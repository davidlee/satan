# DEC-128: SL-034 decider: an async WakePolicy seam with injected env; v0 is clamp, jitter, quiet window, weighted presence

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Narrowed by DEC-139 (SL-034 inq-11): jitter, retry step, presence weight and percept deadline are code constants; floor, ceiling and quiet window are env config.



Clarified 2026-10-27 by the SL-034 GPT sense check (codex gpt-6.1-sol, thread 01a17c9f-bea9-7882-bd5c-1f09ef8779b0); dispositions accepted by the user 2026-10-27 (F6): gate() decides admission; a followUp admitted while the conversation is busy starts when the running turn ends, possibly inside the quiet window. Accepted for v0.