# DEC-060: SL-023 runner collects every job's commits through a git-channel port and classifies them from the quarantine

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Revised 2026-10-18 before design lock, after an informal critical review (gpt-6-sol; no RV ledger) — findings 6 and 10: collection outlives room_unavailable via pending_collection; immutable reviewed_oid with ancestry and path checks. User accepted the triage.