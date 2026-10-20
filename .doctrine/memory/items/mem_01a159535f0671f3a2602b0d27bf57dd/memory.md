Verified 2026-10-20 against pi HEAD `26293e74f` (`~/.local/src/pi/packages/durable`)
and 1.3.0 (unchanged in these respects). Source: SL-030 research.

- **No default model.** `resolveAgent` takes the model only from the
  conversation's stored `pi.agent` (`src/harness/agent.ts:274-281`). A
  conversation without one fails `no_model` at generation
  (`src/harness/generation.ts:135-139`; `docs/spec.md:2840`).
  `HarnessSettings` has no model; only `settings.extensions` is a live
  harness-wide default.
- **`harness.root(ctx, {agent, init})` is a no-op when root exists**
  (`src/harness/harness.ts:389-392`). To re-apply settings on every open, call
  `conversation.configure(change)` (malebolge `src/session.ts` does this).
- **`conversationCreated(tx, record)`** sets defaults for *new* conversations
  and forks only; it never runs on reopen (`src/harness/types.ts:620-627`).
- **`ConversationId` has no public parser.** Only `ROOT_CONVERSATION_ID` is
  exported; `idFromNumber` is internal. `harness.conversation(id)` returns
  `undefined` for an unknown id and does not validate it, but `watchEvents`
  throws a plain `Error` for an unknown id. malebolge's runner recovers ids
  by scan (`src/runner/durable-ids.ts` `conversationIdOf`), never by cast.
- There is no public conversation listing or metadata. Enumerate with
  `tx.scanConversations` inside a commit.


## Per-conversation vs harness-wide (verified 2026-10-20 against pi-durable **1.3.0**, malebolge's pin `@earendil-works/pi-durable@1.3.0`)

- **`configure` merges field-wise.** `configure(tx, id, change)` →
  `applyChange(state, change)` sets only the keys present in the `AgentChange`:
  `undefined` leaves a field alone, `null` deletes it (`dist/harness/agent.js:55-58`,
  `:92-122`). So `configure({ model })` cannot clobber a conversation's `cwd`,
  and no read-modify-write is needed to change one field. Each call is its own
  commit (`dist/harness/types.d.ts:592-593`) and emits `agent_changed`.
- **`createConversation({ ownership, agent?, init? })` applies `agent` inside
  the creating commit** — after the creation hook, before `init`
  (`dist/harness/types.d.ts:415-421`). Model and `cwd` for a new conversation are
  therefore atomic: one write, no second `configure`, no window without a model.
  (`harness.root(ctx, {agent})` accepts the same shape but only at creation.)
- **`harness.resume()` is scheduler-wide, not root's.** On open the scheduler
  scans every live task across all conversations, re-pends `running` ones, and
  `resume()` kicks them all (`dist/harness/scheduler.js:133-157`, `:158-162`).
  A store holding N conversations with unfinished turns starts N unattended
  generations, whoever is attached — relevant to any concurrency/cost bound
  (malebolge has none: RFC-002 OQ-3).
