# DEC-055: SL-023 runner pauses a job while the room is down and resumes its conversation when reachable

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Revised 2026-10-18 before design lock, after an informal critical review (gpt-6-sol; no RV ledger) — finding 5: EVD-005 shows recovery after one failed call (daemon kill) not automatic pausing on a VM stop; the signal and interception point must be proven. User accepted the triage.


Revised 2026-10-18 at design review (RV-025 F-2, F-5; Codex gpt-6-sol): pi-durable catches tool and environment exceptions before afterTool, so a typed failure would reach the hook as text. Recognition moves to a per-job wrapper over pi-env's ExecutionEnv, which catches the typed failure and marks the job room-down; afterTool reads that mark and triggers the pause. waiting_room is entered only from running; a room down during preparing retries within max_room_wait, then fails room_unavailable.


Revised 2026-10-18 at RV-025 verification (F-16, F-17): the env wrapper records pause_requested durably at catch time (afterTool only reads; no in-memory fallback), and each waiting episode's resume message is named resume-<job id>-<pause_count>, pause_count incremented with waiting_room, so a restart resubmits the same id.