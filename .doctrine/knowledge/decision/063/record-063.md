# DEC-063: SL-023 cutover: delete both old runners, drop patch_jobs from satan_memory, one consumer at every step

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Revised 2026-10-18 before design lock, after an informal critical review (gpt-6-sol; no RV ledger) — finding 7: two consumers are enabled today, so the invariant needs an explicit fence step before any schema drop. User accepted the triage.