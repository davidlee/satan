# Review RV-012 — code-review of SL-017

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Subject: SL-017 PHASE-04 (e1ea308, one tool-ctx from the run struct),
PHASE-05 (3a11272, the single pre-child spawn handler), PHASE-06 (d6e849c,
record before emit), read against HEAD 82de4c5. Recommended by RV-010.
Canon: design sec-4 / sec-5, invariants I2-I4, I6, I7, risks R8-R10; plan
EX/VT for PHASE-04..06; notes.md PHASE-04..06 (already-ruled deviations are
not re-raised: stderr kill only without a child, `:id :null`, verdict
projection skipped after a failed intervention projection, explicit keyword
list on create, evidence nil -> JSON null).

Depth: full pass (subsystem-level, order-sensitive, hard to see in tests).

Lines of attack:

1. `satan-broker--spawn`: `let*` stage order; hoisted `run-id` / `stderr-buf`
   / `run-ctx` / `proc` never re-bound inside the body (handler visibility);
   pre-child vs post-child classification; lock cleared on every path;
   single finalisation; stderr buffer ownership after `make-process`.
2. `satan-broker--record-spawn-failure`: audit-open vs no-audit branches,
   percept mirror, trace stamp, `current-run-id` clearing, diagnostics quality
   of the finalised record.
3. Record/project split: composed `create` / `classify` behaviour-preserving;
   record halves DB-free; FK order; rebuild replay of the undelivered verdict.
4. `notify_send`: I2 (nothing shown before `intervention.created`), I3
   (projection never gates), I4 (undelivered verdict, never signals), result
   shape; every partial-failure combination of the three post-pop steps.
5. Sensor alerts / observer on the canonical tool-ctx: frozen time source,
   A17 gate, cooldown arming on the record.
6. Tests: hermeticity (live corpus, state root, production DB), R8 (no
   re-stubbing around emit), tests that pass for the wrong reason, uncovered
   branches.

Verification: targeted non-DB ert runs only (no `just check`, ISS-013).

## Synthesis

(Reviewer's synthesis, written before disposition; the audit driver owns
dispositions.)

- **Overall**: solid.
- **Synopsis**: The three phases do what the design says. No blocker or
  major defect found. The order-sensitive work holds up:
  - `--spawn` hoists `run-id` / `stderr-buf` / `run-ctx` / `proc` outside
    the one `condition-case`, and nothing in the body re-binds them.
  - `proc` is `setq`'d inside the exec stage, so the handler reliably tells
    a pre-child error from a post-child one.
  - The lock is cleared first on every handler path.
  - Post-child errors re-signal and leave finalisation to the sentinel, so
    nothing is finalised twice.
  - Both no-child branches stamp `spawn_failed`, and the no-audit branch
    clears `current-run-id`.
  - The composed `create` / `classify` behave as before.
  - The record halves never touch the database.
  - `notify_send` never shows anything before `intervention.created` is
    appended.
  - Every recorded outcome returns `ok`, so the cooldown arms on the record.
  - The undelivered verdict passes rebuild validation (`:evidence` `:null`
    is accepted by `--iv-require-object`) and the outcome-table CHECKs.

  Tests do not re-stub around emit (R8). The notify, sensor-alert and run
  suites (46 tests) and the 12 SL-017 spawn/DEC-8 broker tests pass in
  isolation. The standing risks are small:
  - F-1: two spawn-failure tests depend on the live corpus.
  - F-2: a projection window on the undelivered path that the code's own
    docstring says cannot happen; one transaction closes it.
  - F-4: a crash-context flag that now over-reports.
  - F-5, F-6: nits on guard strength and on duplicated no-child failure
    records.

  Accepted as designed and not raised:
  - R-B: the lock is cleared while a post-child child still runs.
  - The misindented `--spawn` body (CHR-009).
  - The parallel intervention-id parsers (IMP-022) and the test ctx
    builders (IMP-023).
- **Haiku**:
  Record, then the pop —
  the ledger line lands first; still,
  two writes, one gap left.
