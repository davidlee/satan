# ISS-013: Concurrent `just check` runs clobber the shared test databases

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found during the SL-015 reconciliation audit (RV-005 F-8), 2026-09-17.

The DB-touching suites target **fixed database names by defconst** —
`satan_memory_test`, `trace_test`, `patch_live_test` — and each one runs
`reset-and-migrate` at setup. There is no per-run namespacing and no lock, so
two overlapping `just check` invocations tear each other's schema down
mid-migration.

Observed: two runs overlapping by a few seconds produced **14 unexpected
failures** across `satan-memory-store/*` and `satan-memory-renormalize/*`, with
conditions

```
Migration 1 (0001_init.sql) failed: … ERROR: duplicate key value violates unique
constraint "pg_type_typname_nsp_index"  DETAIL: Key (typname, typnamespace)=
(schema_migrations, 2200) already exists.
Migration 7 (0007_patterns.sql) failed: … ERROR: relation "satan_interventions"
does not exist
```

A serial re-run of the identical command returned the documented bar exactly:
`Ran 1044 tests, 1040 results as expected, 1 unexpected, 3 skipped`.

## Why it matters

This is the fourth independent way this repo reports a false result, and the
only one that manufactures **failures** rather than hiding them:

| # | Mechanism | Tracked as |
|---|---|---|
| 1 | `just check` exits 0 with any number of failures | ISS-008 |
| 2 | `just lint` is paren balance only — no byte-compile | design SL-015 §9.1 |
| 3 | ~130 tests skip silently without the test DBs | `justfile:18-20` |
| 4 | **concurrent runs clobber each other** | this item |

The first three cost a missed defect. This one costs audit time chasing a
phantom regression — and an agent that runs the suite in the background while
starting another is the most likely trigger.

## Options

- Namespace the databases per run (`$$`, or a `SATAN_TEST_DB_SUFFIX`), so
  concurrent runs are isolated. Fixes it properly; touches the three defconsts
  and `db-setup`.
- Take an advisory lock (`pg_advisory_lock`) around `reset-and-migrate`, so the
  second run blocks rather than corrupts. Cheaper, serialises the slow part.
- Document it only: a warning in the justfile. Cheapest, and leaves the trap
  armed.

Relates to [[ISS-008]] — together they mean neither the exit status nor the
failure list can be trusted without knowing how the run was invoked.
