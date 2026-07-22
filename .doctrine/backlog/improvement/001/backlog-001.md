
# A16 audit verifier: cross-check notified.json against actions.json.pre_spawn

A16 one-to-one — `notified.json` ↔ `actions.json.pre_spawn`. Phase 4.4 test
asserts the invariant at the producer. The audit verifier
(`dl-satan-audit.el`'s `--p/pre-spawn-shape`) does not yet cross-check the two
artefacts.

**Blocked:** add once a fixture corpus exists.

Migrated from `docs/satan/follow-ups.md` §"Audit verifier extensions" (2026-05-30).
