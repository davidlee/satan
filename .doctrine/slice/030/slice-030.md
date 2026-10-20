# malebolge daemon: many conversations — thread the conversation through the interactive daemon

## Context

All paths are in `~/dev/malebolge` unless stated.

The interactive daemon `malebolge` serves exactly one conversation: the
pi-durable harness's root conversation. pi-durable itself does everything per
conversation, and `satan-runner` already keeps many conversations in one store
(`src/runner/conversations.ts`). The single-conversation assumption is
malebolge's alone, fixed in a few places:

| Seam | Now |
|---|---|
| `src/session.ts:15-44` | `Session = { harness, root }`; only root is opened, and `root.configure(agent)` runs on every open |
| `src/daemon.ts:46,52,70` | every connection binds to root (`watchEvents(root.id)`, `act(root, …)`) |
| `src/protocol.ts:11-14` | `ClientMessage` (`input`, `abort`, `compact`) names no conversation |
| `src/attach.ts:13-30` | no way to choose or create a conversation |
| `src/cwd.ts` | the working-directory prompt section is fixed text from the daemon's startup directory |

This slice threads the conversation through those seams as a parameter, with
root as the default. That is mechanism, independent of how conversations will
be organized. The policy (topics, an index, titles, Emacs buffers, a nushell
launcher) is deliberated in malebolge's RFC-002
(`~/dev/malebolge/.doctrine/rfc/002`), which stays open and is not decided
here.

Research so far (pi-scout reads of pi-durable 1.3.0 and malebolge, 2026-10-20;
to be consolidated in this slice's research artefact):

- `Conversation.configure` stores `AgentChange` (model, `cwd`, extensions, …)
  per conversation. The `env` hook receives the conversation's `cwd`, and
  section render functions receive `conversationId` and `agent.cwd`.
- There is no public conversation listing and no metadata. `ConversationId`
  is a branded number with no public parser.
- Different conversations run concurrently with no cap. One conversation
  already makes concurrent tool calls over the shared room connection
  (`toolExecution: "parallel"` is the default), and pi-env multiplexes
  requests by id.

## Scope & Objectives

1. **Session:** `session.ts` stays the store opener; root remains the default
   and is still opened at startup. A daemon-only `src/conversations.ts`
   resolves or creates a conversation from an attach request, and watches it, so the transport holds no `Harness` (DEC-109).
2. **Protocol:** an optional first frame `{type:"attach", conversation?,
   new?, cwd?}` selects a conversation by id or creates one; the daemon
   acknowledges with `{type:"attached", conversation}`. Any other first line
   binds root, so clients that send no attach keep working (DEC-108).
3. **Daemon:** `attach()` reads the first line, binds one conversation per
   connection, handles its lines in order; watching, input, abort and compact
   act on it. `serve()` takes an options object (DEC-109).
4. **Line client:** `malebolge-attach` always sends `attach` on connect, gains
   flags to select an existing conversation or create a new one, and prints
   its banner on the acknowledgement.
5. **Prompt section:** the working-directory section renders the
   conversation's own `cwd` (`input.agent.cwd`).
6. **Configuration** (D-A → DEC-104): the daemon's model and `cwd` are
   creation-time defaults, written by `createConversation({agent})`; root is
   still reconfigured on every open, as today; no other conversation is.
7. **Id resolution** (D-B → DEC-105): the wire id is a JSON number, validated
   as a safe positive integer and read with one lookup; unknown and
   task-owned conversations are refused. `durable-ids.ts` does not move;
   `test/structure.test.ts` is unchanged.
8. **Room fault reporting** (D-C → DEC-106): stays per daemon; documented in
   `daemon-env.ts`'s header.
9. **Client-supplied `cwd`** (D-D → DEC-107): an opaque string passed to pi
   unchanged; confinement is the jail's (CON-005). Who may attach: ASM-007.

## Non-Goals

- Topics, a conversation index, titles, archiving and listing UI: malebolge
  RFC-002. Listing, if present at all, returns bare ids.
- Emacs multi-buffer support beyond keeping `malebolge.el` working against
  root.
- A cap on concurrent runs, or cost ceilings for the interactive daemon
  (RFC-002 OQ-3).
- Per-conversation project context. It stays daemon-wide, read once at
  startup (RFC-002 OQ-7).
- Fork as a client verb, and the runner (`satan-runner`).

## Summary

Done when:

- One daemon serves several conversations at once, each with its own event
  stream, and input to one is never seen by another. Verified with
  overlapping conversations: B completes while A is held mid-turn, abort on
  A leaves B running, and each stream and transcript holds only its own
  traffic (faux factories see the transcript, so order need not be scripted).
- A legacy client whose first line is a command behaves as today, against
  root. A client that never sends gets no snapshot (DEC-108).
- A new conversation created with a `cwd` runs its tools there and states
  that directory in its prompt.
- A new conversation carries the daemon's model; a restart reconfigures root
  only, and never changes another conversation's model or `cwd` (DEC-104).
- `test/structure.test.ts` passes unchanged.
- `just check` in malebolge is green; the README and the "one conversation"
  comments are updated.

Risks:

- After a model change, non-root conversations keep their old model; no
  client verb changes it yet (RFC-002 OQ-2).
- At startup `harness.resume()` restarts every conversation's unfinished
  turn, unattended and uncapped (RFC-002 OQ-3).
- The faux provider's response queue is shared by all conversations;
  overlapping tests use transcript-aware factories or barriers, not
  scripted order.
- Version skew: a new `malebolge-attach` against an old running daemon fails with a restart hint until the daemon is restarted.
- The existing tests (`test/daemon.test.ts`, `test/session.test.ts`) are built
  around `root`, so the test fixtures carry much of the change.
- Concurrency across conversations is unbounded once creating them is
  possible. Accepted for a single user; the cap is RFC-002 OQ-3.

## Follow-Ups

- malebolge RFC-002: topics, index, titles, clients, concurrency cap.
- Shared-state hazards in room fault handling (`roomShell` loss counters,
  `DaemonConnection.trustFailure`): accepted by DEC-106, revisit if they bite.
