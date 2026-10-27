# DEC-131: SL-034 heartbeat: one perpetual recurring satan.wake in a dedicated daemon-written topic

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->



Amended 2026-10-27 by the SL-034 GPT sense check (codex gpt-6.1-sol, thread 01a17c9f-bea9-7882-bd5c-1f09ef8779b0); dispositions accepted by the user 2026-10-27 (F4): pending = sleeping wakes only; ensureHeartbeat treats blocked/parked as dead; gap bound qualified. The user declined changing afterFailedRun.



Amended 2026-10-27 by the SL-034 RV-062 design review (codex); repairs accepted by the user 2026-10-27: F-1 a heartbeat stuck behind a failed run is an active invocation (inspect reports running), so start-time detection cannot see it; replaced by a bounded wait in `submit`. F-2 abort-marked tasks do not count as live, making replacement restart-safe.

Amended 2026-10-27 by the SL-034 RV-062 design review (codex), F-11, repair accepted by the user 2026-10-27: every wake bounds its wait by one ceiling and then withdraws a still-queued input with Submission.abort() (pi-durable harness/submissions.ts:130-143), so a one-shot stranded behind a failed run in any conversation is withdrawn and reported; a placed input is waited on.

Amended 2026-10-27 by the SL-034 RV-062 design review (codex), F-14, repair accepted by the user 2026-10-27: a start sweep aborts every blocked satan.wake and withdraws its queued inputs itself, since aborting a definition-blocked task cannot run its abort handler (pi-durable docs/spec.md, blocked tasks); ensure then only counts and creates.