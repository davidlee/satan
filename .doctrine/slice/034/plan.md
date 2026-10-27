# Implementation Plan SL-034: malebolge wakeups: SATAN schedules its own turns in the room daemon

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Seven malebolge phases build the wake mechanism bottom-up, each ending with
malebolge's `just check` green; one satan phase lands the jail env, the corpus
fragment and governance, then checks the behaviour live. Code lives in
`~/dev/malebolge`; this repo carries the plan, `flake.nix` and governance.

```
PHASE-01 settings + policy + presence      (pure; no harness)
   │
PHASE-02 seams: session clock, beforeResume, scheduled kind, SatanTools.call
   │
PHASE-03 model stream deadline  ── RV-062 F-13 demonstration
   │
PHASE-04 satan.wake: fire + submit          (W1, prepared, failure report)
   │
PHASE-05 bounded wait + abort handler       (relies on PHASE-03)
   │
PHASE-06 tasks extension + wake_* tools
   │
PHASE-07 daemon wiring + sweep + heartbeat  (room only)
   │
PHASE-08 satan: flake.nix env, wake.md, ledger rows, docs; live (VA/VH)
```

## Sequencing & Rationale

- **Pure first.** PHASE-01 has no harness dependency, so the policy's
  arithmetic (clamp, jitter, quiet window across midnight, weighted presence)
  is pinned by fast deterministic tests before anything consumes it.
- **Seams before behaviour.** PHASE-02 changes existing modules only
  (`session.ts`, `conversation-context.ts`, `satan-tools.ts`, the harness
  fixture) and keeps current behaviour; every later test needs the injected
  clock it adds.
- **The deadline before the wait that depends on it.** The bounded wait
  waits unbounded on an `already_placed` input, which is safe only because a
  placed input always settles. That holds for a stalled model stream only with
  `withStreamDeadline`. RV-062 F-13 (route `demonstrate`) requires its
  demonstration to land no later than the first phase relying on this; PHASE-03
  hosts it, ahead of PHASE-05. Its criterion carries F-16's amendment (exactly
  one model request, no retry). PHASE-03 is independent of the wake code, so
  it also isolates the one change that touches both profiles.
- **Task in two halves.** The wake task is the largest unit. PHASE-04 covers
  the happy path, restart dedupe (W1) and the `prepared` host re-check;
  PHASE-05 adds the bounded wait and the abort handler, whose tests need
  failed runs and queued inputs. Tests drive the task by creating it directly,
  so neither half waits on the tools.
- **Tools, then wiring.** PHASE-06's tools need the task and its abort
  handler (`wake_cancel` answers from `{fired}`). PHASE-07 wires everything
  into `startDaemon`, where the start sweep and heartbeat ensure run after
  `resume()`; its tests are the restart-heavy ones.
- **Host side last.** PHASE-08 needs a malebolge commit to pin. Governance
  lands with it (DEC-136); SPEC-002's REV is reconcile's job.

## Notes

- Routed review findings: RV-062 F-13 is the only instrument-routed finding
  (`demonstrate`); it is transcribed in PHASE-03 (EX-2, VT-1, VA-1). All other
  majors are routed `review` and were settled in the design's prose.
- Test files are named in each VT mandate; new suites are `test/wake-*.test.ts`
  in malebolge.
- **The live room daemon runs from the malebolge working tree**
  (`flake.nix` `malebolgeRoot`), so any restart mid-slice runs whatever is
  committed. Consequences for sequencing: PHASE-03 changes the model path of
  both profiles on the next restart, so it must be complete when committed;
  nothing registers the wake task until PHASE-07 wires the extension, so
  PHASE-04…06 are inert in the daemon. From PHASE-07 on, a restart ensures a
  heartbeat in `session.sqlite` even with wakes off (it defers). Once that has
  happened, `satan.wake` v1's input and checkpoint shapes are durable: a later
  shape change needs a version bump and migration, or the start sweep will
  orphan the stored wakes (`task_too_old`).
- Implementation checks the design carries, not design questions: the room
  jail's time zone (PHASE-08 EX-5); per-tool deadlines for in-turn tool calls
  (design Risks; goes to the backlog if any tool lacks one).
