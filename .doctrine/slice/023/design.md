<!-- doctrine:section sec-1 -->
# 1. Design Problem

SATAN can ask for a code change: its `patch_job_create` tool queues a *patch
job* — a directive, a repo, a base branch and the paths the change may touch.
Something must then run a coding agent on that job, bring the resulting commits
back, and put them in front of the user, who decides whether they land.

Today nothing completes that loop. Two consumers read the same queue (the elisp
runner in `satan/satan-patch-*.el` and the Go `satan-patcher`), and neither has
ever finished a live job (ISS-030, ISS-038, ISS-039, ISS-041). Both were built
for a model this slice replaces: a local worktree or clone, with the agent
jailed on the host.

The new model is oubliette's *room*: a persistent microVM holding clones of the
user's repos, with no network egress and no git credentials. Work leaves it only
as git commits the host fetches into a per-repo *quarantine* (a host-side bare
repo). Oubliette stops the room routinely (its DEC-031), so a run must survive
the room going away under it.

This design introduces one new process, the **patch runner**: a TypeScript
daemon on the host, in `~/dev/malebolge`, that

- is the only consumer of patch jobs and the only owner of their state;
- runs each job as a durable agent conversation (pi-durable) on the host, whose
  coding tools execute inside the room through pi-env;
- enforces the job's path allowlist, spend ceilings and kill switch, and audits
  what it does, whether or not Emacs is running;
- collects the job's commits into quarantine, classifies them, and offers them
  for review.

Emacs keeps three things: the producer tool (a thin client that submits to the
runner), the inbox notice, and the human approval act that promotes reviewed
commits into the real repo as a branch. Both old runners are deleted, and the
`patch_jobs` tables leave Postgres.

**Boundary.** Inside this design: the runner, its control socket and store, the
Emacs client changes, the cutover, and the authority-ledger changes. Outside it:
the room and its door (ssh ingress; oubliette SL-005), the room's git channel
and `session` launcher (oubliette SL-006); the LLM gateway, its keys and budgets
(`~/flakes` SL-011). Where the runner touches the door — git channel, door
configuration, execution environment — this design defines a port with two
adapters: a *slot* adapter (an oubliette capsule slot standing in for the room;
the live rung until SL-006 ships) and a *room* adapter built now against
fixtures of oubliette SL-006's interface (§5.2). It does not design oubliette's
side. There is no land verb (oubliette DEC-040): promotion is Emacs's plain
fetch of the quarantine ref.

<!-- doctrine:section sec-10 -->
# 2. Current State

```mermaid
flowchart LR
  tool["patch_job_create<br/>(satan-tools-patch.el)"] -->|INSERT + pg_notify| pg[("satan_memory<br/>patch_jobs, patch_job_events")]
  pg -->|LISTEN / idle timer<br/>SKIP LOCKED claim| el["elisp runner<br/>satan-patch-runner.el"]
  pg -->|LISTEN + 30 s tick<br/>SKIP LOCKED claim| go["Go satan-patcher<br/>(systemd unit)"]
  el --> wt["local worktree<br/>+ jailed pi"]
  go --> cl["local clone<br/>+ bwrap pi"]
  el -->|state writes| pg
  go -->|state writes| pg
  pg -->|done/failed notify| inbox["satan-patch-listener.el<br/>→ satan-patch-inbox.el (org append)"]
```

Purpose: show why the queue has two writers and two schema owners today.

**Producer.** `satan-tool/patch-job-create` (`satan/satan-tools-patch.el:83`)
validates arguments, defaults `base_ref` to `"HEAD"` (:97), inserts a row and
notifies. Sibling tools read status/result, cancel, and clean up worktrees.

**Elisp runner** (`satan-patch-{runner,worktree,adapter,adapter-pi,prompt,classify,store,listener}.el`,
~1.9k lines, 85 ert tests). Claims a row, prepares a local worktree, composes
the prompt, spawns jailed pi with an 1800 s timeout, checks changed files
against the allowlist, classifies, appends to the org inbox. Every psql and git
call is a synchronous `call-process` on Emacs's main thread. The in-flight job
lives only in memory, so an Emacs restart orphans it. `satan-patch-runner-enabled`
defaults off, but the editor config turns it on (ISS-039).

**Go `satan-patcher`** (`~/dev/satan-patcher`, ~5k lines, 92 tests). Same claim
query, a policy ladder (defaults → mode → tag → repo pin → row), prompt
composition, a pi JSONL classifier, crash reconcile of `running` rows. It owns
migration 0006 on `satan_memory`, making `patch_jobs` a two-owner table
(SPEC-002 REQ-013, RSK-015). All 17 recorded jobs failed. Known defects in the
Go code itself: adapter axis never dispatched, checks never run, a silently
skipped missing prompt file (CHR-003), the repo pin read from the host working
copy rather than the base ref.

**Contract skew.** `HEAD` works for `git worktree add` but not for Go's
`clone --branch` (ISS-041).

**Missing everywhere.** No SATAN-owned ceiling beyond the timeout (SPEC-001
REQ-004), no audit of patch-job actions (REQ-003), no promote command (the
`accepted_external` and `stale` states have no writer), and no owner for a run
outliving a VM stop.

**What exists to build on.** `~/dev/malebolge` (~750 lines TypeScript) hosts
interactive SATAN on pi-durable: SQLite store, NDJSON framing
(`src/ndjson.ts`), a unix-socket server (`src/unix-socket.ts`, `src/daemon.ts`),
model catalog wiring (`src/models.ts`), config from the environment
(`src/config.ts`), Biome + tsc + vitest behind `just check`. The option-D spike
(EVD-005) drove a capsule slot from a host pi-durable harness through pi-env
over the slot's relay: a killed tool connection failed one call, and the model
recovered and committed.

<!-- doctrine:section sec-11 -->
# 3. Forces & Constraints

**Binding governance** (confirmed for this run):

| Source | How it binds this design |
|---|---|
| POL-001 (extraction policy) | Queue, dispatch and quarantine fetch do not use the editor as an editor, so they leave elisp; the promotion surface stays. Cutover, never addition. Every extraction has a disable switch and holds its ceilings with Emacs absent. Ported test corpora become acceptance fixtures. Rust is the daemon target, with recorded workload-fit exceptions. |
| ADR-017 §1, §3, §4 | Emacs owns the human approval surfaces. Each authority item has exactly one owner, recorded in the ledger with a transition line (INV-1..3). A daemon fails closed when the client is absent. |
| ADR-018 D1, D3 (as amended 2026-10-18 by REV-006) | A component whose enforcement points are hooks inside a library that exists only in another language may live outside the daemon repo by workload fit, with one ledger owner per item. Postgres is the *shared* state store; process-private state may live in its own store. The control plane is UDS RPC; no new `pg_notify` control traffic. |
| ADR-018 D5 | No new stateful layer lands in elisp. |
| ADR-018 OQ-2 / OQ-3 | Open: the global RPC shape. The runner's socket is its own surface and does not front-run them. |
| SPEC-001 REQ-001, -003, -004, -005, -007, -009, -010 | Schema-validated actions; audit; ceilings; kill switch fails closed; request/response lifecycle; no dual enforcement; fail closed. |
| SPEC-002 REQ-013, REQ-016 | One schema owner per store. Every jail holding model output has a test-asserted profile with no protocol bypass (here: the runner socket path is never bound into a jail). |
| SPEC-003 OQ-3 | This slice decides the surviving runner and its spec (DEC-064). |
| DEC-043, DEC-049 | Gateway budgets are not SATAN ceilings. Provider-credential custody is not a ledger item. |
| oubliette DEC-031 | Room stops are routine and must be cheap; persistent state survives them. |
| oubliette DEC-040, DEC-047 | No land verb: promotion is a plain fetch of the quarantine ref. One `known_hosts` per room under alias `room-<room>`, first contact `accept-new` over the host-local door socket. |
| CON-003, CON-004 | The runner runs as the oubliette module owner (door socket `0600`); the room user carrying the runner's key is declared `{ uid; keys; }`, uid 1000-29999. |

Checked and ruled out: ADR-001 (perception/cognition), ADR-002 (proposed, not
binding), RFC-017/RFC-018 (open — evidence), REQ-019..025 (harness-only).

**Technical forces.**

- pi-durable and pi-env exist only as Node libraries, are experimental, and
  change without notice. Versions are pinned (1.3.0 today).
- pi-durable allows one owning process per storage, with no cross-process
  locking. A tool interrupted by a process crash reruns only if declared
  `replay: "safe"`.
- pi-durable's hooks: `beforeTool` (block or rewrite arguments), `afterTool`
  (replace the result), `beforeRequest` (replace one request's messages — not
  its options), `afterResponse`, `onYield`, `afterTools`. Spend is tracked in
  `pi.usage`, including failed and aborted attempts; there is no built-in
  ceiling.
- `bash` in the room can write any path, so a per-tool-call check cannot be the
  authoritative path allowlist.
- The room has no egress and no credentials; the model call must happen on the
  host.
- Oubliette's door is pinned (SL-005, ASM-005 validated); its room git channel
  and `session` launcher are designed in SL-006, which is neither locked nor
  shipped. A slot offers the same shape — ssh as an agent user through a relay,
  host-side collect into a bare quarantine — and stays the live rung meanwhile.

<!-- doctrine:section sec-12 -->
# 4. Guiding Principles

1. **One owner, one enforcement site.** Every authority the runner exercises —
   job lifecycle, RPC validation, path allowlist, ceilings, audit, its own kill
   switch — is the runner's alone, recorded in the ledger. Emacs validates tool
   arguments for the model's sake only; it never restates a runner check.
2. **The runner never writes a real repo.** It reads real repos (to resolve a
   base branch, to verify a promotion) and writes only the room and quarantine,
   through the git-channel port. Promotion is a human act enacted in Emacs.
3. **Authoritative checks run on what actually travels.** The path allowlist and
   ancestry are checked on the collected commits, not on tool calls. Per-call
   checks are early feedback.
4. **Durable by construction, not by repair.** Job rows and transcripts share one
   SQLite file and commit together. Restart is "reopen and follow the recovery
   table", not reconcile-and-guess.
5. **Spend nothing while blocked.** A room outage pauses a job; it does not burn
   model turns on failing tool calls.
6. **Fail closed.** An unreachable runner fails the Emacs tools; an unreadable
   usage figure denies the next request; a disabled runner schedules nothing.
7. **Ports at the door.** Everything that depends on oubliette's verbs sits
   behind one port with a slot and a room adapter; `[door] kind` picks one.
   SL-006 shipping changes config, not design.
8. **Port logic, not code.** The policy ladder, prompt composition, allowlist
   semantics and classification move from the old runners as behaviour, pinned
   by their old tests turned acceptance fixtures.

<!-- doctrine:section sec-13 -->
# 5. Proposed Design

## 5.1 System Model

```mermaid
flowchart LR
  subgraph emacs["Emacs (privileged client)"]
    tool["patch_job_* tools<br/>(RPC client)"]
    inbox["inbox<br/>(watch-driven)"]
    promote["promote / reject<br/>command"]
  end
  subgraph runner["patch runner — TS process, ~/dev/malebolge"]
    ctl["control socket<br/>NDJSON"]
    sched["scheduler<br/>FIFO, one job"]
    harness["pi-durable Harness<br/>one conversation per job"]
    guard["guard extension<br/>hooks: pause, early path check"]
    gate["model gate<br/>ceilings at provider boundary"]
    envw["JobConnection<br/>room-down detection"]
    chan["git-channel port"]
    classify["collect + classify"]
    db[("runner.sqlite<br/>job_* tables + pi_* tables")]
  end
  gw["LLM gateway<br/>(~/flakes)"]
  subgraph oub["oubliette (room; slot until SL-006 ships)"]
    door["door: agent user<br/>+ relay socket"]
    clone["repo clones<br/>job/&lt;id&gt; branches"]
    quar[("quarantine<br/>bare repo per repo")]
  end
  real[("real repos")]

  tool -- submit/status/result/cancel --> ctl
  inbox -- watch --> ctl
  promote -- report-disposition --> ctl
  ctl --> sched --> harness
  harness --- guard
  harness --> gate -- model requests --> gw
  harness --> envw -- "tools via pi-env (ssh over relay)" --> door --> clone
  chan -- refresh (push base) --> clone
  chan -- collect --> quar
  classify --> chan
  harness --- db
  sched --- db
  promote -- "fetch quarantine ref → temp ref; == reviewed_oid → create satan/patch/&lt;id&gt; (CAS)" --> real
  quar -. read by promote .-> promote
  chan -. "read base branch / verify promotion" .-> real
```

