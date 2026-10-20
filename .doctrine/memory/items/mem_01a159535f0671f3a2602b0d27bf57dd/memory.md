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
