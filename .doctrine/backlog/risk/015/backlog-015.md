# RSK-015: Two migration owners share satan_memory: elisp runner and satan-attrd, overlapping NNNN sequences

Two migration runners, **one database**, overlapping numbering. Corrected
2026-09-23: the original (2026-07-06) text placed attrd in a separate
`satan_attributes` database. Production has never looked like that —
verified against the system Postgres:

| Owner | Database | Ledger table | Applied |
|---|---|---|---|
| `satan/satan-memory-migrate.el` + `satan/memory/migrations/` | `satan_memory` | `schema_migrations` | 1–7 (memory, grammar, patch_jobs, interventions, patterns) |
| `~/dev/satan-attrd/migrations/` via `satan-attrd migrate` (sqlx) | `satan_memory` | `_sqlx_migrations` | 7–12 (attributes, outcome inbox, audit inbox/replies, decay, settings) |

Not broken today: the ledgers are separate tables, so neither runner sees the
other's versions, and the table names don't collide. But:

- "0007" means two different migrations in the same database.
- Neither runner knows the other exists. Nothing stops a table-name
  collision, and a satan-side `DROP ... CASCADE` (the test fixtures do this)
  can take attrd objects with it if an FK ever crosses owners.
- The broker reads and writes attrd-owned tables (`satan_outcome_inbox`,
  `satan_attributes`, `satan_attribute_settings`, audit tables), so schema
  ownership is already split across repos within one DB.

Direction: RFC-001 §D4 (one schema owner per database; migration ownership
consolidated in the DB-owning component) and ADR-018 D1 (satan-attrd is
absorbed into the daemon-core repo; one database, one authority) — that
absorption is the natural point to unify the ledgers. Resolution options
still open: renumber vs freeze-and-diverge.

Interim control: SL-019 pins satan-attrd as a flake input and runs its
migrator against the test DB, so satan's suite exercises the real combined
schema and the pinned version is explicit in `flake.lock`.

Trigger to act: the ADR-018 D1 absorption, or the next extraction that moves
a Postgres-backed module (the elisp runner leaves with the memory substrate).