Purpose: who owns what, and which edges cross a trust boundary.

Non-obvious edges:

- **Model requests go host → gateway.** The room needs no model door and holds
  no key. The runner is a gateway client like the harness and malebolge's
  interactive daemon; per-job model choice comes from the policy ladder.
- **Tools reach the room only through pi-env.** pi-env runs a small daemon in
  the guest over ssh as the agent user, through the door's relay socket
  (`ProxyCommand` in a runner-owned ssh config, as EVD-005 proved on a slot);
  in a room it is started under the job's repo's `session` launcher (§5.2).
  The guest sees tool arguments only; prompt, transcript and model output stay
  on the host.
- **The runner reads the real repos and never writes them.** Reads: resolve and
  validate `base_ref`, and verify a promotion. The only real-repo write is
  Emacs's promotion fetch.
- **Promotion does not touch the socket.** Emacs fetches from quarantine itself,
  then reports a disposition the runner verifies (DEC-061, DEC-058).

**Ownership by party.**

| Party | Owns |
|---|---|
| Emacs | producer tool (argument schema for the model), inbox notice, promote/reject command and its git fetch |
| Patch runner | queue, scheduling, job state and its schema, RPC validation, policy ladder, prompt composition, harness hosting, ceilings, pause/resume, collection, classification, job audit, its kill switch |
| Oubliette | room, door, `session` launcher, `push`/`collect` verbs and the quarantine, the room's `known_hosts`; stop (orderly guest reboot via the stop key; in-flight work cut). No land verb (its DEC-040). |
| Gateway | model routing, provider keys, deployment budgets |

**Module layout in `~/dev/malebolge`.** A second binary beside the interactive
daemon, sharing framing, socket and model wiring; separate process, store and
disable switch (POL-001: one binary per extraction).

| Module | Responsibility | Pure? |
|---|---|---|
| `src/ndjson.ts`, `src/unix-socket.ts` | shared framing and listen/connect (existing) | — |
| `src/models.ts` | shared model catalog; gains the gateway-routed provider both binaries use | — |
| `src/runner-main.ts` | entry: load config, open store, open harness, start scheduler and socket | no |
| `src/runner/config.ts` | parse runner config: maxima, repos, mode/tag policy, prompt path, door settings (slot or room kind) | yes |
| `src/runner/protocol.ts` | full schema parse of every control operation | yes |
| `src/runner/store.ts` | SQLite file, shared adapter, job schema and migrations, job queries | no |
| `src/runner/jobs.ts` | state machine: allowed transitions and the recovery table | yes |
| `src/runner/policy.ts` | policy ladder resolution | yes |
| `src/runner/prompt.ts` | prompt composition | yes |
| `src/runner/ceilings.ts` | budget arithmetic: remaining allowance, warning threshold, cap | yes |
| `src/runner/model-gate.ts` | `Models` view wrapping `streamSimple` and `completeSimple`: attempt counter, ceiling denial, output cap | no (thin over `ceilings.ts`) |
| `src/runner/env.ts` | per-job pi-env `ExecutionEnv` over a `JobConnection` (DEC-055: observes the typed lost failure, records `pause_requested` durably) layered on the door's daemon connection — slot: pi-env's `sshConnection`; room: the `session` launch command (§5.2) | no |
| `src/runner/guard.ts` | pi-durable extension: `afterTool` pause trigger (reads `pause_requested`), `beforeTool` early path check | no (thin over pure parts) |
| `src/runner/room.ts` | git-channel port, reachability probe; slot adapter and room adapter (argv builders and exit-code mapping pure) | no |
| `src/runner/classify.ts` | path allowlist match, ancestry result, class from end reason | yes |
| `src/runner/scheduler.ts` | FIFO, one in flight, wake on submit, deadline timer | no |
| `src/runner/control.ts` | serve operations and the watch stream | no |
| `src/runner/audit.ts` | append `job_events` | no |

<!-- doctrine:section sec-14 -->
## 5.2 Interfaces & Contracts

### Control socket (DEC-058)

`$XDG_RUNTIME_DIR/satan-runner/control.sock`; directory `0700`, socket `0600`.
Authentication is same-uid plus one invariant: the path (and its directory) is
never bound into any jail. It sits in its own directory, not malebolge's
`$XDG_RUNTIME_DIR/satan/`, so a jail binding that directory cannot reach it.

One JSON object per line, malebolge's framing. Every operation except `watch`
is a short request/response the runner answers without waiting on any job;
`watch` is the one long-lived stream. Every request carries `op` and a
client `requestId`; every response echoes `requestId` and is `{ok: true, ...}`
or `{ok: false, error: {code, message}}`. The runner parses the **full schema**
of every operation before acting (SPEC-001 REQ-001 on its own surface) and
answers `invalid_request` otherwise; unknown keys are refused.

| op | request | response | effect |
|---|---|---|---|
| `submit` | `submissionId`, `mode`, `directive`, `repo`, `allowedPaths`, optional `baseRef`, `tags`, `context`, `source`, `ceilings` (each may only lower the configured maximum) | `jobId`, `state` | validate; insert job (`conversation_id` null) + event; create the conversation and record its id; wake scheduler. Same `submissionId` returns the existing job (idempotent). |
| `cancel` | `jobId`, `reason` | `state` | queued → cancelled; running/waiting → abort, then collect (§5.4) |
| `status` | `jobId` | job summary | read |
| `list` | optional `states[]`, `limit` | summaries | read |
| `result` | `jobId` | class, `baseOid`, `reviewedOid`, quarantine path + ref, commits, diffstat, end reason, usage | read |
| `report-disposition` | `jobId`, `disposition: promoted \| rejected`, for promoted `branch` | `state` | rejected: record. promoted: verify (read-only) that `refs/heads/satan/patch/<id>` in the real repo resolves to `reviewedOid`, else refuse `receipt_mismatch` |
| `ack` | `jobIds[]` | — | marks failed/cancelled notices as announced (sets `announced_at`) |
| `watch` | — | stream | on connect, one frame per `needs_review` job and per unacked `failed`/`cancelled` job; then `job_changed` frames on every transition; ends on disconnect |

Error codes: `invalid_request`, `unknown_job`, `invalid_transition`,
`base_ref_invalid`, `ceiling_above_maximum`, `runner_disabled`,
`receipt_mismatch`.

Example:

```json
→ {"op":"submit","requestId":"r1","submissionId":"sat-7f3c","mode":"fix","directive":"…","repo":"satan","allowedPaths":["satan/satan-db.el","satan/test/"],"tags":["lint"]}
← {"requestId":"r1","ok":true,"jobId":"pj-01JABC…","state":"queued"}
→ {"op":"report-disposition","requestId":"r2","jobId":"pj-01JABC…","disposition":"promoted","branch":"satan/patch/pj-01JABC…"}
← {"requestId":"r2","ok":false,"error":{"code":"receipt_mismatch","message":"satan/patch/pj-01JABC… is 3e1f…, reviewed 9a0c…"}}
```

There is no promote operation. Nothing reachable over this socket writes a real
repo.

### Job contract (DEC-059)

- `repo` names an entry in runner config (real repo path, guest clone path,
  default branch) — a name, not a path, equal to the oubliette target name.
  Unknown repo → `invalid_request`.
- `baseRef` must be a branch of the real repo: `git check-ref-format --branch`
  and `refs/heads/<baseRef>` exists. Omitted → the repo entry's default branch.
  `HEAD`, tags and oids are refused (`base_ref_invalid`). The producer no longer
  defaults it (ISS-041).
- `allowedPaths`: non-empty, repo-relative. An entry ending `/` is a prefix;
  otherwise an exact file. No globs (ported from
  `satan-patch-worktree-path-allowed-p`). Leading `./` is stripped; `..`
  segments and absolute paths are refused.
- The Emacs tool's argument schema stays the model-facing gate (ledger row 1);
  the runner is the authoritative validator.
- Dropped from the contract: `branch`, `worktree_path`, `adapter`, `checks`,
  and the `patch_job_cleanup` tool. The runner runs no checks; a directive may
  ask the agent to run them in the room. Host-side checks are a later slice.

### Policy ladder and prompt (DEC-056)

