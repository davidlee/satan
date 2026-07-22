# ISS-007: Grammar db-sync tests target the production DB name and silently skip

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`satan/test/satan-memory-grammar-test.el:22` resolves its database as
`(or (getenv "SATAN_MEMORY_TEST_DB") "satan_memory")` — the **production**
name. Every sibling DB suite hard-codes a `_test` database
(`satan_memory_test`, `trace_test`, `patch_live_test`) and drop/re-migrates it
per test.

Consequence: unless an operator happens to have exported
`SATAN_MEMORY_TEST_DB`, the three `db-sync-*` tests
(`db-sync-current-version`, `db-sync-aliases`, `db-sync-default-weights`)
`skip-unless` an unreachable DB and never run. They are the only check that the
elisp grammar constants match the SQL migration — the drift they exist to catch
is exactly the drift nobody would notice.

Observed 2026-07-22: with `satan_memory_test` / `trace_test` /
`patch_live_test` created, the suite runs 1035 tests with 0 unexpected and 16
skipped; three of those 16 are these.

## Why it is not simply "point it at satan_memory_test"

The sibling suites `DROP TABLE ... CASCADE` and re-migrate inside their
`with-db` macros. Pointing the grammar suite at the same database makes its
result depend on whether some other suite has migrated first — order-dependent
green, which is worse than an honest skip. A fix needs either its own database
or its own migrate step, not just a name change.

## Why it matters now

SL-002 PHASE-06 **VT-2** requires `satan-memory-grammar.el` and
`0002_grammar_v1.sql` to be byte-identical pre/post and
`satan-memory-grammar-test.el` green **unmodified**, `db-sync-*` included —
that is the preserved-artifact guarantee for the bough grammar. While these
tests skip, the DB half of VT-2 is unverifiable and the byte-identity half
carries the whole claim.

Not a blocker for SL-002: the no-diff check is a genuine (if narrower) guard,
and the pure internal-consistency tests in the same file do run. Recorded so
the audit does not mistake a skip for a pass.
