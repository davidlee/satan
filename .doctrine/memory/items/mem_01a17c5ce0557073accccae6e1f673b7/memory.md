Verified 2026-10-27 by spike (SL-034 research; 7/7 vitest tests, faux model,
injected clock `HarnessOptions.now` + `onWake`) against pi-durable 1.4.0
(malebolge's pin; source `~/.local/src/pi/packages/durable`).

- `conversation.submit({type:"input", content, entry:{kind, data}, requestId})`
  starts a turn. The entry keeps the application kind/data (kind must not start
  `pi.`); the model sees a plain user message (`src/harness/types.ts:57-61`).
- `type:"write"` never starts a turn (`docs/spec.md:1012-1014`).
- `requestId` dedupes within one conversation before any write
  (`docs/spec.md:2559`): resubmitting returns the same submission, no second
  turn. Gives idempotent "record, then submit" without a shared transaction.
- A task created with `tx.createTask(def, input, {ownership:{kind:"conversation"},
  conversationId: target, background: true})` whose phase calls
  `runtime.sleepUntil(at, checkpoint)` and whose next phase calls
  `runtime.conversation(target).submit({type:"input",…})` fires exactly once
  at `at`; an overdue sleep fires exactly once after close → reopen →
  `resume()`.
- `Harness.inspect()` lists sleeping tasks as `{kind:"sleeping", until}`;
  `Harness.wake()` gives the next deadline. Without `onWake` the harness arms
  its own timer.
- No setter for a sleep's deadline: reschedule = `abortTask` (abort handler
  commits terminal) + create anew. No fire at the old time.
- Trap: a conversation created without `agent.model` settles input
  `unanswered`/`no_model` (no default model; see
  [[mem.fact.pi-durable.agent-defaults-and-ids]]).
- Not exported: the harness's context-size estimator
  (`src/harness/compaction.ts:390`); recompute with pi-ai estimators.
