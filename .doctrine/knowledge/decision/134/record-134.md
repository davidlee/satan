# DEC-134: SL-034 wake failure visibility: journal line plus notify_send over the scheduled connection (lands in satan-tank)

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->



Amended 2026-10-27 by the SL-034 GPT sense check (codex gpt-6.1-sol, thread 01a17c9f-bea9-7882-bd5c-1f09ef8779b0); dispositions accepted by the user 2026-10-27: the model_error assumption is settled by source (generation.ts:376); removed from scope.

Amended 2026-10-27 by the SL-034 RV-062 design review (codex), F-11, repair accepted by the user 2026-10-27: every wake bounds its wait by one ceiling and then withdraws a still-queued input with Submission.abort() (pi-durable harness/submissions.ts:130-143), so a one-shot stranded behind a failed run in any conversation is withdrawn and reported; a placed input is waited on.