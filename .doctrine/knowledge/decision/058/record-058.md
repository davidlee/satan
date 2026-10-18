# DEC-058: SL-023 runner control socket: same-uid UDS never bound into a jail, NDJSON request/response, no promotion

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Revised 2026-10-18 before design lock, after an informal critical review (gpt-6-sol; no RV ledger) — findings 3 and 4: a disposition report is an authority unless verified; every RPC is schema-validated by the runner. User accepted the triage.


Revised 2026-10-18 during drafting, user direction (pre-ready fixes, item 4): a failed or cancelled notice sent while Emacs is absent would be lost, so watch connect resends unacked failed/cancelled jobs and Emacs acks them with a new ack operation.