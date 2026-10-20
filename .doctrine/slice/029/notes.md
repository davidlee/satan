# SL-029 notes — pi-agent MCP server

## Design-surface triage (explore.triage)

### Constraining governance (verified, see `research/research.md`)

- **ADR-017 §3**: one owner per authority item; rows 1/2/3/4a/5a/6a are
  `emacs-client`, 3b `satan-flake`, 4b/5b/6b/8/9 `patch-runner`. No "adds no
  authority" escape → the server needs a new token (proposed `pi-mcp`) for schema
  validation, profile→tool allowlist, audit, ceiling and kill switch.
- **Operator convention (memory `flake-wrapped-execution`)**: jail policy is
  project-specific, lives in the flake, exposed as a wrapped form → the execution
  profile row is `satan-flake`'s (row-3b precedent) and `pi/mcp` carries no bwrap
  argv. A second enforcement site would breach SPEC-001 REQ-009.
- **SPEC-001 REQ-001..011** bind generically. REQ-004 is the sharp one: with
  DEC-057, a wall-clock backstop alone is nonconformant — ceilings are needed on
  model requests, cost, tokens and active wall clock. DEC-043 forbids treating
  gateway budgets as SATAN ceilings.
- **SPEC-002 REQ-016 AC1/AC2**: any jail receiving model output needs a declared
  per-consumer-class profile, test-asserted, not binding the editor eval socket
  and not rw the home/source/notes roots.
- **SPEC-003 is dark** for this surface (broker-spawned Python harness only).
- **Read-only is an OS claim, not a tool list**: every profile declares `bash`.
- **No stdio MCP container exists in SPEC-002**; no resident standard exists.

### Shaping decisions (proposed, not yet locked)

1. Transport: stdio, one blocking call — settled by the operator, recorded in
   IMP-046. No steering, no job handles.
2. Confinement is delegated to a flake-provided wrapped runner; the server never
   builds bwrap.
3. The reducer's `Reduced` gains a `result` field so the server need not parse its
   own transcript.
4. Wire protocol hand-rolled on `node:` stdlib (~100 lines, `satan-mcp` precedent);
   no TS dependency mechanism exists and adding one would be new infrastructure.

### Open questions (candidates for the inquiry graph)

- **OQ-A (blocking) — `cwd` vs a launch-time jail.** A jail is fixed when the
  wrapper starts; `pi_agent` takes a `cwd`. Per-call launcher from the flake, or
  one root fixed at launch with refusal outside it?
- **OQ-B (blocking) — the ceiling.** Which of request/cost/token/wall-clock
  ceilings does the server enforce itself, which does it delegate to the wrapped
  runner, and where is the number recorded? REQ-004 + DEC-057 make "time only"
  nonconformant.
- **OQ-C (blocking) — the ledger split.** Confirm the proposed `pi-mcp` row set
  and the `satan-flake` execution-profile row; state each row's `Enforced at`.
- **OQ-D — profile resolution trust boundary.** Where does `profile` resolve
  (server install root, never the call's `cwd`), and what is the name grammar?
  Untrusted MCP input is joined into a path today (`scripts/pi-agent:42`).
- **OQ-E — read-only posture.** How is "read-only by default" made true given
  `bash` can write: a second wrapped runner for read-only profiles, or a profile
  flag the flake consumes?
- **OQ-F — session continuity vs the run dir.** `session` needs a stable session
  dir; `/tmp` is a tmpfs per jail run. Where does it live, and what is cleaned up?
- **OQ-G — result shape.** Exact JSON for `{state, result, transcript, status,
  transcript_path}`; whether `transcript` in the response is budgeted, and where
  the artefacts land.
- **OQ-H — the kill switch.** What `pi-mcp`'s switch actually is (env, config
  file, absence of the server binary) and how it fails closed.
- **OQ-I — audit.** Where delegate actions and control decisions (spawn, refuse,
  timeout) are appended, given the server may run without Emacs and without the
  SATAN DB.

### Risks

- Building a second confinement site (REQ-009) if the flake boundary is blurred.
- A ceiling implemented in the server while the wrapped runner also caps
  (two enforcement points).
- Nested jails are additive: running inside `jailed-claude` inherits that
  profile's defects (eval socket, notes reach) — the flake profile must be fixed
  regardless.
- `just test` is behind the test-DB gate; an un-gated TS suite is invisible to
  `doctrine.toml`'s `just check` gate.

### Assumptions

- bwrap works nested (operator-stated; the union rule).
- `pi --mode json` self-exits and its exit code is not the verdict.
- The wrapped runner can be exec'd per call without a measurable startup cost
  worth avoiding.

## Inquiring results (rev 18)

