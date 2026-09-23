# Implementation Plan SL-017: SATAN reports on SATAN: one emit seam, record before emit, persistent failures stay loud

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.

## Overview

Eight phases, one per design mechanism, ordered so that every phase lands
green and each one's tests can rely on the previous ones.

```
phase     builds                          needs
PHASE-01  announce seam, hermetic suite   —
PHASE-02  outcome + streak walk (leaf)    01
PHASE-03  failure reason (slot, harness)  02
PHASE-04  one tool-ctx                    03 (slot)
PHASE-05  pre-child spawn handler         04 (early struct), 03 (slot)
PHASE-06  record before emit              04 (real pre-spawn ctx), 01 (seam)
PHASE-07  announce policy / back-off      02, 03, 05
PHASE-08  deploy + live evidence          01-07, keeper
```

## Sequencing & Rationale

- **PHASE-01 first.** Every later phase adds or rewrites tests that touch
  emits. Until the harness binds the recording sink, those tests either leak
  into the journal and D-Bus (ISS-015) or need the per-file stubs the design
  removes. The five sites move onto the seam with their current policy, so
  this phase changes delivery only, not behaviour.
- **PHASE-02 is pure leaf work.** It adds readers to `satan-run.el` and moves
  the two existing run-id parsers onto them. Nothing calls the streak yet, so
  the phase is low-risk and testable in isolation.
- **PHASE-03 before PHASE-04.** The `failure-reason` slot is appended to the
  `satan-run` struct here. PHASE-04 then reorders `--spawn` around that
  struct, and PHASE-05 writes `spawn_failed` into the slot. Doing the struct
  change first keeps each `--spawn` edit to one concern. The harness change
  rides in this phase because it is the other half of the same decision
  (DEC-019), and its tests are independent.
- **PHASE-04 and PHASE-05 are split,** though both edit `--spawn`. PHASE-04 is
  a behaviour-preserving consolidation, except that pre-spawn alerts now get a
  valid ctx. PHASE-05 changes failure semantics. Separating them means a
  regression in the longest broker function (R10) points at one change.
- **PHASE-06 needs PHASE-04.** Record-before-emit for pre-spawn alerts only
  works once they carry the run's audit handle.
- **PHASE-07 last among the code phases.** The back-off policy reads outcomes
  (PHASE-02), matches recorded reasons such as `auth` (PHASE-03), and must
  count `spawn_failed` runs (PHASE-05). Until then the broker keeps its current
  streak==1 policy, delivered through the seam.
- **PHASE-08 needs the keeper.** The push and home-switch are outward-facing,
  and the live checks (V4) need real runs.

## Notes

- **Deploy order (R13).** The live Emacs loads the package from this working
  tree, but the jail runs the harness from the GitHub flake input. So
  PHASE-07's policy can be live while the old harness still reports a
  moderation 403 as `auth`, and it would then pop critically on every run.
  Deploy the harness (PHASE-08 EX-1) before PHASE-07 is loaded into the live
  Emacs. Pulling the push forward to just after PHASE-03 is the simplest way,
  and it needs the keeper's approval.
- **The harness binding must be dynamic.** `dev/satan-test.el` is
  lexical-binding. Without `(require 'satan-announce)`, its `let` of the sink
  is a lexical no-op, the suite is not hermetic, and the self-check test is the
  only thing that would notice.

- **Code review at `/audit`.** RV-010's conclusion: PHASE-05 (spawn handler)
  and PHASE-06 (classify split) get a code review.
- **`satan-intervention-test.el` and `satan-observer-test.el`** use the real
  test database `satan_memory_test` (`just db-setup`). A missing database makes
  them skip silently, so check skip counts.
- **Follow-ups at reconcile:** the REV to the authority-ledger row 4 standing
  note (operational alarms), optionally a REQ-003 acceptance criterion, and
  the `session_blocked` correction to mem_eb8e5cff794c48bd86597f94fa50b0ac.
