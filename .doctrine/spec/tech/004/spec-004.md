# SPEC-004: Patch runner

<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

The patch runner executes SATAN's *patch jobs*: a directive, a repo, a base
branch and the paths a change may touch, queued by the model's
`patch_job_create` tool. It is a container of SPEC-002 (C4 level 2): one
TypeScript process, the `satan-runner` user unit, built as a second binary in
`~/dev/malebolge` beside the interactive daemon (DEC-051). It hosts each job as
one durable agent conversation (pi-durable) on the host; the agent's tools run
inside the oubliette room through pi-env. Work comes back only as git commits
collected into a host-side quarantine, and a human promotes it from Emacs.

It replaced two consumers of a Postgres queue — the elisp runner and the Go
`satan-patcher` — in SL-023 (DEC-050, DEC-063). Its design record is SL-023's
design and DEC-050..DEC-065; this spec holds what outlives that change.
Host facts (unit, paths, keys, room name, config values) live in
`~/flakes/SATAN.md`.

```text
 Emacs (privileged client)                 patch runner (satan-runner, host)
 ┌──────────────────────────┐   NDJSON    ┌───────────────────────────────────┐
 │ patch_job_* tools (RPC)  ├────UDS─────►│ control socket ─ scheduler (1 job)│
 │ inbox (watch stream)     │◄───watch────┤ store: runner.sqlite              │
 │ promote / reject         ├─disposition►│   job_* tables + pi_* tables      │
 └──┬───────────────────────┘             │ harness (pi-durable)              │
    │ fetch quarantine ref                │   model gate ─────────────────────┼──► LLM gateway
    │ CAS-create satan/patch/<id>         │   guard hooks, JobConnection      │
    ▼                                     │ git-channel port (slot | room)    │
 real repos ◄─────── read only ───────────┤                                   │
    ▲                                     └──────┬───────────────┬────────────┘
    │                                   pi-env over ssh    capsule push / collect
    │                                     (door relay)            │
    │                              ┌─────────▼────────┐   ┌───────▼────────┐
    └── Emacs reads quarantine ────┤ room: repo clone │──►│ quarantine     │
                                   │ job/<id> branch  │   │ bare, per repo │
                                   └──────────────────┘   └────────────────┘
```

### Components

| Component | Owns |
|---|---|
| Control socket (`control.ts`, `protocol.ts`) | framing, full-schema parse, the operations below, the watch stream |
| Scheduler (`scheduler.ts`) | FIFO by creation, one job in flight across all repos, woken by submit; the deadline timer |
| Store (`store.ts`) | the one SQLite file and adapter shared with pi-durable; job schema, migrations, the append-only `job_events` audit |
| Job state machine (`jobs.ts`) | allowed transitions and the recovery table, as pure data |
| Policy and prompt (`policy.ts`, `prompt.ts`) | the policy ladder, prompt composition (pure) |
| Model gate (`model-gate.ts`, `ceilings.ts`) | per-job ceilings at the provider boundary |
| Environment (`env.ts`, `guard.ts`) | per-job pi-env environment and connection; room-down recognition; early path check |
| Git channel (`room.ts`) | the door port and its slot and room adapters |
| Collection (`collect.ts`, `classify.ts`) | collect into quarantine, ancestry and allowlist over all commits, class |
| Emacs client (`satan-patch-rpc`, `satan-tools-patch`, `satan-patch-inbox`, `satan-patch-promote`) | the model-facing tools, the inbox, promotion and rejection |

## Responsibilities

Mirrors the structured list: one consumer and one state owner (FR-001); an
unjailed, validated control socket that never writes a real repo (FR-002);
work returned only as git and judged at collection (FR-003); promotion enacted
in Emacs and verified by the runner (FR-004); ceilings at the provider
boundary (FR-005); pausing through room outages without spending (FR-006);
restart by a written recovery table (FR-007); the door behind one port
(NF-001). As an enacting surface it is bound by SPEC-001; it owns ADR-017
ledger rows 4b, 5b, 6b, 8 and 9 (`patch-runner`).

## Contracts

### Control socket

`$XDG_RUNTIME_DIR/satan-runner/control.sock`, directory `0700`, socket `0600`;
one JSON object per line. Every request carries `op` and a client `requestId`;
every response echoes it and is `{ok: true, …}` or `{ok: false, error: {code,
message}}`.

| op | effect |
|---|---|
| `submit` | validate; insert the job and create its conversation; idempotent by `submissionId` |
| `cancel` | queued/preparing → `cancelled`; a running or waiting job is aborted, then collected |
| `status`, `list` | job summaries |
| `result` | class, base and reviewed oids, quarantine path and ref, commits, diffstat, end reason, usage, and the configured real repo path |
| `report-disposition` | record `rejected`, or verify a promotion read-only and record `promoted` |
| `ack` | mark failure notices announced |
| `watch` | replay every job awaiting review and every unacked failure notice, then stream transitions |

Error codes: `invalid_request`, `unknown_job`, `invalid_transition`,
`base_ref_invalid`, `ceiling_above_maximum`, `runner_disabled`,
`receipt_mismatch`. Fields are added, never renamed.

### Job contract

