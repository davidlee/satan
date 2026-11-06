# ISS-018: Test suite may write the live ingest cursor file

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Found in SL-017 PHASE-05 (see `.doctrine/slice/017/notes.md`, PHASE-05
Findings). Before that phase, the broker spawn tests (the DEC-8 tests and
PHASE-04's) ran the real `satan-ingest-cursor-advance` and wrote the live
cursor file under `satan-state-root` (`~/.local/state/satan`). A test run could
therefore move the user's real ingest cursor.

## Detail

- PHASE-05's spawn test helper now stubs the cursor advance, so those tests are
  hermetic.
- Other suites that reach `satan-broker--spawn` or the ingest cursor have not
  been audited.

## Wanted

Sweep the suite for writes under `satan-state-root` (and the other live roots),
and bind the roots to a temp dir in a shared test fixture rather than stubbing
per test. A guard that fails the run when a live-root path is written would
keep it fixed.

## More evidence (2026-11-06)

The largest offender is the tick-trace ledger, not the ingest cursor.
`satan-db-query` / `satan-db-psql` route every psql call through
`satan-trace-call` (`satan-db.el:121,164`), which appends a
`kind:"subprocess"` row to `satan-trace-dir` — the live state root by default
(`satan-trace.el:39`). Any suite that touches the DB and does not explicitly
bind `satan-trace-enabled nil` writes there; only the broker tests do
(`satan-broker-test.el:582,635,664,704,787`).

Counted in `~/.local/state/satan/tick-trace-*.jsonl`: **152,983**
`kind:"subprocess"` rows across 13 day-files, and **zero** `kind:"tick"` rows.
Every row is a suite artefact (psql against `satan_memory_test` on a temp
socket). The intended readers of that substrate — a tick report (IMP-063) and
per-stage percentiles (IMP-014) — must currently filter out all of it.

Two fix surfaces, both single-point: bind a temp `satan-trace-dir` in
`dev/satan-test.el` around both batch paths (the runner is the one place that
knows the run is a test; the per-suite rule never anticipated a cross-cutting
ledger), and/or make an unbound-accumulator subprocess row opt-in. Pair with
IMP-015, which fixes the `run_id` those rows render as `{}`.
