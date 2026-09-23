# ISS-019: Composed classify tests enqueue into the production satan_outcome_inbox

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Found while planning SL-017 PHASE-06 (`.doctrine/slice/017/phases/phase-06.md`
Findings F1; notes.md PHASE-06 Findings). Same class as ISS-015 and ISS-018:
the test suite writes into live state.

## Detail

- The composed `satan-intervention-classify` calls
  `satan-intervention--enqueue-attribute-outcome` -> `satan-attribute-enqueue`,
  which uses `satan-attribute-database` (default `satan_memory`) on
  `satan-attribute-host`.
- Under `SATAN_DB_HOST=/run/postgresql/ just check` that resolves to the
  production server.
- `satan-intervention-test--with-db` rebinds only
  `satan-memory-migrate-database`, so the existing classify, manual-writer and
  observer tests insert into production `satan_outcome_inbox` and fire
  `pg_notify` (or fail and are swallowed).
- The new `satan-intervention/classify-composition-unchanged` test (PHASE-06)
  stubs the enqueue; the older tests do not.

## Wanted

The test DB fixture also binds `satan-attribute-database` to the test database
(or the enqueue is routed through a test sink), so no test reaches the
production outcome inbox. Fold into the ISS-018 hermeticity sweep if that lands
first.
