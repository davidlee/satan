# DEC-139: SL-034 daemon wiring: late-bound tasks extension, harness-armed timer, heartbeat ensured after resume, five env keys

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->



Amended 2026-10-27 by the SL-034 GPT sense check (codex gpt-6.1-sol, thread 01a17c9f-bea9-7882-bd5c-1f09ef8779b0); dispositions accepted by the user 2026-10-27 (F3): "no jail change" was wrong; the wake keys are set in the room jail and probed by the launcher check. The ~/flakes unit step is dropped.



Amended 2026-10-27 by the SL-034 RV-062 design review (codex); repairs accepted by the user 2026-10-27: F-5 room-profile gate; F-6 beforeResume receives the Session and binds Conversations synchronously.