# RSK-015: Postgres migration numbering collision: satan_memory (elisp) and satan_attributes (attrd) both use NNNN sequences

Two migration runners, two databases, one colliding numbering convention
(observed 2026-07-06):

| Owner | Database | Sequence |
|---|---|---|
| `satan/dl-satan-memory-migrate.el` + `satan/memory/migrations/` | `satan_memory` | 0001–0007 (memory, patch_jobs, interventions, patterns) |
| `~/dev/satan-attrd/migrations/` | `satan_attributes` | 0007–0012 (attributes, outcome_inbox, audit_*) |

Not broken today — separate databases — but "0007" already means two
different things, and each future daemon extraction (IMPR-006..009) would
bring its own migration dialect and sequence. Failure mode: a migration
applied to the wrong DB, or schema ownership ambiguity when a table moves
between owners during extraction.

Direction discussed in RFC-001 §D4: one schema owner per database; migration
ownership consolidated at the flake level or in the DB-owning component.
Resolution options (RFC-001 outcome, open): renumber vs freeze-and-diverge.

Trigger to act: next extraction that touches postgres (IMPR-007 memory
substrate is the natural point — the elisp runner leaves with it).