Resolved at `preparing`, low → high precedence: built-in defaults → config
`[defaults]` → `[mode.<m>]` → `[tag.<sorted tags joined>]` (longest match) →
the repo's entry in runner config → submit fields. The repo pin is that
config entry; the runner reads nothing policy-bearing from the repo itself
(the Go runner's `.satan-patch.toml` is not ported), so a repo cannot author
its own policy. Resolves `model`,
`thinkingLevel`, and ceilings. Every resolved ceiling is clamped to the config
`[maxima]`; a submit value above the maximum is refused
(`ceiling_above_maximum`), not clamped. The resolved policy is written to
the job row and audited. The policy is runner config: ADR-018 D2's policy
artifact does not exist yet, and the runner restates nothing from it (DEC-059).

The prompt is composed from the corpus prompt file at the explicit path in
runner config (no fallback; unreadable → the runner refuses to start, closing
CHR-003), the mode/repo prompt fragments in config, and the job fields
(directive, allowed paths, base branch, job branch, the commit-your-work and
notes conventions). Composition is a pure function of (prompt text, resolved
policy, job).

### Git-channel port (DEC-060)

```ts
interface GitChannel {
  /** Make base_ref's tip present in the room's clone; return its oid. */
  refresh(repo: RepoConfig, baseRef: string): Promise<Oid>;
  /** Fetch job/<id> from the room into quarantine; return the ref and its oid. */
  collect(repo: RepoConfig, jobId: JobId): Promise<{ ref: string; oid: Oid }>;
  /** Reachability probe for pause/resume and pending_collection (room: this job's collect). */
  reachable(job: JobId): Promise<boolean>;
}
```

Errors are typed: `ChannelUnavailable` (room down — retry later) vs
`ChannelFailed` (anything else); `reachable` answers false for unavailable and,
room, throws `ChannelFailed`. Two adapters, chosen by `[door] kind`; nothing
outside `room.ts` and `config.ts` knows which. The job branch `job/<id>` is
created at `base_oid` in the guest clone through the execution environment
during `preparing`. Only `job/<id>` is collected; uncommitted work never
travels.

**Slot adapter** (live rung until SL-006 ships). `capsule <slot>
provision`/`collect`/`ssh true`; `capsule` exits 1 for every failure, so a
failed verb is typed by probing afterwards. Refresh first switches the guest
clone back to `work` (`returnToWork`: slot-only — `provision` refuses off
`work`). Collect fetches every guest head; only `job/<id>` is read.

**Room adapter** — against the interface in oubliette SL-006 design sec-6,
*provisional until SL-006 locks*; built and tested on fixtures now, live when
SL-006 ships. `<room>` and `<repo>` are config: the door's room name and the
`[repo.*]` key, which must equal the oubliette target name.

| Port member | Room adapter |
|---|---|
| `refresh` | check `base_ref` still exists in the real repo; `capsule <room> push <repo> <base_ref>` → stdout `<oid>`, which is `base_oid` (exactly what the guest received; push resolves the branch in the target's host checkout, the same checkout as `[repo.*].path`); the guest-side steps follow in `preparing` (§5.4) |
| `collect` | `capsule <room> collect <repo> job/<id>` → `refs/capsule/<room>/heads/job/<id>` in the repo's `quarantine` (`/var/lib/capsule/collect/<room>/<repo>.git`); stdout `<oid>\t<ref>` (git ls-remote order; progress and errors on stderr), the ref required to be exactly that name; the adapter reads the ref from the quarantine, and a stdout oid or ref that differs from it is `ChannelFailed` |
| `reachable` | job-scoped: the job's `collect` (above), bounded by the repo's `transfer_timeout_s`; 0 → true; 75 or timeout → false; 1 and 2 throw, as below — a trust failure is never downtime. Idempotent: `job/<id>` exists from `preparing` on, and a later collect overwrites the quarantine ref. Not `capsule <room> ssh <user> true`: that is the human's door, outside the channel's exit contract (stopped → 1, changed key or refused auth → 255) and interactive |
| errors | exit 75, or no exit within the verb's timeout (`push`/`collect`, the probe included: the repo's `transfer_timeout_s`) → `ChannelUnavailable` (room down, guest frozen, or a hung prompt; no probe needed; a timeout is audited as `channel_timeout`, distinct from exit 75; retried within `max_room_wait` / `max_pending_collection`); 1 → `ChannelFailed`, including authentication and a changed host key (a trust failure, not downtime — never retried as a pause); 2 → `ChannelFailed` marked a refusal (a runner bug: argv or config), audited as such — except that exit 2 from `push` first re-checks `refs/heads/<base_ref>` in the real repo, and an absent branch is `base_ref_invalid` (deleted between the runner's check and push's own resolve) |

**Killing a verb.** Each verb is spawned as the leader of its own process group
(`capsule` → `capsule-room-git` → git → ssh → socat). On its timeout the
runner signals the whole group (`kill(-pgid)`: TERM, then KILL after a grace)
and awaits the leader's exit before reporting `ChannelUnavailable`, so no
orphaned git still holds a quarantine or guest ref lock when the retry runs.
`execFile`'s own timeout signals only the direct child and is not used.

`push` never touches the guest worktree (it writes `refs/host/<branch>`), so
the runner owns clone hygiene, in two places:

- **Clean after collect.** After a successful `collect` of `job/<id>`, the
  runner runs, through the env, `git reset --hard` and `git clean -ffd` in
  `guest_path` (ignored files, e.g. build caches, are kept; `-ff` also removes
  untracked nested repos). This is the only automatic clean anywhere. The job's commits
  are already in quarantine, so only uncollectable residue is discarded. A
  clean that fails (room down, crash) leaves the tree dirty for the check below.
  Safe only because the job still holds the scheduler's one seat while
  `collecting` or `pending_collection` (§5.4 Scheduling): no other job can be
  live in that clone.
- **Check in `preparing`, never clean.** Through the env: (1) `test -d
  <guest_path>/.git` — the configured `guest_path` is the target's `guestPath`;
  (2) clean-tree check, `git status --porcelain` empty (untracked counted,
  ignored not); (3) `git switch -c job/<id> <base_oid>`. A still-dirty tree
  fails closed: `failed(error)`, reason `dirty_clone`, paths audited.
  `preparing` discards nothing, so it can never destroy work that was not
  collected. A fresh room clone is `git init` on an unborn branch with no
  commits; step 3 works there once `push` delivered the oid. The checks run
  only before the initial prompt is admitted: on a restart redo whose
  submission record exists, the agent may already have worked in the clone, so
  the redo skips them and records `running` (§5.4 recovery).
- **Env uses outside `running`** (the `preparing` checks and switch, the clean)
  go through a `JobConnection` with a *counting* observer: a lost failure makes
  that step `ChannelUnavailable` and never writes `pause_requested` or a pause
  event. Only the running job's tools use the pausing observer.
- **Operator remediation** of a `dirty_clone` (every later job on that repo
  fails until it is resolved): inspect and clean by hand through `capsule
  <room> ssh <user> -- git -C <guest_path> status` / `reset --hard` / `clean
  -ffd`. A `clean-clone <repo>` control-socket operation, invoked from Emacs,
  is deferred to the backlog.

### Execution environment

pi-env's `RemoteExecutionEnv`, one per job, `cwd` = the repo's `guest_path`,
over two layered `Connection`s, both per job (`connect(repo)`):

- **outer: `JobConnection`** (DEC-055) — a subclass delegating `info()`,
  `session()`, `request()`; recognises the typed lost failure and records
  `pause_requested` before rethrowing (§5.4). Indifferent to how the daemon
  starts.
- **inner: the daemon connection**, one runner-owned `command` function for
  both kinds: at each start it runs `detectPlatform(target)` (first time) and
  `deployDaemon(target, remote)`, then returns `[ssh, ...sshArguments(target,
  true), <launch>]`; pi-env appends `serve --token <hex>`. Slot launch: the
  daemon path (pi-env's `sshConnection` recipe). Room launch: `<session_path>
  <repo> -- <daemon path>`. `session` (oubliette SL-006) is invoked by its
  absolute path, the configured `session_path` (documented value
  `/run/current-system/sw/bin/session`; I13), because non-interactive ssh does
  not inherit the login `PATH`. It puts
  that repo's tool set on `PATH`, `cd`s to its `guestPath` and
  `exec`s the daemon, so every tool command inherits the repo's tools. `<repo>`
  is the job's `RepoConfig` name. All three helpers are exported by pi-env
  1.3.0 (`dist/index.d.ts`, from `ssh.ts`); the room command is
  `sshConnection`'s own recipe with the launch word replaced.

The ssh target comes from door config: `user`, `identity`, `known_hosts`,
`host_key_alias`, `ssh_config` (§5.3), and a host. Room door values (oubliette
SL-006 sec-6): `ssh_config` holds `ProxyCommand socat -
UNIX-CONNECT:/run/capsule-room/<room>/ssh.sock` and `ServerAliveCountMax`;
login user = the room's `repos.user`; `known_hosts` =
`/var/lib/capsule/room/<room>/known_hosts` (oubliette's file; the runner only
reads it); alias `room-<room>`. The room needs no guest address: the socat
`ProxyCommand` and `HostKeyAlias` bypass `HostName`, so the runner passes the
configured room name as the placeholder ssh host; `host` is a slot-only key.

Frozen guest: pi-env's `Connection` pings the daemon every 5 s and tears the
session down after 30 s of silence (`SILENCE_LIMIT_MS`), a typed lost failure
→ pause; that fires first and is what the live rung tests. ssh's keepalive is a
backstop only: `sshArguments` fixes `ServerAliveInterval=15` on the command
line, so only `ServerAliveCountMax` (door `ssh_config`) is ours, and at ssh's
default of 3 it fires at 45 s. The channel verbs are bounded by
their timeouts instead (§5.2 errors).

**Host keys — the one statement.** The runner's ssh is strict: its daemon
command calls `sshArguments(target, true)` (`StrictHostKeyChecking=yes`;
pi-env's `strictHostKeys` parameter, `false` meaning `accept-new`), and
`detectPlatform`/`deployDaemon` use the same strict default. The runner never
writes oubliette's `known_hosts`. Keys are learned only by oubliette: the room
adapter's first step is `capsule <room> push` in `refresh`, whose program uses
`accept-new` (oubliette DEC-047: TOFU over a host-local socket into a VM this
host booted), and it precedes the first env command. A daemon start that
finds the key unknown or changed fails strict; that is a trust failure, not
downtime. `detectPlatform`/`deployDaemon` throw it typed
(`HostKeyUnknownError`/`HostKeyChangedError`), but `Connection` rewraps any
command-function rejection as `RemoteError{spawn_error, lost: true}`, erasing
the type. So the runner's command function catches the two typed errors and
records a per-job trust failure (by type, before rethrowing); `JobConnection`
consults it before treating a lost failure as a pause. With a trust failure on
record: in `preparing` → `failed(error)`, reason `host_key`; in `running` → abort,
`end_reason = error`, then `collecting` (I12) — never `waiting_room`. The same
holds on every reconnect, restart redo included. A changed key is refused by
oubliette's verbs too (exit 1). Slot keys: oubliette's slot transport checks
no keys and records none, so the runner's slot `known_hosts` is seeded once
out of band (pi-env `scanHostKey` + `acceptHostKey`, operator step in
`~/flakes/SATAN.md`); unseeded, the first start is a trust failure. The runner runs as the oubliette
module owner (CON-003: door socket `0600`).

**Identities.** satan has its own dedicated ssh key, the runner's `[door]
identity`; the runner's pi-env daemon ssh uses it. The capsule channel verbs,
run as the module owner, authenticate with that user's default identity
(oubliette's room verbs take no identity option). The room user's declaration
`{ uid; keys; }` lists both keys (CON-004) — a deployment fact for
`~/flakes/SATAN.md`. The verbs run ssh without `BatchMode`; a prompt that hangs
is bounded by the verb's timeout and reads as `ChannelUnavailable`. The live
room rung checks that push and collect run non-interactively as the runner
user. pi-env deploys its daemon under the agent's home, which
must be writable and executable (ASM-005's open caveat; checked at the live
room rung).

### Tools offered to the model

pi-durable's built-in `read`, `write`, `edit`, `bash`, run through the job's
environment. `read` is wrapped with `wrapTool` as `replay: "safe"`; the rest
stay unsafe (DEC-054).

### Emacs side

- `patch_job_create`, `_status`, `_result`, `_cancel`: rewritten as RPC clients
  of the socket. Tool handlers are synchronous (`satan-tool-dispatch` expects
  an immediate result, from both broker and MCP), so each call is a bounded
  synchronous request on a fresh local connection with a short deadline; no
  change to the dispatch path. Runner unreachable or deadline passed → the tool
  returns an error; nothing is queued locally.
- `patch_job_create` keeps creating the observer's intervention: after the
  runner's `submit` response, Emacs creates one `patch_job` intervention
  targeting the runner's job id and returns `intervention_id`. Each tool call
  mints one `submissionId` and sends it once — Emacs never retries a submit —
  so one tool call yields at most one job and one intervention. A failed
  intervention create returns ok with `job_id` and an `intervention_error`
  instead of `intervention_id`. This departs from today, where the tool returns
  an error although the job is already queued, which invites the model to
  submit a duplicate. A lost submit response returns an error; that job has no
  intervention.
- Inbox: a watch connection, reconnecting with backoff. A `needs_review` frame
  appends a review entry; a `failed` or `cancelled` frame appends a notice and
  is then acked. Appends are idempotent by job id, so a resend after a lost ack
  is harmless.
- `satan-patch-promote` / `satan-patch-reject` commands on an inbox entry
  (§5.4, promotion sequence).

<!-- doctrine:section sec-2 -->
## 5.3 Data, State & Ownership

### One SQLite file (DEC-052, DEC-054)

`$XDG_STATE_HOME/satan/runner/runner.sqlite` (beside, not inside, malebolge's
`durable/session.sqlite`). One `NodeSqliteDatabase` adapter is opened and used
for both pi-durable (`SqliteStorage.open(database, { prefix: "pi_" })`) and all
host queries, so host writes queue behind pi transactions instead of bypassing
them. The runner is the only process that opens the file, the only schema
owner and the only migrator. Tests use in-memory databases.

```sql
CREATE TABLE job_schema (version INTEGER NOT NULL);

CREATE TABLE jobs (
  id              TEXT PRIMARY KEY,          -- pj-<ULID>
  submission_id   TEXT NOT NULL UNIQUE,      -- idempotent submit
  conversation_id TEXT UNIQUE,               -- pi-durable conversation; null until created
  state           TEXT NOT NULL CHECK (state IN ('queued','preparing','running',
                    'waiting_room','collecting','pending_collection','needs_review',
                    'promoted','rejected','cancelled','failed')),
  mode            TEXT NOT NULL,
  directive       TEXT NOT NULL,
  repo            TEXT NOT NULL,
  base_ref        TEXT NOT NULL,             -- resolved branch name
  allowed_paths   TEXT NOT NULL,             -- JSON array
  tags            TEXT NOT NULL DEFAULT '[]',
  context         TEXT NOT NULL DEFAULT '{}',
  source          TEXT NOT NULL DEFAULT '{}',
  policy          TEXT,                      -- resolved ladder output, JSON
  base_oid        TEXT,                      -- set at refresh
  end_reason      TEXT,                      -- completed|ceiling_exceeded|usage_unavailable|cancelled|room_unavailable|error
  pause_requested INTEGER NOT NULL DEFAULT 0, -- written by the JobConnection
  pause_count     INTEGER NOT NULL DEFAULT 0, -- waiting episodes; names resume messages
  state_entered_at TEXT NOT NULL,           -- set on every transition; bounds waits
  parked_at       TEXT,                      -- first disabled startup that parked this job; null when not parked
  running_since   TEXT,                      -- start of the current running segment
  active_ms       INTEGER NOT NULL DEFAULT 0, -- closed running segments
  model_requests  INTEGER NOT NULL DEFAULT 0, -- provider attempts, counted by the model gate
  reviewed_oid    TEXT,                      -- immutable once set
  quarantine_ref  TEXT,
  class           TEXT,                      -- complete|partial|no_changes|path_violation|error
  failure         TEXT,                      -- reason for failed/cancelled, JSON
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  started_at      TEXT,
  finished_at     TEXT,
  announced_at    TEXT                       -- failed/cancelled notice acked by Emacs
);
CREATE INDEX jobs_state_created ON jobs(state, created_at);

CREATE TABLE job_events (                    -- append-only audit (DEC-057)
  seq     INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id  TEXT NOT NULL REFERENCES jobs(id),
  at      TEXT NOT NULL,
  kind    TEXT NOT NULL,                     -- submitted|transition|policy|blocked_tool|warning|ceiling|pause|resume|collected|classified|disposition|...
  payload TEXT NOT NULL DEFAULT '{}'
);
-- triggers refuse UPDATE and DELETE on job_events
```

A state change and its `job_events` row are one host transaction. Host
transactions and pi-durable commits are separate but ordered through the one
adapter's queue. Where the two must agree, the runner writes in a fixed order
and the recovery table (§5.4) covers each gap:

- **Creation** (DEC-052): job row first, `conversation_id` null; then the
  conversation is created and its id recorded; the job's first submission uses
  `requestId` = job id, so resubmitting after a crash is a no-op. pi-durable's
  `createConversation` takes no `requestId`; a conversation created but not
  recorded before a crash is never submitted to and is left inert.
- **Initial submission**: the job stays `preparing` until the initial prompt is
  admitted; only then is `running` recorded.
- **Warning**: the `job_events` warning row is the receipt of an admitted
  `warn-<job id>` steer; placement is read from its submission record.
- **Pause**: the `JobConnection` records `pause_requested` before the hook runs
  and before the abort; `pause_count` is incremented with `waiting_room`.

### What is audited

`job_events` records what the runner *enacts*: submission (with the validated
request), resolved policy, each state transition, blocked tool calls,
warnings, ceiling hits, pause and resume, collection result, classification,
and dispositions (with verification outcome). The pi-durable transcript records
what the model and tools did. Together they answer "what happened to this job"
without Emacs; read with `sqlite3` or the `status`/`result` operations.

### Runner config

One file (TOML), path from the unit's environment. Read once at start; a parse
error refuses start.

```toml
enabled = true
prompt_file = "~/satan-corpus/prompts/patch-agent.md"   # explicit, no fallback

[maxima]                       # absolute; a job may only lower these
model_requests = 200
cost_usd = 2.00
tokens = 2_000_000
active_wall_clock_s = 3600
soft_threshold = 0.8
max_room_wait_s = 21600
max_pending_collection_s = 86400

[defaults]
model = "gateway/deepseek-flash"

[mode.fix]
[tag."lint"]

[repo.satan]                   # key = the oubliette target name
path = "~/dev/satan"
guest_path = "/work/satan"     # the target's guestPath, /work/<target>
default_branch = "main"
quarantine = "/var/lib/capsule/collect/assistant/satan.git"   # room kind only
transfer_timeout_s = 600       # room kind: bound on this repo's push/collect; sized for a first full push

[door]
kind = "room"                  # "slot" | "room"
room = "assistant"             # room kind: capsule argv; also the placeholder ssh host
user = "agent"                 # the room's repos.user
ssh_config = "…"               # ProxyCommand socat … ssh.sock; ServerAliveCountMax
identity = "…"                 # the runner's private key
known_hosts = "/var/lib/capsule/room/assistant/known_hosts"   # oubliette's; read only
host_key_alias = "room-assistant"
session_path = "/run/current-system/sw/bin/session"   # room kind; required, documented value
# slot kind instead: slot, quarantine (the slot's), profile, host (guest address); returnToWork applies
```

Values are illustrative; the shape is the contract. Keys are closed per kind,
in `[door]` and in `[repo.*]` alike: a key of the other kind (e.g.
`[repo.*].quarantine` or `room` under `kind = "slot"`, `host` or `[door]
quarantine` under `kind = "room"`), or a missing key the kind needs, refuses
start. Values
are never derived (I13): the alias is configured, not built from `room`
(today's slot adapter derives `pi-env-<slot>`; it moves to config too), and
each room repo names its own quarantine. `session_path` is required: the value
shown is the documented one, not a built-in fallback. `transfer_timeout_s`
(per repo) bounds that repo's `push` and `collect` and must cover a first full
push into a fresh `git init` clone; it also bounds the probe (a collect). On
expiry the verb's process group is killed, it is treated as exit 75, and the
audit records `channel_timeout` (§5.2). `guest_path` must equal the target's
`guestPath`; the runner holds a copy because `~/flakes` renders this file from
the same oubliette target attrset as the room (one source, at Nix eval), and
the `preparing` check (§5.2) backstops it. The check runs before the first
command in that repo, not at startup: a room down at startup is routine
(oubliette DEC-031).

### Leaving Postgres

At cutover a new elisp migration drops `patch_jobs` and `patch_job_events` from
`satan_memory`; the 17 failed historical rows are discarded. Go migration 0006
is retired with `satan-patcher`. Nothing else references these tables (the
observer and audit name `patch_job` only as an intervention kind).

### Authority ledger (DEC-062), applied at audit

| Item | Owner | Note |
|---|---|---|
| Patch-job lifecycle / queue consumer (new) | `patch-runner` | SPEC-001 REQ-001 (RPC schema validation on the runner's socket) and ADR-018 D3 (lifecycle, no REQ covers it; QUE-001) |
| Per-job path allowlist (new) | `patch-runner` | REQ-002; authoritative at collection |
| Row 4 audit → run actions | `emacs-client` | unchanged |
| Row 4 audit → patch-job actions | `patch-runner` | `job_events` + transcript |
| Row 5 ceiling → run budget | `emacs-client` | unchanged |
| Row 5 ceiling → per-job ceiling | `patch-runner` | |
| Row 6 kill switch → per switch | each owner | the runner's `enabled` owned by `patch-runner`; `satan-patch-runner-enabled` deleted |
| Legend token | `satan-patcher` → `patch-runner` | the malebolge runner binary |

Each row gets its transition line in the same change (INV-3). Promotion is an
approval surface (ADR-017 §1), not a ledger row. Credential custody stays out
(DEC-049).

<!-- doctrine:section sec-3 -->
## 5.4 Lifecycle, Operations & Dynamics

### Job state machine (DEC-059, DEC-055, DEC-060)

```mermaid
stateDiagram-v2
  [*] --> queued: submit
  queued --> preparing: scheduled (one in flight)
  queued --> cancelled: cancel
  preparing --> running: base_oid, job branch, initial prompt admitted
  preparing --> failed: refresh failed / base gone / room_unavailable / host_key / guest_path_invalid / dirty_clone
  preparing --> cancelled: cancel
  running --> waiting_room: typed env failure (JobConnection → afterTool)
  waiting_room --> running: room reachable → resume message
  running --> collecting: completed / ceiling / cancel / error
  waiting_room --> pending_collection: max_room_wait / cancel
  waiting_room --> collecting: probe ChannelFailed (end_reason = error)
  collecting --> pending_collection: channel unavailable
  pending_collection --> collecting: channel reachable
  pending_collection --> failed: max_pending_collection (collection_abandoned) / probe ChannelFailed (error)
  collecting --> needs_review: complete / partial
  collecting --> failed: no_changes / path_violation / error
  collecting --> cancelled: end_reason = cancelled
  needs_review --> promoted: verified receipt
  needs_review --> rejected: rejected
  promoted --> [*]
  rejected --> [*]
  cancelled --> [*]
  failed --> [*]
```

Purpose: the full set of states and who moves a job between them.

- Once anything has run in the room (from `running` on), a job reaches a
  terminal state only through `collecting`: the job is terminal only on a known
  collection outcome. `queued` and `preparing` can end directly — nothing
  travelled.
- A cancelled job that had run is still collected (its commits sit in
  quarantine for inspection and audit) but ends `cancelled`, not `needs_review`:
  it is never promotable. *(Reading of DEC-059 + DEC-060; see §6.)*
- `preparing` never enters `waiting_room`. With the room unreachable it retries
  refresh and branch creation with backoff, bounded by `max_room_wait`, then
  ends `failed(room_unavailable)` — nothing ran, so nothing is collected.
  `waiting_room` is entered only from `running`, so the resume message always
  follows an admitted run.
- Dropped from 0005: `claimed`, `preparing_worktree`, `accepted_external`,
  `stale`.

### Submit to review

```mermaid
sequenceDiagram
  participant E as Emacs tool
  participant R as Runner
  participant G as Git channel
  participant H as Harness (pi-durable)
  participant Rm as Room (pi-env)
  participant GW as Gateway
  E->>R: submit
  R->>R: validate schema, repo, base_ref, ceilings
  R->>R: tx: insert job(queued, conversation_id null) + event
  R->>H: createConversation
  R->>R: tx: record conversation_id
  R-->>E: jobId
  R->>R: scheduler wakes (FIFO, one in flight)
  R->>R: resolve policy → job.policy (preparing)
  R->>G: refresh(repo, base_ref)
  G-->>R: base_oid
  R->>Rm: (room) test -d guest_path/.git; clean-tree check, never clean (via env exec)
  R->>Rm: git switch -c job/<id> base_oid (via env exec)
  R->>H: configure(model, tools, cwd, instructions) + submit prompt (requestId = job id)
  H-->>R: admitted
  R->>R: tx: state = running
  loop turns
    H->>GW: model request (capped)
    H->>Rm: tool call (guard hooks around it)
  end
  H-->>R: run settled (completed)
  R->>G: collect(repo, job)
  G-->>R: quarantine ref + oid
  R->>Rm: (room) git reset --hard; git clean -ffd (via env exec)
  R->>R: ancestry + allowlist over all commits → class, reviewed_oid
  R-->>E: watch: needs_review
```

### Ceilings (DEC-057)

Per job: model requests, cost (USD), tokens, and *active* wall-clock (time in
`running`; `waiting_room` does not count).

**The model gate.** Hooks cannot deny a request: `beforeRequest` returns only
messages, and a throwing hook is reported and skipped. Denial therefore sits at
the provider boundary. The runner gives the harness a `Models` view whose job
models wrap both provider entry points pi-durable uses (`src/runner/model-gate.ts`):
`streamSimple` (generation and its retries) and `completeSimple` (compaction
summaries). Every provider call the job makes passes the gate; the view
delegates neither entry point unwrapped. Deferred polling (`fetchDeferred`) and
a tool's calls through `runtime.models` (`complete`, `stream`, `classify`,
`generateImages`, `streamDeferred`) are gated by the same rule. Two exceptions
(user rulings, 2026-10-19): `cancelDeferred` always passes, budget exhausted or
not, and is never counted — refusing it would leave an admitted deferred
request running and billing at the provider; `getAuth`, `login` and `logout`
are always refused, so a tool reaching `runtime.models` gets no credentials.
Before building that refusal the implementer confirms pi-durable itself never
calls them through the job's view; if it does, that is an escalation, not a
workaround.
Before each send the gate, purely from (attempt count, `pi.usage`, ceilings):

1. refuses if any ceiling is exhausted or usage cannot be read — the stream
   fails without a provider call, and the runner aborts the job with
   `end_reason = ceiling_exceeded` (or `usage_unavailable`), proceeding to
   collection;
2. otherwise increments the job's durable attempt counter (`model_requests`),
   so failed attempts count and the count survives restart;
3. sets the request's `maxTokens` to the lesser of the model's limit and what
   the remaining token and cost budget allows.

`pi.usage` (per model and per tool; includes input, failed, aborted and
compaction spend) is the token and cost measure; it has no request count, hence
the gate's counter. **Guarantee:** spend exceeds a ceiling by at most one
request, whose output is capped by the gate and whose input cost is that of its
prompt. That the gate can sit in the request path at the pinned pi-durable is
demonstrated before ceilings are built on it (§6 OQ-1); if it cannot, DEC-057
is amended to the weaker guarantee.

**Deadline timer.** Independent of the gate: a timer armed for the remaining
active wall-clock aborts the conversation's current work (a long model call or
`bash` included) when it fires. Active time is `active_ms` (closed running
segments) plus now minus `running_since`; a crash interval is charged to the
job (fail closed), so a restart re-arms with what is truly left.

**One warning.** At the soft threshold (default 80%) or when the remaining
budget falls under one request's allowance, whichever comes first, the runner
submits one steer (`whenBusy: "steer"`, placed after the current tool round,
before the next model request): commit work in progress and write notes now.
Its `requestId` is `warn-<job id>`, so a resubmit is a no-op. The `job_events`
warning row records *admission* and carries the admitted `submissionId` in
its payload; *delivery* is the steer's placement in the transcript.
Transcript entries carry no `requestId` and compaction can drop a placed entry
from the active view, so placement is read from the submission record instead:
`Harness.submission(id)` then `Submission.status()`, neither of which enables
scheduling (`wait` would). The warning is placed when that record carries an
`entry` (`placed`, `done`, or `unanswered` with an entry); `queued`, or
`unanswered` with no entry (withdrawn), is not placed. A pause aborts the
conversation and so withdraws a queued, unplaced steer; resubmitting the same
`requestId` would only return the withdrawn submission. So when a job resumes
past the warning threshold with no placed warning on record — no receipt (a
crash between admission and receipt), or a receipt whose record has no
`entry` — the resume message carries the warning text. A warning placed
before that crash is then repeated once; a duplicate advisory is tolerated.
Placement of a steer mid-run is confirmed in the pause spike.

**Maxima.** Runner config holds hard maxima; a job may only lower them.

### Room down: pause and resume (DEC-055)

```mermaid
sequenceDiagram
  participant Env as JobConnection (pi-env)
  participant H as Harness
  participant Gd as Guard (afterTool)
  participant R as Runner
  participant G as Git channel
  Env->>R: catch typed pi-env failure (lost / spawn) → tx: pause_requested = 1 + event
  Env-->>H: rethrow
  H->>Gd: tool result (error)
  Gd->>R: read pause_requested (never the result text)
  Gd-->>H: replace result ("environment unavailable; paused")
  R->>H: conversation.abort()  (before another model request)
  R->>R: tx: state = waiting_room, pause_requested = 0, pause_count += 1, stop deadline timer
  loop backoff
    R->>G: reachable(job)?
  end
  G-->>R: true
  R->>H: submit(requestId = resume-<job>-<pause_count>): "The environment restarted. Your last call may not have completed. Check state and continue."
  R->>R: tx: state = running, re-arm timer
```

- Recognition is by **type**, never by text, and happens at the environment
  boundary: pi-durable catches tool and environment exceptions and hands
  `afterTool` an ordinary error result, so a typed pi-env failure would arrive
  there as text only. pi-env's `ExecutionEnv` itself erases the type for
  `exec` (EVD-009), so amended DEC-055 moved recognition from the pre-amendment
  "env wrapper" over `ExecutionEnv` to the per-job `JobConnection` (§5.2,
  `src/runner/env.ts`): it sees the typed
  failure before pi-env and pi-durable convert it, records `pause_requested =
  1` durably (with its event; idempotent — one stop raises more than one lost
  failure) and rethrows. The mark is durable before the hook runs, so a crash
  anywhere after it leaves a recorded pause for recovery. The PHASE-01 spike
  stopped a slot mid-call (`capsule f stop`, EVD-010); EVD-005 covered a killed
  daemon, not a VM stop.
- A room stop is the same mechanism as that slot stop: an orderly guest reboot
  via the stop key (`systemctl stop microvm@…` → capsule-halt), cutting
  in-flight work. EVD-010 therefore stands for rooms and DEC-055 needs no new
  evidence; the live room rung adds one test — a reconnect after a room stop
  (pause, `capsule <room> start`, resume through a fresh `session`-launched
  daemon).
- The same spike confirms that the `JobConnection`'s host write runs outside any
  pi transaction on the shared adapter: a host call on the adapter from inside
  a pi transaction never settles (pi-durable README, SQLite adapters). The
  `afterTool` hook only reads. There is no in-memory fallback.
- Each waiting episode's resume message has a restart-stable id,
  `resume-<job id>-<pause_count>`: `pause_count` is incremented in the same
  transaction that records `waiting_room`, so a crash after admitting the
  resume message resubmits the same id.
- `max_room_wait` bounds the wait; then `end_reason = room_unavailable` and the
  job moves to `pending_collection`, collected when the room returns. A cancel
  while waiting takes the same path with `end_reason = cancelled`.
- Room: the probe is the job's `collect` (§5.2). A probe that throws
  `ChannelFailed` (changed host key, refused auth, refusal) ends the wait:
  `end_reason = error`, then `collecting` — never parked on a healthy room.
- A planned-stop signal from oubliette is a later, door-touching option.

### Collection and classification (DEC-060)

1. `collect` fetches `job/<id>` into quarantine. `ChannelUnavailable` →
   `pending_collection`, retried when `reachable(job)` (room: that probe is
   this collect; the redo is idempotent); bounded by `max_pending_collection`,
   then `failed(collection_abandoned)`, audited. A probe `ChannelFailed` →
   `failed`, class `error`.
2. Record `reviewed_oid` = collected oid (immutable from here). Room: then
   clean the clone (`git reset --hard`, `git clean -ffd`; §5.2). Idempotent, so
   a restart in `collecting` redoes it; a failed clean is audited, does not
   change the job's outcome, and the next `preparing` refuses the dirty tree.
3. Check ancestry: `reviewed_oid` descends from `base_oid`.
4. Check every path changed across `base_oid..reviewed_oid` (all commits, not
   only the tip diff) against `allowed_paths`.
5. Classify (pure):

| Condition | Class | State |
|---|---|---|
| ancestry fails, or any path outside the allowlist | `path_violation` | `failed` — never promotable |
| no commits beyond `base_oid` | `no_changes` | `failed` |
| collection or check error | `error` | `failed` |
| `end_reason = error` (collection succeeded) | `error` | `failed` — commits stay in quarantine, not promotable |
| `end_reason = cancelled` | (class recorded) | `cancelled` |
| `end_reason = completed` | `complete` | `needs_review` |
| `end_reason ∈ {ceiling_exceeded, usage_unavailable, room_unavailable}` | `partial` | `needs_review`, flagged |

The commit check is the authoritative allowlist site. A `beforeTool` block on
`write`/`edit` outside the allowlist is early feedback to the model only.

### Promotion (DEC-061)

```mermaid
sequenceDiagram
  participant U as User
  participant E as Emacs
  participant Q as Quarantine
  participant Real as Real repo
  participant R as Runner
  R-->>E: watch: needs_review(job, reviewed_oid, quarantine)
  E->>E: append inbox entry (idempotent by job id)
  U->>E: satan-patch-promote on entry
  E->>Q: git fetch <quarantine> <quarantine_ref>:refs/satan/incoming/<id>  (async process)
  E->>Real: incoming == reviewed_oid, else drop incoming and refuse
  E->>Real: git update-ref refs/heads/satan/patch/<id> <reviewed_oid> ""  (fails if it exists)
  E->>Real: delete refs/satan/incoming/<id>
  E->>R: report-disposition(promoted, branch)
  R->>Real: rev-parse (read-only) == reviewed_oid
  R->>R: tx: state = promoted + event
```

Emacs fetches the quarantine *ref* into an isolated temporary ref and requires
it to equal `reviewed_oid`, rather than fetching by oid, which a repo may refuse
(`uploadpack.allowReachableSHA1InWant`); the plan verifies the exact form
against the quarantine. The branch is then created by compare-and-swap against
an absent ref, so Emacs never moves or deletes a branch it did not create. Merging the branch is the user's own git act. Rejection skips the fetch and
reports `rejected`. There is no land verb, ever (oubliette DEC-040): the
quarantine is the slot's `[door] quarantine` or the room repo's
`[repo.*].quarantine` (room:
`/var/lib/capsule/collect/<room>/<repo>.git`, ref
`refs/capsule/<room>/heads/job/<id>`), reported by `result`. Re-sending
`needs_review` on every watch connect means a missed notice is never lost.

### Restart recovery (DEC-054)

Every harness call that asks for progress — `submit`, `abort`, `compact`, a
wait — starts pi-durable's task scheduler, and `Harness.open` alone runs
nothing. Startup therefore has two phases.

**Phase A — host only.** After `Harness.open`, settle every job row from the
table below using the job tables, git reads, the reachability probe, and the
harness's read-only views (`inspect`, a conversation's view, a submission
record's `status()` by its stored id), which never
enable scheduling (pi-durable `Harness` type docs). No call that asks for
progress is made.

**Phase B — harness acts, only when `enabled`.** One job is in flight
globally, so at most one conversation has pending work. Phase B performs that
job's one harness act, if any (column 3), then calls `resume()`.

With `enabled = false` the runner runs phase A only and makes no call that asks
for progress: in-flight jobs stay parked where they were, and a recorded pause stays
recorded. `status`, `list` and `result` read the job tables only. **Rule for
every row:** phase A work that reaches the room — a channel verb (`push`,
`collect`, the probe) or an env command (checks, branch create, clean) — runs
only when `enabled` (I14). Disabled, such a row does nothing: the job stays in
its state and no wait bound is applied, so nothing times out while parked.
Parked time is not charged as wait: a disabled startup sets `parked_at = now`
on each non-terminal job whose `parked_at` is null (one transaction, with a
`parked` event; a later disabled restart leaves it as is). The first enabled
startup, in phase A before any bound is judged, shifts `state_entered_at`
(and, for a `running` job, `running_since`, so parked time is not charged to
active wall-clock) forward by `now − parked_at` and clears `parked_at`, in one transaction with
an `unparked` event. Both writes are host-only and atomic, so a crash either
side of them re-bases exactly once.
Rows marked *(enabled)* below are gated this way.

Each row is exercised by fault injection at its write boundary.

| State at restart | Phase A (host) | Phase B (harness, enabled only) |
|---|---|---|
| `queued`, `conversation_id` null | — | create the conversation, record it |
| `queued` | left for the scheduler | — |
| `preparing`, no `base_oid` | *(enabled)* redo refresh (room down → retry within `max_room_wait`), record `base_oid` | — |
| `preparing`, `base_oid` set, no initial submission record (read-only view) | *(enabled)* room: the `preparing` checks; ensure `job/<id>` exists at `base_oid` (create if absent; at another oid → `failed(error)`) | submit the initial prompt with `requestId` = job id; then `running` |
| `preparing`, `base_oid` set, initial submission record exists | — (no checks: the agent may already have worked in the clone; nothing is judged against its branch) | record `running`; `resume()` continues it |
| `running`, `pause_requested = 1` | — | abort; then `waiting_room` |
| `running`, conversation settled (read-only view), no transition recorded | apply the transition the settled outcome implies (→ `collecting`) | — |
| `running` | re-arm the deadline from `active_ms` + (now − `running_since`) | `resume()` continues it; an interrupted unsafe tool reaches the model as `interrupted` |
| `running`, warning threshold passed, no warning receipt | — | resubmit the warning (`warn-<job id>`; returns the existing submission if admitted), then write the receipt with its `submissionId` |
| `waiting_room`, warning threshold passed and no placed warning on record (no receipt, or its submission record has no `entry`) | — | the resume message carries the warning text |
| `waiting_room` | *(enabled)* resume probing; bound from `state_entered_at`; probe `ChannelFailed` → `end_reason = error`, `collecting` | on reachable: submit the resume message (`requestId` = `resume-<job id>-<pause_count>`) |
| `collecting` | *(enabled)* redo collect (idempotent fetch), classification (pure) and, room, the clean (idempotent) | — |
| `pending_collection` | *(enabled)* resume retrying; bound from `state_entered_at`; probe `ChannelFailed` → `failed`, class `error` | — |
| `needs_review`, terminal | — | — |

Replay concerns runner crashes only. `read` reruns after a crash; `write`,
`edit` and `bash` do not — the model sees `interrupted` and decides.

### Scheduling (DEC-056)

One job in flight across all repos, FIFO by `created_at`. `submit` wakes the
scheduler; there is no tick and no `pg_notify`. A job holds the one seat in
every non-terminal state from `preparing` on, `waiting_room`, `collecting` and
`pending_collection` included (one room). Clean-after-collect relies on this:
no other job can be live in the clone being cleaned. The runner's `enabled = false` (or unit stopped) is the
kill switch: the runner refuses `submit` with `runner_disabled`, schedules
nothing, and makes no harness call that asks for progress (above); status and result stay readable.

### Cutover (DEC-063)

Deployment steps, each verified against the deployed service state, not only
green checks:

```mermaid
flowchart TB
  f["1 fence: satan-patch-runner-enabled nil in editor config;<br/>satan-patcher unit disabled in ~/flakes;<br/>patch_job_create refuses (satan change);<br/>confirm neither consumer runs, no non-terminal rows"] --> d["2 deploy runner from malebolge;<br/>enable while no producer submits"]
  d --> c["3 satan client cutover: delete elisp runner modules;<br/>tools → RPC; inbox → watch; promote/reject;<br/>migration drops patch_jobs, patch_job_events"]
  c --> x["4 flakes: remove satan-patcher module + input;<br/>archive Go repo and migration 0006"]
```

Purpose: the one-consumer invariant holds at every step. Today two consumers
are enabled, so fencing comes before anything else. The fence covers the
producer too: from step 1 until the client cutover, `patch_job_create`
refuses with "patch runner migration in progress", so no row can be queued
without a consumer. The drop migration refuses to run while any non-terminal
`patch_jobs` row exists, so a row from a transition window is never dropped
silently.

<!-- doctrine:section sec-4 -->
## 5.5 Invariants, Assumptions & Edge Cases

### Invariants

- **I1 One consumer.** At every deployment step at most one patch-job consumer
  is enabled; after cutover it is the runner.
- **I2 One schema owner.** Only the runner creates, migrates or writes the job
  tables; no other process opens `runner.sqlite`.
- **I3 No real-repo writes from the runner.** The runner's only real-repo
  operations are reads (`rev-parse`, `show-ref`, `check-ref-format`, ref
  existence). No socket operation causes a real-repo write.
- **I4 Socket never jailed.** `$XDG_RUNTIME_DIR/satan-runner/` is absent from
  every jail profile, asserted by the profiles' tests (REQ-016).
- **I5 Every operation validated.** No socket operation acts before its full
  schema parse succeeds.
- **I6 Authoritative allowlist at collection.** Nothing reaches `needs_review`
  unless every path changed in `base_oid..reviewed_oid` is allowed and
  `reviewed_oid` descends from `base_oid`.
- **I7 `reviewed_oid` is immutable** once recorded; promotion lands exactly it.
- **I8 Promoted means verified.** `promoted` is recorded only after the runner
  reads `satan/patch/<id>` in the real repo and finds `reviewed_oid`.
- **I9 Ceilings hold without Emacs.** Ceiling checks, the deadline timer and
  the kill switch run in the runner and depend on no client.
- **I10 Unreadable usage denies.**
- **I11 Audit is append-only** and written in the same transaction as the state
  change it records.
- **I12 Terminal only on a known collection outcome** for any job that reached
  `running`.
- **I13 No fallback paths.** Missing prompt file or config refuses start. Door
  and repo values (quarantine, `known_hosts`, host-key alias, `guest_path`)
  are configured, never derived.
- **I14 Disabled means parked.** With `enabled = false` the runner never calls
  `harness.resume()`, submit or wait; no job advances.
- **I15 Host state before harness acts.** Startup settles every job's host
  state (phase A) before any harness call that asks for progress (read-only
  views are allowed); only the one in-flight job gets a
  harness act, then `resume()`.
- **I16 Running means admitted.** A job is `running` only after its initial
  prompt is admitted.
- **I17 Gate on every provider call.** Every provider call a job makes passes
  the model gate, which counts it before sending — except `cancelDeferred`,
  which always passes uncounted.

### Assumptions

- **ASM-005** (validated from oubliette SL-005's relay) — the door is as Plan
  F §5 sketched: agent user, runner key in the room declaration, unix-socket
  relay. Open caveat: the agent home is writable and executable (pi-env deploys
  its daemon there); checked at the live room rung.
- **The room interface is oubliette SL-006 design sec-6** — provisional until
  SL-006 locks; the room adapter is built against fixtures of it, and the slot
  remains the live rung until SL-006 ships.
- pi-env raises a *typed* failure on a room stop, catchable in the runner's
  `JobConnection`, whose host write runs outside a pi transaction; a steer is placed
  before the next model request; a `Models` view wrapping `streamSimple` and
  `completeSimple` gates every provider call (all proven by the first-phase spike; DEC-055,
  DEC-057).
- pi-durable 1.3.0's API (hooks, prefixed SQLite storage sharing one adapter,
  `pi.usage`, `abort`, `wrapTool`) holds at the pinned version.

### Edge cases

| Case | Behaviour |
|---|---|
| Duplicate `submit` (same `submissionId`) | returns the existing job; no second row |
| Crash between creating and recording the conversation | recovery creates another; the unrecorded one is never submitted to |
| Cancel while `preparing` | `cancelled`; nothing ran |
| Room down during `preparing` | retry with backoff; after `max_room_wait`, `failed(room_unavailable)` |
| Crash after `base_oid`, before the initial prompt is admitted | phase B resubmits with `requestId` = job id, then records `running` |
| Provider error ends the run after valid commits | collected; class `error`, `failed`; commits kept in quarantine, not promotable |
| Another process creates `satan/patch/<id>` mid-promotion | the compare-and-swap fails; Emacs refuses and touches nothing it did not create |
| Producer called during cutover | refused from the fence until the client cutover |
| Emacs absent when a job fails | notice resent on next watch connect until acked |
| `baseRef` deleted between submit and refresh | `preparing → failed(base_ref_invalid)` |
| `job/<id>` already exists in the guest at another oid | `failed(error)`; never force-moved |
| Room clone still dirty at `preparing` (the clean after the previous collect failed or never ran) | `failed(error)`, `dirty_clone`, paths audited; `preparing` discards nothing |
| Daemon start finds the host key unknown (runner's `known_hosts` or `host_key_alias` config drifted from oubliette's, or a `forget-host-key` raced; a successful `push` has already learned it) or changed (room rebuilt mid-job) | typed `HostKey*Error` in the command function → per-job trust failure; `preparing` → `failed(error)`, `host_key`; `running` → abort, `end_reason = error`, collect — never `waiting_room`, never retried |
| Restart after the initial prompt was admitted, before `running` was recorded | redo skips the `preparing` checks, records `running`; the agent's own uncommitted work is not judged `dirty_clone` |
| Room stops between collect and clean | the clean's lost failure is counted, not a pause; the job keeps its outcome; next `preparing` refuses the residue or the restart redo cleans |
| `base_ref` deleted after the runner's check, before push resolves it | push exits 2; the re-check finds no branch → `failed(base_ref_invalid)`, not a runner-bug refusal |
| Verb killed on its timeout | the whole process group dies before the retry; no orphan holds a ref lock |
| Configured `guest_path` has no `.git` in the room | `failed(error)`, `guest_path_invalid`; config drifted from the target's `guestPath` |
| Room channel verb exits 1 on auth or a changed host key | `ChannelFailed` → `failed(error)` (preparing) or class `error` (collecting); never treated as room down |
| Host key changes or auth is refused while `waiting_room` | the probe (the job's collect) exits 1 → `ChannelFailed`; `end_reason = error`, `collecting` — not parked until `max_room_wait` |
| Room `collect` stdout oid or ref differs from the quarantine ref | `ChannelFailed` |
| Room channel verb exits 2 | `ChannelFailed`, audited as a refusal (runner bug) |
| Guest freezes with tap and relay up | daemon connection: pi-env's 30 s silence limit drops it (ssh keepalive is a later backstop) → typed lost → pause; channel verbs: their timeout → `ChannelUnavailable`, retried within `max_room_wait` |
| Room channel verb exceeds its timeout (incl. an ssh prompt waiting for input) | group killed; `ChannelUnavailable`, as exit 75; audited `channel_timeout` |
| First push into a fresh clone sends the full history | bounded by the repo's `transfer_timeout_s`, sized for it |
| `dirty_clone` wedges a repo (abandoned collection, failed clean) | every later job on it fails until the operator cleans via `capsule <room> ssh`; no automatic clean outside post-collect |
| Agent commits on another branch | not collected; may yield `no_changes` |
| Agent leaves uncommitted work | not collected (the warning tells it to commit) |
| Agent rewrites history below `base_oid` | ancestry fails → `path_violation`, not promotable |
| `bash` writes outside the allowlist and commits it | `path_violation` at collection |
| Room stops during collection | `pending_collection`, retried |
| Cancel while `waiting_room` | `pending_collection`, collected when the room returns, then `cancelled` |
| Emacs absent when a job finishes | job waits in `needs_review`; sent on next watch connect |
| `satan/patch/<id>` already exists in real repo | Emacs refuses promotion; nothing written |
| User moves `satan/patch/<id>` before reporting | runner refuses `receipt_mismatch` |
| Runner disabled with jobs queued | they stay queued; nothing schedules |
| Budget exhausted with a deferred request admitted at the provider | `cancelDeferred` passes the gate uncounted; `fetchDeferred` is refused like any send |
| A tool calls `getAuth`/`login`/`logout` through `runtime.models` | refused by the gated view; no credential leaves it |
| Gateway refuses (budget) | a failed attempt, counted by the gate; the run's error path ends it → collection with `end_reason = error` |

<!-- doctrine:section sec-5 -->
# 6. Open Questions & Unknowns

Resolved by this amendment (was deferred on ASM-005, inq-14): door
configuration and the room git-channel adapter, against oubliette SL-006 sec-6
(§5.2, §5.3); the land verb does not exist (oubliette DEC-040). Also resolved
by the user's rulings:

- **OQ-2 Dirty room clone** — the runner cleans its own clone after a
  successful collect (`git reset --hard`, `git clean -ffd`; ignored caches
  kept); `preparing` only checks and fails closed `dirty_clone`; a wedged repo
  is cleaned by hand via `capsule <room> ssh` (§5.2, §5.4). A `clean-clone
  <repo>` control-socket operation (from Emacs) is deferred to the backlog.
- **OQ-3 Channel verb timeout** — per-repo `transfer_timeout_s` for
  `push`/`collect` and the probe (a collect; no separate probe timeout,
  ruling 2026-10-19); expiry is
  `ChannelUnavailable`, as exit 75, audited separately as `channel_timeout`,
  retried within `max_room_wait` (§5.2, §5.3).
- **Room reachability** (oubliette RV-018; user ruling 2026-10-19) —
  `capsule <room> ssh <user> true` is the human's door, not a channel verb;
  `reachable` is job-scoped and runs the job's collect (§5.2). Oubliette pinned
  stdout: push `<oid>`, collect `<oid>\t<ref>`; progress and errors on stderr.
- **Verb identity** (RV-026 F-4) — the verbs use the module owner's default
  key; the room user lists it and satan's key (§5.2 Identities).

Remaining:

- **SL-006 lock drift.** The room adapter tracks SL-006 sec-6 until it locks;
  a change there re-opens §5.2's room rows, not the port; verb stdout and
  exit codes are already pinned (oubliette RV-018). Oubliette is fixing
  two sec-6 wordings this design already follows (the `guest_path` check is in
  `preparing`; clone hygiene is the runner's). A third is not yet relayed: sec-5
  says every door to a room, "satan's runner" named, uses `accept-new`; this
  design keeps the runner strict (user ruling) and lets only oubliette's verbs
  learn keys. To relay to oubliette so sec-5 is amended before SL-006 locks.
  Nice-to-have for oubliette, not a dependency: an identity option and
  `BatchMode` for the room verbs.
- **Deployment facts** for `~/flakes/SATAN.md`: satan's dedicated keypair and
  the module owner's default key, both public halves in the room user's `{
  uid; keys; }` (CON-004), the runner
  unit as the oubliette module owner (CON-003), runner config rendered from the
  oubliette target attrset.

Open, gated by the first-phase spike:

- **OQ-1 The model gate.** Ceiling denial, the attempt counter and the
  per-request output cap all sit in a `Models` view wrapping the provider
  stream (§5.4), because no pi-durable hook can deny a request or set its
  options (`beforeRequest` returns only messages; a throwing hook is skipped).
  That the view sits in the path of every provider call — generation, retry,
  compaction — at the pinned version is demonstrated in the first-phase spike.
  If it cannot, DEC-057 is amended to the weaker guarantee: strict up to one
  *uncapped* request, enforced by aborting at the first turn boundary after
  exhaustion, with the deadline timer unchanged.
- **Spike confirmations** (same phase): pi-env's typed failure on a real room
  stop, caught by the `JobConnection`; its host write running outside a
  pi transaction; a steer placed before the next model request; compaction
  (`completeSimple`) passing the gate; `Harness.submission(id).status()` on a
  paused harness leaving scheduling paused.

Not a design question here:

- **Runner gateway credential.** The runner is a new gateway client; how its
  key reaches it is `~/flakes` SL-011's (DEC-049: not a ledger item). A
  deployment dependency only.

<!-- doctrine:section sec-6 -->
# 7. Decisions, Rationale & Alternatives

The decisions are the normative records; read each with `doctrine show DEC-0NN`.
This table is an index.

| Record | Choice | Main alternative rejected, and why |
|---|---|---|
| DEC-050 | Option D: host daemon runs a pi-durable harness; tools in the room via pi-env. Emacs keeps producer, inbox, approval. | A (elisp runner, pi in room) fails ADR-018 D5 and loses the run on every room stop; B (daemon, pi in room) also loses the run. |
| DEC-051 | One TypeScript process, second binary in `~/dev/malebolge`. | Rust core over RPC driving a TS harness would split one authority across two processes or call back per tool call. |
| DEC-052 | Job state and pi-durable share one runner-local SQLite file and adapter; ordered creation (job row, then conversation) with a recovery row; `patch_jobs` leaves `satan_memory`. | Postgres with the runner as sole owner: two stores, no shared commit boundary. |
| DEC-053 | Strict tsc + Biome now; typescript-eslint `strictTypeChecked` via IMP-041 before runner code; vitest; 85% line coverage, ratcheted. | Biome alone lacks type-aware rules. |
| DEC-054 | One store, one conversation per job; only `read` replay-safe; written recovery table with fault injection. | Replay-safe `write` can clobber guest state after an unrecorded first write. |
| DEC-055 | Pause on a typed room failure caught at the env boundary, resume with one message; bounded wait; spike first. | Letting the model retry burns turns while the room is down. |
| DEC-056 | One job in flight, FIFO, woken by submit; ladder and composition ported; prompt path explicit. | Per-repo concurrency; periodic tick. |
| DEC-057 | Per-job ceilings on requests, cost, tokens, active wall-clock; a model gate at the provider boundary (deny, count, cap) + deadline timer; one idempotent warning submission; own append-only audit. | Gateway budgets only; audit relayed through Emacs (fails client-absent). |
| DEC-058 | Same-uid UDS never bound into a jail; NDJSON; full schema validation; watch resends review and unacked failure notices; no promotion op. | Token file adds nothing a reachable socket lacks. |
| DEC-059 | `base_ref` is a real-repo branch validated by the runner; slimmed room-model states. | Producer resolves `base_ref` (dual enforcement). |
| DEC-060 | Git-channel port; collect every ended job; classify from quarantine; commit check authoritative. | Per-call allowlist only (`bash` bypasses it). |
| DEC-061 | Approval and enactment in Emacs by a plain fetch of the quarantine ref (no land verb); land `satan/patch/<id>`; runner verifies a receipt. | Runner enacts promotion on an RPC (socket would reach real repos). |
| DEC-0NN *(proposed)* | Room adapter and room door kind behind the existing ports, built now against SL-006 sec-6 fixtures; strict runner host keys (oubliette learns them); `session` by configured absolute path; per-repo transfer timeouts → unavailable; clean clone (`-ffd`) after collect only, check-only in preparing; slot stays the live rung until SL-006 ships. | Wait for SL-006 to ship before building (serialises two repos' work). |
| DEC-062 | Ledger: new lifecycle and allowlist rows; rows 4, 5, 6 split; token `patch-runner`. | Keep token `satan-patcher` (names a retired repo). |
| DEC-063 | Cutover: fence, deploy, client cutover with table drop, remove Go; one consumer throughout. | Keep a fallback runner (half-extraction). |
| DEC-064 | Runner tech spec under SPEC-002, written at reconcile. | Spec before implementation (ahead of evidence). |

Governance amended for this design: REV-006 (ADR-018 D1/D3 scope for workload
fit and process-private state; POL-001's IMP-006 destination).

<!-- doctrine:section sec-7 -->
# 8. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| pi-durable / pi-env are experimental and change without notice. | Exact version pins in one place (malebolge's `package.json`), shared by both binaries; upgrades are deliberate and gated by the harness tests and the env conformance suite. |
| Room adapter built against an unlocked design (SL-006 sec-6). | One port, two adapters; door values are config; nothing outside `room.ts`, `env.ts`'s connection factory and config knows the door. Fixture tests pin argv and exit-code mapping, so a sec-6 change shows as a red test. Re-check against SL-006 at its lock, before the live room rung. |
| Runner config drifts from the room (`guest_path`, repo name, quarantine). | Rendered by `~/flakes` from the same oubliette target attrset; the `preparing` `guest_path` check and the push oid gate the first command. |
| A trust failure reads as downtime and parks a job on a healthy room. | The room probe is the job's collect, under the channel's exit contract (1 → `ChannelFailed`, fails the job); never `ssh <user> true` (255, interactive). |
| A frozen guest makes each room probe wait out `transfer_timeout_s`. | A stopped room exits 75 at once; probing backs off and stays bounded by `max_room_wait` / `max_pending_collection`. |
| A frozen guest hangs ssh. | Daemon connection: pi-env's 30 s silence limit turns it into a typed lost failure → pause (ssh keepalive, of which only `ServerAliveCountMax` is ours, is a backstop). Channel verbs: per-repo transfer timeouts, killing the process group → `ChannelUnavailable`. |
| Cleaning the clone destroys uncollected work. | Only after a successful collect; `preparing` never cleans. |
| A real room stop surfaces differently from a killed daemon, or pi-durable erases the error type. | The pause spike is the plan's first phase; recognition is by type at the `JobConnection`, before pi-durable converts it; never by text. |
| The model gate cannot sit in every provider call's path (OQ-1). | Demonstrated in the first spike; on failure amend DEC-057 to the weaker guarantee; the deadline timer remains regardless. |
| The `JobConnection`'s host write runs inside a pi transaction and deadlocks. | Confirmed by the pause spike before pause is built on it; the hook only reads. |
| Half-extraction during cutover (two consumers enabled today, ISS-039). | Fence consumers and producer first; verify deployed state at each step; the drop migration refuses non-terminal rows (DEC-063). |
| Restart between a pi commit and a host write leaves them disagreeing. | Recovery table rows for each gap, each exercised by fault injection. |
| The runner socket becomes reachable from a jail (RSK-018, ISS-028). | Own runtime directory; jail-profile tests assert its absence (REQ-016). |
| The agent escapes the allowlist via `bash`. | Authoritative check on the collected commit set; violations never promotable. |
| Malicious content in collected git objects. | Quarantine fetch with `transfer.fsckObjects` (oubliette's channel); Emacs fetches one quarantine ref and lands it only if it equals `reviewed_oid`. |
| Losing job history on table drop. | Accepted: 17 rows, all failed (DEC-063). |

<!-- doctrine:section sec-8 -->
# 9. Quality Engineering & Validation

### Gates (DEC-053)

`just check` in malebolge (lint + typecheck + test), zero warnings, covering
both binaries. tsc `strict` plus `noUncheckedIndexedAccess`,
`exactOptionalPropertyTypes`, `noImplicitOverride`,
`noPropertyAccessFromIndexSignature`, `noFallthroughCasesInSwitch`. Lint:
typescript-eslint `strictTypeChecked` once IMP-041 lands, which precedes runner
code; until then Biome recommended at error plus its nursery promise and
exhaustiveness rules. vitest; V8 line coverage threshold 85%, ratcheted, entry
points excluded. 2-space format. malebolge's existing code is raised to the
same bar. In this repo, `just check` (ert) covers the elisp client.

### Test layers

| Layer | Subject | Substrate |
|---|---|---|
| Pure units | `policy`, `prompt`, `ceilings`, `classify`, `jobs` (transitions + recovery table), `protocol` | plain vitest |
| Store | migrations, idempotent submit, append-only `job_events`, state + event atomicity | in-memory SQLite |
| Harness | guard hooks, pause/resume, ceilings, deadline, warning, restart recovery | pi-durable faux provider + memory storage; fault injection at each write boundary |
| Tool seam | the runner's use of an `ExecutionEnv` | a local env held to `registerEnvConformance` |
| Git channel | collect, ancestry, allowlist over commit sets | temp bare repos as room and quarantine |
| Socket | every op, schema refusal, watch replay | real UDS in a temp dir |
| Acceptance fixtures | behaviour ported from the deleted ert tests and the Go policy/classify/reconcile tests (POL-001) | per the layer they exercise |
| Elisp client | RPC tools, watch-driven inbox, promote/reject | ert against a fake socket server |
| Room adapter | argv for `push`/`collect`; the job-scoped probe; exit 75/1/2 and timeout mapping; stdout oid and ref parsing, cross-checked against the quarantine; the `session` daemon command; clean-after-collect; trust-failure record from typed host-key errors; config per door kind | stubbed `capsule` (`SlotCli` seam, incl. one that never exits), a stubbed command function, local env; pure where possible |
| Live smoke | one job end to end against a slot through the gateway | env-gated; not in `just check` |
| Live room rung | one job end to end against a room; reconnect after a room stop; silence-limit drop on a frozen guest; a changed host key on reconnect fails as `host_key`, not a pause; agent home writable; push and collect run non-interactively as the runner user (module owner's default key) | deferred until oubliette SL-006 ships; env-gated |

### Key test cases

- *submit with `baseRef: "HEAD"` is refused `base_ref_invalid`* (ISS-041).
- *submit omitting `baseRef` uses the repo's default branch.*
- *a second submit with the same `submissionId` returns the first job.*
- *a ceiling above the configured maximum is refused.*
- *an unknown key in any operation is refused before any effect.*
- *a commit touching a path outside the allowlist yields `path_violation` even
  when the tip diff is clean* (all commits checked).
- *a history rewrite below `base_oid` fails ancestry.*
- *`write` outside the allowlist is blocked early; the same change via `bash`
  is caught at collection.*
- *a typed env failure, caught by the `JobConnection`, pauses the job before another
  model request; a tool error with the same text does not.*
- *waiting time does not count toward the wall-clock ceiling.*
- *the deadline aborts an in-flight long `bash`.*
- *unreadable usage denies the next request.*
- *with the budget exhausted, the next generation request, a retry and a
  compaction summary each reach no provider* (model gate; faux provider).
- *with the budget exhausted, `cancelDeferred` reaches the provider and leaves
  `model_requests` unchanged; `fetchDeferred` and a tool's `runtime.models`
  `complete` are refused.*
- *the gated `Models` view refuses `getAuth`, `login` and `logout`, and a
  pi-durable job run never calls them through it.*
- *the attempt counter counts failed attempts and survives restart.*
- *a restart during a long call charges the crash interval to active
  wall-clock; a restart during `waiting_room` or `pending_collection` does not
  reset its bound.*
- *a crash between warning admission and its receipt resubmits without a
  second warning reaching the model.*
- *room down during `preparing` retries, then fails `room_unavailable` without
  a conversation turn.*
- *a crash after `base_oid` and before admission resubmits the initial prompt
  once; the job does not hold the slot forever.*
- *a disabled runner restarting with a recorded pause makes no call that asks
  for progress.*
- *a compaction summary with the budget exhausted reaches no provider.*
- *a crash after the resume message is admitted resubmits the same id; one
  resume message reaches the transcript.*
- *a crash after the `JobConnection` records the pause, before the hook runs,
  recovers to `waiting_room`.*
- *a pause withdrawing an unplaced warning: the resume message carries it.*
- *a placed warning compacted out of the active view still reads as placed
  (its submission record carries an `entry`); no resume message repeats it.*
- *a crash after warning admission and a recorded pause, before the receipt,
  resumes with the warning text in the resume message.*
- *an intervention create failure returns ok with `job_id` and
  `intervention_error`.*
- *a run ending in a provider error after valid commits is `failed` with class
  `error`.*
- *promotion refuses, touching nothing, when `satan/patch/<id>` appears
  between fetch and branch creation.*
- *`patch_job_create` returns `intervention_id` and creates a `patch_job`
  intervention for the runner's job id.*
- *the drop migration refuses while a non-terminal row exists.*
- *the warning is delivered once, at the threshold or under one request's
  allowance, whichever is first.*
- *a ceiling hit collects partial work and offers it flagged.*
- *restart in each recovery-table state reaches the expected next state, with
  no task scheduled before the table completes; the resume message is not sent
  twice.*
- *restart with a job whose `conversation_id` is null creates and records one;
  the first submission uses `requestId` = job id.*
- *with `enabled = false` and a job `running`, restart never starts the
  conversation; status reads it as `running`.*
- *with `enabled = false`, restart with jobs in `preparing`, `waiting_room`,
  `collecting` and `pending_collection` runs no channel verb or env command and
  times none out* (stubbed channel and env record no call).
- *a job in `pending_collection` parked for longer than
  `max_pending_collection`, then re-enabled, keeps only its pre-park elapsed
  wait and retries collect; a crash after the `unparked` transaction does not
  re-base it twice.*
- *a `running` job parked while disabled is re-armed on re-enable with only
  its pre-park active time charged (`running_since` shifted).*
- *watch connect resends unacked `failed`/`cancelled` jobs; after `ack` they
  are not resent.*
- *cancel while `preparing` ends `cancelled` without collection.*
- *promotion fetches the quarantine ref and refuses when it differs from
  `reviewed_oid`.*
- *`report-disposition promoted` with a mismatched branch oid is refused.*
- *watch connect re-sends every `needs_review` job; the inbox appends once.*
- *the runner refuses to start with a missing prompt file.*
- *with `enabled = false`, submit is refused and nothing schedules.*
- *Emacs tools fail with an error when the socket is absent.*
- *jail profiles do not bind `$XDG_RUNTIME_DIR/satan-runner`* (in `~/flakes`).
- *room adapter: exit 75 from `push` or `collect` is `ChannelUnavailable` with
  no probe; 1 (incl. auth / host key) is `ChannelFailed`; 2 is a refusal.*
- *room `refresh` returns push's stdout oid; `collect` refuses a ref other than
  `refs/capsule/<room>/heads/job/<id>`.*
- *room `collect` whose stdout `<oid>\t<ref>` differs from the quarantine ref
  (oid or ref) is `ChannelFailed`.*
- *room `reachable(job)` runs `capsule <room> collect <repo> job/<id>`: 0 →
  true; 75 or `transfer_timeout_s` → false; 1 throws `ChannelFailed`; 2 a refusal.*
- *a changed host key during `waiting_room` (probe exits 1) ends the wait with
  `end_reason = error` and collects; the job is not left parked.*
- *the room daemon command is `ssh <sshArguments> session <repo> -- <daemon>`
  with the job's repo; a lost failure through it still pauses (JobConnection
  outer).*
- *`preparing` in a room: missing `<guest_path>/.git` fails
  `guest_path_invalid`; a dirty tree fails `dirty_clone` and is left as found;
  a clean fresh clone takes `git switch -c job/<id> <oid>`.*
- *after a successful room collect the clone is reset and cleaned, ignored
  files kept; a failed collect leaves the tree untouched.*
- *a room `push`/`collect` (the probe included) past the repo's
  `transfer_timeout_s` is killed and maps to `ChannelUnavailable`, audited
  `channel_timeout` (not as exit 75); in `preparing` it retries within
  `max_room_wait`.*
- *the post-collect clean removes an untracked nested repo (`-ffd`) and keeps
  ignored files.*
- *the room daemon command uses `sshArguments(target, true)`, `session_path`
  verbatim and the room name as ssh host.*
- *a command function throwing `HostKeyChangedError`/`HostKeyUnknownError`
  records a trust failure: `preparing` fails `host_key`; a running job aborts to
  `collecting` and never enters `waiting_room`; a plain lost failure still
  pauses.*
- *restart in `preparing` with the initial submission admitted and the agent's
  files in the clone: no `dirty_clone`; the job records `running`* (fault
  injection at that boundary).
- *a crash between collect and clean: restart redoes the clean; a room stop in
  the clean writes no `pause_requested` and no pause event.*
- *with job A in `pending_collection`, job B is not scheduled.*
- *push exit 2 with `base_ref` gone fails `base_ref_invalid`; with it present,
  a refusal.*
- *a timed-out verb whose stub spawns a grandchild that keeps running: the
  grandchild is dead before the retry starts.*
- *config: a room door key under `kind = "slot"` (or the reverse, e.g. `host`
  under `kind = "room"`), or a missing `host_key_alias`, `session_path` or
  `transfer_timeout_s`, refuses start; so do `[repo.*].quarantine` under
  `kind = "slot"` and `probe_timeout_s` under either kind.* (The door ssh config's `ServerAliveCountMax` is a
  `~/flakes` rendering, checked there.)

### Closure evidence

A job from `patch_job_create` runs end to end against the slot, lands in
quarantine, is classified, and is promoted and rejected from Emacs; exactly one
consumer is enabled (deployed state checked); the ledger shows every changed
owner with transition lines; ISS-030, ISS-038, ISS-039, ISS-041 and CHR-003
are closed by supersession; IDE-007 is resolved into this slice. The room
adapter's fixture tests are green; the live room rung is not closure evidence
for this slice while SL-006 is unshipped.

<!-- doctrine:section sec-9 -->
# 10. Code Impact & Governance Follow-through

### This repo (`~/dev/satan`)

| Path | Change |
|---|---|
| `satan/satan-patch-{runner,worktree,adapter,adapter-pi,prompt,classify,store,listener}.el` | deleted |
| `satan/test/satan-patch-{runner,worktree,adapter,classify,store,listener}-test.el` | deleted; behaviour ported to runner acceptance fixtures first |
| `satan/satan-tools-patch.el` | fence commit first (`patch_job_create` refuses during migration); then rewritten: `patch_job_create/_status/_result/_cancel` as bounded synchronous socket RPC clients; intervention creation retained; no `HEAD` default; `patch_job_cleanup` and `satan-patch-prepare` removed; fail closed when the runner is unreachable |
| `satan/satan-patch-inbox.el` | watch-driven: socket watch with reconnect; idempotent org append by job id; renders `reviewed_oid`, class and partial flag |
| `satan/satan-patch.el` | entry shrinks to tools + inbox + the new promote/reject commands (`satan-patch-promote`, `satan-patch-reject`), in a new `satan/satan-patch-promote.el` |
| `satan/test/satan-tools-patch-test.el`, `satan/test/satan-patch-inbox-test.el`, new `satan/test/satan-patch-promote-test.el` | ert against a fake socket server and temp git repos |
| `satan/memory/migrations/0009_drop_patch_jobs.sql` | new: refuses while any non-terminal row exists; drops `patch_job_events`, `patch_jobs`, their trigger function |
| `satan/test/satan-custom-test.el` | drop the deleted modules' defcustoms from its path-root inventories |
| `satan/satan-db.el` | comment no longer names `satan-patcher` |
| `.doctrine/adr/017/authority-ledger.md` | rows per DEC-062, with transition lines (at audit) |

### Other repos

| Repo / path | Change |
|---|---|
| `~/dev/malebolge` | IMP-041 lint move first; then the runner binary (`src/runner-main.ts`, `src/runner/*`, `test/runner/*`); `src/models.ts` gains the gateway-routed provider; `pi-env` pinned beside `pi-durable`; `package.json` `bin` gains the runner; `just check` covers both binaries. Amendment: `config.ts` `[door] kind` with closed per-kind keys, `host_key_alias`, `room`, `session_path` (`probe_timeout_s` removed), `[repo.*].quarantine` and `transfer_timeout_s`; `room.ts` room adapter beside the slot adapter, `roomConnection` reads the alias; `reachable(job)` on the port, room probe = the job's collect (`roomProbeArgs` removed), collect stdout cross-checked against the quarantine; `pause.ts`/`collect.ts` pass the job and end a job on a thrown `ChannelFailed`; `exec.ts` process-group spawn and group kill on timeout; `env.ts` room daemon `Connection` (strict `sshArguments`, `session_path` launch, room name as ssh host); `run.ts` `connect(repo)`; `prepare.ts` `guest_path` and clean-tree checks, skipped on a redo after admission; trust-failure record in the command function; `collect.ts` clean after collect |
| `~/flakes` | runner unit as the oubliette module owner (CON-003), with its `enabled` switch, config file, state and runtime dirs; runner config (repos, `guest_path`, quarantine, door) rendered from the oubliette target/room attrsets; door ssh config (`ProxyCommand`, `ServerAliveCountMax`); satan's dedicated public key and the module owner's default public key in the room user's `{ uid; keys; }` (CON-004); `satan-patcher` module and flake input removed; jail-profile tests assert `$XDG_RUNTIME_DIR/satan-runner` absent; runner keypair + gateway credential wiring; `SATAN.md` updated |
| `~/.config/emacs/apps/dl-satan.el` | `satan-patch-runner-enabled` set nil (fence), then removed |
| `~/dev/satan-patcher` | archived, with migration 0006 |
| `~/satan-corpus/tools/patch_job_{create,status,result,cancel}.md` | rewritten for the new contract: `repo` is a config name, not a path; `base_ref` a branch, default the repo's; no `checks`, `adapter`, `branch` or `worktree_path`; create returns `job_id`, `state` and `intervention_id` (or `intervention_error` when the intervention create failed; the job still exists); result carries class, `reviewed_oid` and a partial flag; review is promote/reject in Emacs, not cherry-pick. Committed with `just commit` in the corpus repo. |
| `~/satan-corpus/tools/patch_job_cleanup.md` | deleted with the tool |

### Governance follow-through

- Ledger rows (DEC-062) at audit.
- Runner tech spec under SPEC-002 at reconcile; SPEC-002's container list and
  SPEC-003 OQ-3 updated with it (DEC-064).
- Close ISS-030, ISS-038, ISS-039, ISS-041, CHR-003 by supersession; resolve
  IDE-007 into this slice.
- REV-006 already applied (ADR-018 amendment, POL-001 IMP-006 destination).
- Oubliette ISS-021 (no `/work` volume) is closed by oubliette SL-006, not here.
- Deferred to the backlog: a `clean-clone <repo>` control-socket operation,
  invoked from Emacs, for a wedged `dirty_clone` (today: manual remedy, §5.2).
- DEC-060 and DEC-061 choice text amended for the room adapter and no land
  verb; a new decision records the room adapter and door kind (§7).

