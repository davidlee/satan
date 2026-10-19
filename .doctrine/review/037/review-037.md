# Review RV-037 — code-review of SL-027

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Subject: malebolge 1c42811 (SL-027 PHASE-04, design §4.3–§4.5; DEC-079/080/081).
Depth: full pass (trust seam, ~600 lines diff). External reviewer: jailed-pi-research
(read-only, gateway model), findings verified by the implementer-as-raiser before raise.

Lines of attack:
1. Trust invariant (room/connection.ts invariant 2): a host-key refusal is never
   reported or worded as `room unavailable` — tool path, log, startup read.
   Nesting rule: an ObservedConnection wraps a DaemonConnection directly.
2. Reword correctness: type/fields kept (isConnectionLost survives); runner unaffected
   (no reword → identical rethrow); "other failure" untouched.
3. daemonEnv as the single profile→environment seam; Config.cwd removal leaves no
   second source; no runner-tier coupling (structure.test.ts).
4. Startup: bounded execs, home-only reads, [] on down/untrusted, bugs rethrown;
   gateway check presence-only.
5. Lifecycle: one lazy connection reused; close on stop; failure paths at startup.
6. Tests: behaviour not implementation; the F-4 control genuinely discriminates;
   no theatre (e.g. lost-room grep assertion weakened from design wording — §7 R3).
7. Docs (README, internals) true of the code.

## Synthesis

- **Overall**: solid
- **Synopsis**: PHASE-04 makes `daemonEnv` the single seam where an execution
  profile becomes the agent's environment, cwd and startup context. The trust
  invariant holds on both paths into the room. The tool path and the startup
  read each wrap the one bare `DaemonConnection`, so a host-key refusal is
  worded and logged as untrusted, never as downtime. The F-4 control test
  discriminates the nested-wrapper bug (observed red during execution). The
  rule is now also enforced: `observedEnv` refuses an `ObservedConnection`
  (F-3). `reword` keeps the error's type and fields, so the runner, which
  passes none, is unchanged. The eight findings were all minor or nit:
  startup order (the room is reached only after local config is checked),
  failure diagnosis in the startup log, test precision, a type alias, and doc
  accuracy. All are fixed in malebolge 368f625. Standing, accepted: a lost
  room reaches grep as a thrown env error, rendered by the harness, not as
  grep's own `rg could not run:` text (notes § Design errata). The daemon has
  not run against a live room yet; PHASE-05/06 do that.
- **Haiku**: one door, one key — / the room is down, or untrusted; / never both, never mistaken.
