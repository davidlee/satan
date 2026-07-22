
# A13 audit verifier: cross-check observer.json against intervention transcripts

A13 one-to-one — `observer.json` ↔ intervention transcripts. After Phase 5.8
landed, the observer's dedup state file is the canonical record of classified
interventions; the audit verifier should cross-check it against each run's
`transcript.jsonl`.

**Blocked:** add once observer fixtures exist.

Migrated from `docs/satan/follow-ups.md` §"Audit verifier extensions" (2026-05-30).
