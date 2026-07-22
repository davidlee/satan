# SATAN test DB isolation

# SATAN test DB isolation + skip-unless

## Summary

SATAN's DB-backed ERT suites **isolate themselves** — they target a dedicated
test database (`satan_memory_test`, `trace_test`, `patch_live_test`),
`skip-unless` it is reachable, and `reset-and-migrate` (drop + re-migrate) per
test via macros like `dl-satan-intervention-test--with-db`. Pure suites (e.g.
`attribute-listener`) mock the psql subprocess. They never touch the production
DB.

## Context

`just check` (`dl-test-run-suite`, `dev/dl-test.el`) therefore runs **all**
suites under `satan/test` + `lisp/test`. Do **not** re-add a per-subsystem
exclusion list: it would duplicate the in-suite policy (coarser + wrong) and
bench pure tests. The earlier `dl-test-db-excludes` was removed for exactly
this reason (2026-05-30).

Consequence: if the test DB is up, the DB suites run for real; if it is down,
they skip. Running the full suite surfaced 2 pre-existing failures in
`dl-satan-intervention-mark-test.el` — see `ISSUE-002`
(`dispatch-routes-to-writer` is wall-clock time-dependent;
`recent-orders-newest-first` passes in isolation but fails in the full run →
shared-DB cross-talk). These were masked while the suite was excluded.

Related: [[mem.fact.satan.followups-superseded-by-backlog]].
