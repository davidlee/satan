# DEC-127: SL-034 wake task: target-owned background pi-durable task, one fire phase, minimal input

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->



Amended 2026-10-27 by the SL-034 GPT sense check (codex gpt-6.1-sol, thread 01a17c9f-bea9-7882-bd5c-1f09ef8779b0); dispositions accepted by the user 2026-10-27: F1 stable occurrence counter `n` in the checkpoint and requestId (was `wake:<taskId>:<at>`, which a defer rewrote); F7 decided `at` carried in the task input. Test: interrupt right after admission, including a restart into quiet hours; exactly one turn results.



Amended 2026-10-27 by the SL-034 RV-062 design review (codex); repairs accepted by the user 2026-10-27 (F-3): a second phase `submit`, checkpointed before the input is submitted, so the abort handler can tell an occurrence that may be admitted from one that is not.



Amended 2026-10-27 by the SL-034 RV-062 verify round (F-3 contest, F-7): the abort handler reads `task.state.checkpoint`; `submit` re-checks the host gate so a prepared but unadmitted occurrence cannot bypass the switch or quiet window after a restart; `prepared` keeps W9 across that defer.



Amended 2026-10-27 (RV-062 F-9): every defer from `fire` spreads the current state, so `prepared` is not lost on a second defer.

Amended 2026-10-27 by the SL-034 RV-062 design review (codex), F-12, repair accepted by the user 2026-10-27: aborting a wake ends the submit invocation that holds the bounded wait, so the abort handler withdraws a may-be-admitted occurrence input that is still queued (Harness.abortSubmission) and reports fired only for a placed or settled input.