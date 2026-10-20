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

1. **Session:** the session exposes the harness and resolves conversations by
   id. Root remains the default and is still opened at startup.
2. **Protocol:** an optional first message selects a conversation by id or
   creates a new one (optionally with a `cwd`). A connection that does not
   send it is attached to root, so existing clients and stores keep working.
3. **Daemon:** `attach()` resolves the selected conversation; watching,
   input, abort and compact act on it.
4. **Line client:** `malebolge-attach` gains flags to select an existing
   conversation or create a new one.
5. **Prompt section:** the working-directory section renders the
   conversation's own `cwd`.
6. **Reapplying configuration on open** — design decision D-A: today the
   daemon's model and `cwd` are reapplied to root on every open
   (`session.ts:27`). With many conversations, the daemon-wide model must
   still take effect on restart without overwriting a conversation's own
   `cwd`.
7. **Id resolution** — design decision D-B: resolving id text to a
   `ConversationId` needs `runner/durable-ids.ts` `conversationIdOf`, but
   `test/structure.test.ts` forbids root modules from importing `src/runner/`.
   DEC-074 governs this, not RFC-001. Either move it to a named root module
   (`src/durable-ids.ts`, plus `"durable-ids"` in `RUNNER_ROOTS`), or cast
   validated text directly. Creating a `src/lib/` tier would reopen what
   DEC-074 deferred to malebolge IMP-002.
8. **Room fault reporting** — design decision D-C: the room connection's
   fault log, trust flag and reconnect window are per daemon, so faults are
   reported across conversations. Decide whether to accept and document this,
   or change it.
9. **Client-supplied `cwd`** — design decision D-D, found in research: a
   created conversation's `cwd` is where its tools run (both environment
   hooks use `state.cwd`). Decide which values a client may supply. Research
   suggests restricting them to what the running profile can serve (CON-005,
   DEC-078): under the room home for the room profile, under the launch
   directory for the host profile.

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
  stream, and input to one is never seen by another.
- A client that sends no selector behaves exactly as today, against root.
- A new conversation created with a `cwd` runs its tools there and states
  that directory in its prompt.
- Changing the daemon's model takes effect on restart according to D-A, and
  a conversation's `cwd` survives the restart.
- `test/structure.test.ts` passes with id resolution in the shared tier.
- `just check` in malebolge is green; the README and the "one conversation"
  comments are updated.

Risks:

- D-A may have no clean answer if pi-durable has no harness-wide default
  model. Not yet checked.
- The existing tests (`test/daemon.test.ts`, `test/session.test.ts`) are built
  around `root`, so the test fixtures carry much of the change.
- Concurrency across conversations is unbounded once creating them is
  possible. Accepted for a single user; the cap is RFC-002 OQ-3.

## Follow-Ups

- malebolge RFC-002: topics, index, titles, clients, concurrency cap.
- Shared-state hazards in room fault handling (`roomShell` loss counters,
  `DaemonConnection.trustFailure`), depending on D-C.
