# SPEC-003: SATAN harness

<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

The harness is the untrusted half of every broker-spawned SATAN run: a jailed
Python process (`satan/harness/`) that talks to the host LLM gateway and to the
broker, and to nothing else. The broker (trusted, in Emacs) renders the prompt,
chooses the tools, starts the harness, executes every tool call and records the
outcome. The harness turns model output into protocol messages.

**C4 frame.** A container under the context spec SPEC-002, filling that spec's
Harness row. No product spec: the why lives in SPEC-002 and ADR-017. This spec
owns the harness's **envelope** — where its binary comes from, what the broker
hands it, how the two talk, and what its jail can reach — and gives the
harness's internals only enough context to read the code.

**Posture.** Mostly retrospective: provenance, the spawn contract and the run
loop describe shipped behaviour (after ISS-037, 2026-10-14). Forward intent,
not yet built: the protocol version check (REQ-023) and the declared,
test-asserted jail profile (REQ-025). All requirements are `pending`; observed
coverage is reconciled, not inferred here.

```text
       trusted                         untrusted (bwrap jail)
┌──────────────────────┐  spawn: cmd, env, cwd ┌──────────────────────┐
│ Broker (Emacs)       ├──────────────────────►│ Harness (Python)     │
│ renders bundle.json  │  run dir (ro inputs)  │ reads bundle +       │
│ + manifest.json      │                       │ manifest, env        │
│ executes tool calls  │◄──── JSONL stdout ────┤                      ├──► LLM
│ records the run      ├──── JSONL stdin  ────►│                      │    gateway
└──────────────────────┘                       └──────────────────────┘
```

Out of scope: patch jobs. They run in the patch runner (SPEC-004), which hosts
its own agent conversations with tools in an oubliette room; the elisp patch
adapter that spawned `jailed-pi` was deleted (SL-023) — see OQ-3.
Interactive pi sessions reach the broker over MCP, not through this envelope.

## Responsibilities

Mirrors the structured list:

1. **Provenance** — one declared binary per deployment, and the loop that
   changes it.
2. **Spawn contract** — env, cwd and run dir; nothing else crosses.
3. **Wire protocol** — its requirements; `docs/protocol.md` remains the
   message catalogue.
4. **Jail profile** — declared in named roots and ro/rw, with forbidden binds.
5. **Run-loop context** — enough to read the code; detail stays with CON-001,
   DEC-019 and `docs/resilience-design.md`.

### Provenance

```text
mode spec  :harness (:cmd "jailed-satan-gptel-harness")     ← bare name
   │  executable-find over (default-value 'exec-path)        ← global, never the buffer's
   ▼
~/.nix-profile/bin/jailed-satan-gptel-harness               ← home.packages (satan.nix)
   ▲
~/flakes flake.lock: satan = github:davidlee/satan @ <rev>   ← the one source
```

The deployed harness is the `satan-jailed-gptel-harness` package built from the
pinned `satan` flake input and installed by `home.packages`. A bare `:cmd`
resolves on the editor's global `exec-path`, so no buffer, timer or direnv can
change it (REQ-019). A development build is opted into by giving the mode an
absolute `:cmd`, never by where you are standing.

**Deploy loop.** Building in the working tree proves the wrapper; it does not
deploy it. A harness or jail change ships by: commit and push `satan` → `nix
flake update satan` in `~/flakes` → `just home-switch` → check the resolved
store path (`readlink -f ~/.nix-profile/bin/jailed-satan-gptel-harness`). A
bind whose host source is missing fails every run at spawn, so moving a bound
directory puts this loop on the critical path.

Consequence: the harness ships at the pinned revision while the broker loads
from the live tree. That skew is SPEC-002 REQ-015's concern; REQ-023 is this
container's half of the answer.

### Spawn contract

| Crosses | Value | Source |
|---|---|---|
| command | `:harness :cmd` + `:args` | mode spec, resolved per REQ-019 |
| cwd | the run directory | broker (REQ-021) |
| base env | `(default-value 'process-environment)` | editor's global env (REQ-020) |
| run identity | `SATAN_RUN_ID`, `SATAN_RUN_DIR`, `SATAN_BUNDLE` | broker |
| model + budget | `SATAN_MODEL` (a gateway alias), `SATAN_BUDGET_TOKENS`, `SATAN_MAX_BUDGET_TOKENS` | mode spec |
| key | none: the jail launcher supplies `LLM_GATEWAY_KEY` by fd, and sets `LLM_GATEWAY_URL` | jail launcher (host gateway client key) |
| extra env | `:harness :env` | mode spec |
| inputs | `bundle.json` (rendered prompt), `manifest.json` (tools, mode meta) | run dir (REQ-022) |

The broker resolves no key. The jail starts from an empty environment and
receives only its declared forwards (REQ-025), so nothing else in the base env,
an `op://` reference included, reaches the harness. The launcher process
outside the jail still inherits the editor's env until emacs:SL-015. Inside the jail, the run dir appears at
`/satan/run` and `SATAN_RUN_DIR` is rewritten to match.

### Wire protocol

Newline-delimited JSON over stdio. `docs/protocol.md` is the message catalogue
(types, fields, fixtures); this spec does not restate it. In: `ready`, `log`,
`tool_call`, `final`, `error`. Out: `tool_result`. The broker validates every
inbound message against `satan-protocol.el`; the harness never enacts anything,
it only asks (SPEC-001 REQ-001, REQ-002 are enforced on the broker side).
REQ-023 adds a version to `ready`.

