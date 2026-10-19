# Review RV-036 — code-review of SL-027

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Subject: SL-027 PHASE-02 — malebolge `e2aaf98..87f48e3` (5 commits). Extracts
the room tier (`src/room/{connection,shell,source-reader,door}.ts`) out of
`src/runner/*`. Pinned to design §4.1 (API, moves, stays, module header), §5
rows, §6 "Runner unchanged" / "Door parser", and `plan.toml` PHASE-02 EX-1..EX-5.

Lines of attack:

1. Invariant 1 (room tier names no job/door/kind): does runner policy leak into
   `src/room/`? Is the structure-test allowlist (ROOM_ROOTS) actually enforced?
2. Behaviour preservation: "Runner unchanged" — any semantic drift in env,
   project-context, prepare, collect, pause, start, run, config.
3. EX-10 matcher `withoutSpecifiers` (`test/runner/room.test.ts`): sound, or
   does it hide door knowledge?
4. `Degradation` union discrimination via `"code" in degradation` in `run.ts`.
5. `DOOR_KEYS.room` derived from `ROOM_DOOR_KEYS`: error-order change
   (`identity` before `ssh_config`) — observable regression?
6. API surface beyond §4.1: `successStdout`, `answerable`, `Attempt`, `jobEnvId`.
7. `ObservedConnection` built twice (`roomShell`, `jobEnv`) — duplication ahead
   of PHASE-04's third consumer.
8. Tests: moved, not lost; fixtures cohesive; behaviour not implementation.

## Synthesis

- **Overall**: acceptable (solid after fixes).
- **Synopsis**: PHASE-02 moves the room tier out of `src/runner/` and keeps
  behaviour. `ObservedConnection` is the old `JobConnection` byte for byte;
  `sshTarget`, `daemonCommand` and `DaemonConnection` moved verbatim; env ids,
  reader classification and the `onlyKeys` sets are unchanged. The tests moved
  rather than being lost: no skips were added, and test titles match before and
  after. `src/room/` names no job, pause, profile or kind. The structure test
  rejects the import edges §4.1 forbids. `"code" in degradation` is sound under
  `exactOptionalPropertyTypes`. The review found two minors. (1) EX-10's
  specifier strip left a blind spot: a runner module could import the door's
  parser without tripping it. The structure test now pins who may import
  `room/door.ts`. (2) The observed-env construction existed in two copies, and
  PHASE-04 would have added a third. `observedEnv` is now the one builder.
  Five nits: three were fixed, one was recorded only (key-order wording), and
  one is a §4.1 erratum (unlisted exports). The F-3 fix also changes §4.1
  (`ReadFailure` loses `"exit"`), with the user's assent. Standing risks:
  EX-10 is still a text heuristic, so its kind regex can be evaded by
  constructs it does not know. The import-edge rule is the stronger guard.
  PHASE-03 must add the daemon's `config.ts` to both lists.
- **Haiku**:
  Two rooms built one way —
  the door's keys, read by few hands;
  the wrapper stands once.