`repo` names a runner-config entry (the oubliette target name), never a path.
`baseRef` is a branch of the real repo, validated by the runner; omitted, the
repo's default branch; `HEAD`, tags and oids are refused. `allowedPaths` are
repo-relative exact files or `/`-terminated prefixes, no globs. Policy (model,
thinking level, ceilings) resolves from runner config — defaults, mode, tag,
repo, then submit fields — clamped to configured maxima; a submit value above
a maximum is refused. The repo itself authors no policy.

`mode` names a runner-config mode. The client sets it from the acting run
mode: the Emacs client stamps the tool context's `:mode-name`, and it is never
a model argument (DEC-068). Each `[mode.<m>]` requires `repos` and
`allowed_paths`, each a non-empty list or `"*"` (unbounded). Submit refuses,
`invalid_request`, a `repo` outside the mode's `repos` or an `allowedPaths`
entry not covered by the mode's `allowed_paths` (the collection matcher,
`disallowedPaths`), naming what the mode allows; the check runs before the
repo lookup. Admission is the scope snapshot: narrowing a mode affects new
submits only — replay, `preparing` and rejoin never re-check it. Scope sits
outside the policy ladder: no tag, repo or submit field sets or widens it
(DEC-069).

### States

```text
queued ─► preparing ─► running ⇄ waiting_room
   │          │           │            │
   ▼          ▼           ▼            ▼
cancelled   failed    collecting ⇄ pending_collection ─► failed
                          │
             ┌────────────┼──────────────┐
             ▼            ▼              ▼
       needs_review     failed       cancelled
        │       │
        ▼       ▼
    promoted  rejected
```

Once a job has run in the room it ends only through collection. A cancelled
job that ran is collected but never promotable. Classes: `complete`,
`partial` (ended by a ceiling, unreadable usage or a room outage; offered
flagged), `no_changes`, `path_violation`, `error`.

### Git-channel port

`refresh` (base branch's tip into the room clone → base oid), `collect`
(`job/<id>` into quarantine → path, ref, oid), `reachable` (the probe for
waits), `checkClone` and `cleanClone` (clone hygiene). Errors are typed:
*unavailable* (the room is down; retried within a bound) versus *failed*
(anything else, including trust failures; never retried as an outage). The
room adapter maps oubliette's verbs: exit 75 or a timeout is unavailable, 1 is
failed, 2 is a refusal (a runner bug). The room probe is the job's own
collect. Each verb runs in its own process group, killed whole on timeout.

### Execution environment

One pi-env remote environment per job, `cwd` the repo's guest path. The
in-room daemon is launched by oubliette's `session` at its configured
absolute path, which supplies the repo's and the room's tools; the runner sets
no guest `PATH`. The runner's ssh checks host keys strictly and never writes
oubliette's `known_hosts`; oubliette's own verbs learn keys. Tools offered:
`read`, `write`, `edit`, `bash`; only `read` is replay-safe.

## Concerns

- **Trust boundary.** The agent and its tools are untrusted; the model and its
  transcript stay on the host, and the room holds no credentials. The runner
  never writes a real repo; collected objects are untrusted until judged.
- **Durability.** One owning process per store (pi-durable has no cross-process
  locking). Job rows and conversation commits are separate writes; the
  recovery table covers every gap.
- **Experimental dependencies.** pi-durable and pi-env are pinned exactly in
  malebolge's `package.json`; upgrades are deliberate and gated by the
  harness and env conformance tests.
- **One seat.** One job in flight across all repos means a wedged job blocks
  every later one (ISS-047); every held state must make progress or end.
- **Deployment drift.** Room and repo config values are literals in
  `~/flakes`, commented with their fleet source, because the fleet exposes no
  room data; the `preparing` guest-path check and the push oid gate catch
  drift. The unit runs malebolge's working tree until CHR-017 pins a build.

## Hypotheses

- **One job in flight is enough.** A single room and one human reviewer make
  per-repo concurrency unnecessary; if review throughput becomes the limit,
  the seat rule is what changes.
- **Pausing beats retrying.** A room outage is long relative to a model turn;
  if outages turn out to be sub-second blips, the pause costs more than a
  retry would.
- **Promotion stays a fetch.** Oubliette has no land verb (its DEC-040); a
  plain fetch of the quarantine ref is enough for every repo the runner serves.

## Decisions

- **D1 — TypeScript, outside the core daemon repo.** The enforcement points
  are hooks in Node libraries; ADR-018 D1 (as amended by REV-006) admits that
  workload fit (DEC-051).
- **D2 — Own store, not Postgres.** Process-private state, one schema owner,
  one commit order with the conversations; no `pg_notify` (DEC-052, ADR-018 D3).
- **D3 — Ceilings at the provider boundary.** Hooks cannot deny a request, so a
  gated `Models` view does (DEC-057).
- **D4 — Recognition by type at the connection.** Room-down is recognised from
  pi-env's typed failure at the per-job connection, never from text (DEC-055).
- **D5 — The door is a port** with slot and room adapters (DEC-060, DEC-065).
- **D6 — Promotion in Emacs** by a plain fetch and compare-and-swap; the runner
  verifies a receipt (DEC-061).
