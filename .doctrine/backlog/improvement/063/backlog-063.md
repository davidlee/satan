# IMP-063: Tick ledger review: derive null-tick and signal coverage from what runs already record

## Why

A discarded improvement card (authored in a worker confined to `./satan`) proposed
writing one `kind='observation'` trace per tick into `traces`, on the premise that
nothing records a tick that looked and declined. That premise is false: the null
tick is already recorded, in state. What is missing is a *reader*.

## What already exists (checked 2026-11-06)

- Every run writes `runs/<date>/<run-id>/`: `percept.json` (canon handle list plus
  per-handle `rule_id` / origin), `bundle.json`, `actions.json`
  `{applied,staged,rejected,failed}`, `final.json`, `transcript.jsonl`
  (`satan-audit.el:5-8`; close at `satan-audit.el:109-130`). Perceive runs
  unconditionally *before* both spawn gates, so even a refused tick persists its
  percept (`satan-broker.el:670-690`).
- Every run also appends one `kind:"tick"` JSONL row carrying `outcome` in
  `{spawned, perceive_failed, budget_denied, run_busy, spawn_failed}` plus per-stage
  ms (`satan-trace.el:161`; stamped at `satan-broker.el:693,706,709,925`).
- So a tick that spawned and did nothing is `actions.applied: []` with its percept
  on disk. The opportunity denominator exists; only the psql side is all-positive
  (`satan-observer.el` writes observation traces where an intervention was made, and
  `ignored` already exists as a classification with its own counter,
  `0007_patterns.sql:82-100`).
- Existing readers to reuse: `satan-budget--run-tokens` (`satan-budget.el:27`) and
  `satan-context--list-recent-runs` (`satan-context.el:256`), both walking
  `satan-run-dirs-for-date`. Do not build a second run-dir walker (cf. IMP-018).

## Wanted

One read-only analysis over those artefacts — no new schema, no new write path.
Over a date range it answers:

- ticks/day by mode, status mix, how many ticks applied nothing, and what those
  ticks cost;
- sensor-missing rate per sensor — how often the percept is ctx-only (the starvation
  case IMP-064 has to survive);
- pattern near-misses: for each cue set in `satan-pattern-file`
  (`satan/patterns.eld`), the handles it is missing against a run's percept
  (`|cue \ handles| == 1`), computed from `percept.json` with no `satan_patterns`
  rows and therefore working today despite ISS-063;
- daily spend against `satan-budget-daily-tokens`.

## Not this item

Perf percentiles from the tick-trace rows are IMP-014's half. This is coverage /
recall, not latency.

## Caveat

`~/.local/state/satan/tick-trace-*.jsonl` is polluted: `satan-db-*` ledgers every
psql call, so any suite that touches the DB writes live rows (ISS-018). As of
2026-11-06 the files hold 152,983 `kind:"subprocess"` rows and **zero**
`kind:"tick"` rows. The report must filter on `kind` and a non-empty `run_id`.

## Implementation

`SL-036` (increment 1) implements this item's reader as `tick_explain`, and goes on to a
shadow policy oracle only if the reader shows the loop's decisions are reconstructible. The
slice is the work; this item stays as the statement of what "coverage" means.
