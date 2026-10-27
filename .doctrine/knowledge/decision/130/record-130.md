# DEC-130: SL-034 tool surface: wake_schedule/wake_cancel/wake_list; target is the caller or a known topic's latest, resolved at schedule

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->



Amended 2026-10-27 by the SL-034 GPT sense check (codex gpt-6.1-sol, thread 01a17c9f-bea9-7882-bd5c-1f09ef8779b0); dispositions accepted by the user 2026-10-27 (F5): abortTask after submission leaves the queued turn, so wake_cancel acts only on a sleeping wake. Test: cancel racing a fire.



Amended 2026-10-27 by the SL-034 RV-062 design review (codex); repairs accepted by the user 2026-10-27 (F-3): cancel waits for the task to settle and reports from its result; the answer may say already fired for a wake that never submitted, never cancelled for one that did.