| inquiry | outcome |
|---|---|
| inq-1 | DEC-089 wrapped runner launched per call; the flake binds the launcher's `$PWD` (`jailed-agents.nix:197`), so the root is per call for free |
| inq-2 | DEC-090 ceilings owned by `pi-mcp`, gated on the event stream, one-response overshoot (DEC-057 precedent); gateway budgets stay insurance (DEC-043) |
| inq-3 | DEC-091 five `pi-mcp` rows + one `satan-flake` profile row |
| inq-4 | DEC-092 profiles resolve only from the server's tracked profile dir under `^[a-z][a-z0-9-]{0,31}$`; unknown profile refuses, never defaults |
| inq-7 | DEC-093 `pi-agent-result/1`; `status` embedded verbatim; `Reduced.result` added; artefacts outside the tree under `PI_MCP_RUN_DIR` |
| inq-9 | DEC-094 audit is the server's own append-only `audit.jsonl` per run; pi's event stream is not the audit |
| inq-5 | deferred — provisional: a second wrapped form (read-only) built by the flake, since the rw root bind is the flake's (DEC-089 consequence 3) |
| inq-6 | deferred — provisional: session dir inside the bound root (`.pi-session/<id>`), never `/tmp` (per-run tmpfs) |
| inq-8 | deferred — provisional: enable is absence/sentinel in the read-only maxima artifact the server already loads (DEC-090), so one artifact carries numbers and the switch |

## Process lifetime (user-conveyed, 2026-10-20)

`jailed-pi` dies when its launching shell exits (`bwrap --die-with-parent`), which is
what kills a worker launched with `nohup … &`. The user's working pattern is
foreground chunks inside one supervisor call, resuming via `--session-id` when a
chunk runs out of the timeout. Recorded as
`mem.fact.jail.background-launch-dies-with-shell`.

Design consequence: the server must not detach its child, and the driver must not
background the server. A stdio MCP server launched by the driver satisfies this by
construction — the child's parent is the server, the server's parent is the
driver — but it must be stated, because "detach and poll" is the obvious wrong
answer for a long delegate call, and it silently yields a dead jail and no result.

## Correction: the wrappers are in-repo declarations, not cross-repo machinery

An earlier note called the read-only form and the session-dir bind "cross-repo
flakes/agents dependencies". Wrong on both counts:

- `makeJailedAgent { agent = <derivation>; profile = …; extraOptions = … }`
  already takes any executable and any profile, and `extraOptions` already
  carries raw bwrap args in this repo's flake (`--ro-bind "$HOME/notes"`,
  `flake.nix:159`). Both forms are a few lines in `satan/flake.nix`.
- **But `profile = "research"` is not a read-only mode.** Profiles carry only
  persisted home, network, and per-profile git/op-env defaults
  (`jailed-agents.nix:205-232`). Read-only-ness is `mountLaunchDir`, whose true
  branch rw-binds the launch dir (`:193-198`). A read-only root needs
  `mountLaunchDir = false`, or a raw `--ro-bind "$PWD"` + `--chdir` in
  `extraOptions`.

Two real remaining items: the server must be a **derivation** to be passed as
`agent = …` (today `bin/pi-mcp` is a repo shim — a `writeShellScriptBin` is
enough), and the fork below.

## Open fork: jail the server once, or the runner per call

`agent = pi-mcp` is possible and would mean the *server* is the jailed process,
children inheriting (intersection of authority). That shape and DEC-089's
per-call wrapper are different products:

| | jail the server once | wrapper per call (DEC-089/098) |
|---|---|---|
| roots | fixed at server launch | per call, arbitrary allowlisted root |
| capabilities | one jail = one filesystem mode; read-only needs a second server | both modes in one server, selected per profile |
| server's own writes | confined | unconfined (writes run/audit dirs) |
| moving parts | wrapper only, no child jail | wrapper per call |

MCP stdio configs are per-project anyway, so a server-per-project jail is
defensible and simpler; it costs the multi-root, mixed-capability case. Not
settled — it changes DEC-089 and DEC-098.

## Evidence isolation across the three forms (asked at review)

RV-043 F-1/F-2 left static mode visibly weaker than per-call. Where does it sit
relative to the shell wrappers (`scripts/spawn-confined.sh`, `pi-agent`)?

| | shell script (today) | per-call MCP | static MCP |
|---|---|---|---|
| child can reach its own evidence | no — unjailed shell redirects the child's stdout to a host file | no — evidence dir not bound | **yes** — same jail, same uid; mitigated by memory buffering, flushed after exit |
| crash durability of evidence | yes (written as it streams) | yes | **no** — a server crash loses the buffered run |
| jail per call / distinct roots | yes, one bwrap per invocation | yes | **no** — one jail, one root for the process |
| session continuity across runs | per-worktree session dir only | yes, one bound dir per session | yes, but the shared home is visible to co-resident children |
| policy surface (ceilings, audit, allowlist, refusals, result shape) | none — the orchestrator parses a shell | full | full |
| supervisor readable by a human | yes — a shell script | no — node | no — node |

Verdict: static mode is a **policy upgrade and an isolation downgrade** relative
to the script form. It does not improve the one property the script form already
has by construction (an unjailed supervisor writing evidence no child can touch);
it improves the properties the script form has none of (ceilings, audit,
allowlisting, refusal/result contracts).

Two consequences worth carrying into the plan: static mode's evidence mitigation
trades tamper-resistance for crash-durability, and it must bind the policy file
read-only or the child can rewrite its own switch.
