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