### Jail profile

Declared in root terms (SPEC-002's three roots); host paths stay in
`~/flakes/SATAN.md` (SPEC-002 D2).

| Root / resource | Access | In jail |
|---|---|---|
| run directory (state root) | rw | `/satan/run`, also cwd |
| corpus `hippocampus/` | rw | `/satan/hippocampus` |
| notes root | ro | `/satan/notes` |
| persisted jail home | rw | `$HOME` |
| anything else under the user's home, any source tree | **forbidden** | — |
| editor server socket, MCP socket | **forbidden** | — |
| mounts injected from build or launch env | **forbidden** | — |

REQ-025 makes this the asserted list, together with the env forward list (keys
off argv, ceilings forwarded).

### Run loop (context)

```text
init: read env, bundle.json, manifest.json, build provider
  │      (any failure → error, exit)
  ▼
emit ready
  ▼
┌─► provider.complete(messages, tools) ──exception──► error{class} ─► exit
│     │
│     ▼
│   emit log{usage}
│     │ tokens ≥ max ceiling ──────────────► final{max_budget_tokens}
│     │ satan_final called ────────────────► final{summary, actions}
│     │ warned at tier 3 last turn ────────► final{budget_tokens}
│     │ no tool calls ─────────────────────► final{no_tool_calls}
│     ▼
│   for each tool call: emit tool_call ─► broker executes ─► read tool_result
│     │
│     ▼
│   tier = f(tokens / budget, elapsed / timeout)   never decreases
│     │ rose? withdraw tools, add a system note
└─────┘
```

Tiers: 70% / 85% / 95% of budget (or 85% of timeout → tier 3). Tier 1 drops
survey tools, tier 2 drops focused reads, tier 3 leaves only `satan_final`.
Every tool's tier is CON-001; the ladder's rationale is
`docs/resilience-design.md` §2. The error class is DEC-019's. The broker also
enforces its own timeout and kills the child.

## Concerns

- **Trust boundary.** The harness holds model output. What it can reach outside
  the protocol (mounts, sockets, env) is the boundary's weak side (SPEC-002
  REQ-016, ISS-028). The jail is the only control on that side, so its profile
  must be stated, not inherited from whatever the jail library defaults to.
- **Ambient authority.** ISS-037 showed the failure mode: no single owner for
  binary, env, cwd or mounts, so the calling context decided. Every
  requirement here closes one such ambient input.
- **Revision skew.** Pinned harness, live-tree broker (RSK-016). Until REQ-023,
  a wire change can be half-deployed silently.
- **Failure at spawn.** A missing bind source, a refused gateway key, a down
  gateway or a bad binary kills the run before `ready`. A child that ends with
  neither `ready` nor `final`, and sent no `error`, is recorded as
  `spawn_failed` with a `broker spawn-failed` audit event rather than lost.
  Perception frontiers commit on the first `ready`, so such a run consumes no
  signal (SL-022).

## Hypotheses

- **The envelope survives ADR-018.** When run lifecycle moves out of Emacs, a
  daemon spawns the harness instead of the broker. The contract (one binary
  source, one base env, run-dir cwd, run-dir inputs, versioned wire, declared
  profile) is stated without naming Emacs as its enforcer, so it should carry
  over unchanged; only the "editor's global environment" becomes "the spawning
  process's own environment".
- **One harness profile is enough.** Every broker mode uses the same binary
  and jail. If a mode needs a different sandbox, OQ-1 becomes live.

## Decisions

- **D1 — Envelope, not internals.** This spec owns provenance, spawn contract,
  wire requirements and jail profile. The run loop is context only; its
  decisions stay in CON-001, DEC-019 and `docs/resilience-design.md`, so each has
  one home.
- **D2 — `docs/protocol.md` stays the catalogue.** Message shapes live there,
  next to the fixtures both sides test against; this spec adds requirements
  (REQ-023) and never copies the tables.
- **D3 — Profile in roots, paths in the deployment.** The jail profile names
  roots and access; host paths stay in `~/flakes/SATAN.md` (SPEC-002 D2).
- **D4 — Bare name on the global path is the provenance knob.** The pinned
  install wins by default; an absolute `:cmd` is the only dev override
  (ISS-037). No defcustom, no direnv lookup.

## Open questions

- **OQ-1 — Mode `:jail-profile` → binary.** The manifest records
  `:jail-profile 'specDev'`; nothing enforces it, and the binary alone decides
  the jail. Mapping the profile to the binary (ISS-037 option D) would make the
  mode spec state its sandbox. Deferred until a second profile exists.
- **OQ-2 — Jail library opt-out for env-injected mounts.** `jailed-agents.nix`
  merges `JAIL_WORKSPACE_DEPS` at impure eval. The pinned build evaluates
  purely, so production is unaffected; an explicit opt-out (ISS-037 option A)
  would enforce REQ-025's "no injected mounts" structurally rather than by
  build mode. Next time that library is touched.
- **OQ-3 — Patch adapter coverage.** *Resolved 2026-10-19 (SL-023, DEC-050,
  DEC-064).* Neither old runner survives: the elisp runner (with
  `satan-patch-adapter-pi`, ISS-038) and the Go `satan-patcher` (ISS-039) were
  replaced by the malebolge patch runner, governed by SPEC-004. Patch jobs are
  outside the harness.
- **OQ-4 — Persisted home.** The harness shares the `specDev` persisted jail
  home with every interactive dev jail (ISS-028). Should it get its own?
