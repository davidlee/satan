<!-- doctrine:section sec-1 -->
# Overview and module map

All paths are in `~/dev/malebolge`. The interactive daemon's one-conversation assumption becomes a per-connection binding: each bound connection is bound to exactly one conversation of the profile's store, root when its first line names none; a connection that sends nothing is never bound. Policy (topics, index, titles, listing) stays in malebolge RFC-002.

```
 malebolge-attach ──attach frame──▶ daemon.ts ──AttachTarget──▶ conversations.ts ──▶ pi Harness
 (attach.ts, flags)  ◀──attached── (transport,      (resolve or create,      (session.ts opens
                     ◀──events───   one binding      daemon defaults)          store + root)
                                    per connection)
                                         ▲
                       daemon-start.ts composes: session, conversations, beforeInput
```

| module | owns after SL-030 | change |
|---|---|---|
| `src/protocol.ts` | wire frames | gains the `attach` frame and `AttachTarget`; `attached` reply |
| `src/daemon.ts` | transport: connection lifecycle, one binding, ordered lines | reads the first line before binding; `serve()` takes options |
| `src/conversations.ts` (new, daemon-only) | attach target → `Conversation`, and its event stream | resolve (DEC-105) or create with defaults (DEC-104, DEC-107); `watch` (the transport's only route to the `Harness`; `daemon-start.ts` keeps the `Session` and closes it last) |
| `src/session.ts` | the store and root | unchanged behaviour; header and option comment say "root" |
| `src/daemon-start.ts` | composition | builds `conversations` from the daemon's `AgentChange`; new `serve` call |
| `src/cwd.ts`, `src/daemon-extensions.ts` | the working-directory section | renders `input.agent.cwd`; `DaemonParts.cwd` removed |
| `src/attach.ts`, `src/attach-main.ts`, `src/render.ts` | line client | flags, attach on connect, hold lines until `attached`, banner from the reply |

## Invariants (stated in module headers)

1. At most one conversation per connection, bound by its first line: the one an `attach` frame names, root for any other line. A connection that sends nothing is never bound (DEC-108).
2. The daemon's model and `cwd` are creation-time defaults for non-root conversations; root is reconfigured with them on every open, as today (DEC-104).
3. A non-root conversation's stored agent settings are never rewritten by the daemon.
4. A conversation id is meaningful only inside this profile's store and socket (DEC-078, DEC-087).
5. `cwd` is an opaque string handed to pi; confinement is the jail's (DEC-107, CON-005).

Nothing in `src/room/` or `src/runner/` changes; `test/structure.test.ts` is unchanged (DEC-105). No ADR-017 §3 authority item is created or moved; the socket remains the attach authority (ASM-007).

<!-- doctrine:section sec-2 -->
# Wire protocol

One JSON object per line, as today. Client → daemon gains one frame; daemon → client gains one reply.

## The attach frame (DEC-108, amended)

Valid only as a connection's first line.

| first frame | `AttachTarget` | meaning |
|---|---|---|
| `{type:"attach"}` | `{kind:"root"}` | root |
| `{type:"attach", conversation: N}` | `{kind:"existing", id: N}` | conversation N (DEC-105) |
| `{type:"attach", new: true}` | `{kind:"new"}` | create, daemon's default `cwd` |
| `{type:"attach", new: true, cwd: S}` | `{kind:"new", cwd: S}` | create, `cwd` S (DEC-107) |

`protocol.ts` exports `parseConnectionMessage(line): AttachMessage | ClientMessage`, where `AttachMessage = { type: "attach"; target: AttachTarget }`; it delegates every other type to `parseClientMessage`, whose type and contract (`test/protocol.test.ts`) are unchanged. The daemon narrows on `type`, so `act()`'s switch stays exhaustive over `ClientMessage`. A refused `attach` throws `AttachRefused` (exported from `protocol.ts`), distinguishable from other parse errors; on a bound connection the daemon answers both a parsed `AttachMessage` and an `AttachRefused` with `already attached`, and any other failure with its own message. Nothing downstream sees the raw fields. Refused before anything is created:

- `conversation` together with `new`; `cwd` without `new`; `new` with any value but `true`;
- `conversation` not a safe positive integer; `cwd` not a string;
- any key other than `type`, `conversation`, `new`, `cwd` — strict so a future RFC-002 field (`topic`) sent to this daemon fails rather than silently attaching root.

The existing three messages keep their lenient parsing. `cwd` is not trimmed, resolved or checked; the empty string is passed through like any other (pi stores it; tools fail at use).

## Replies

- `{type:"attached", conversation: N}` — sent once, after a successful `attach`, before the snapshot. N is the id pi returned (for a created conversation, the new id).
- The snapshot and events, as today.
- `ErrorMessage` (`{type:"error", message}`), as today, for a line the daemon could not act on.

A connection whose first line is not `attach` receives no `attached` reply. A legacy client receives today's stream once it sends its first line; until then it receives nothing, where today the snapshot arrived at connect. No in-repo client is affected: `malebolge-attach` always sends `attach`, and `probeUnix` (`unix-socket.ts:69-72`) connects and leaves without sending, so it is simply never bound.

## Errors

| case | reply | connection |
|---|---|---|
| malformed or refused `attach` as the first line | `ErrorMessage` | closed |
| unknown id, task-owned conversation | `ErrorMessage` | closed |
| any line of type `attach` after the connection is bound, well-formed or not (the bound check precedes shape validation) | `ErrorMessage` (`already attached to conversation N`) | open; binding unchanged |
| a first line that is not JSON, or not an `attach` and not a valid command | root is bound, then `ErrorMessage` | open (today's behaviour) |
| any other bad line | `ErrorMessage` | open (today's behaviour) |

## Ids

The id is a JSON number, as pi types `ConversationId`. It names a conversation only within this profile's store; a client that persists one (buffer name, launcher argument, log) must persist the profile with it. The protocol header says so. `profile` in the reply is a possible later additive field, not part of this slice.

<!-- doctrine:section sec-3 -->
# Connection lifecycle (daemon.ts)

```
 connect ─▶ close handler + one line splitter installed ─▶ lines queued
                │
                ▼  (serial chain: each line waits for the previous one)
         first line ─┬─ attach ──▶ await conversations ─▶ resolve/create ─┬─ ok ─▶ bind(conv, ack)
                     │                                                    └─ fail ─▶ error, end, drop rest
                     └─ other ───▶ await conversations ─▶ bind(root) ─▶ act(line)
         later lines ─▶ act on the bound conversation (attach → error, stays bound)

 each line's turn starts after `conversations` is ready: socket destroyed? ─▶ drop it (and every later line)
 bind (part of the first line's turn): open ─▶ conversations.watch(conv) ─▶ destroyed? stop stream, drop queue
                                       ─▶ write attached (if ack) ─▶ snapshot ─▶ start stream
```

## Rules

- **One splitter, one queue.** The `data` handler and line splitter are installed at connect, before the session is ready, and feed a single per-connection promise chain. The first frame and trailing commands that arrive in the same chunk, and a partial next frame, flow through the same splitter, so nothing is lost or reordered. Lines that arrive while selection or session readiness (the `conversations` promise) is pending wait in the chain.
- **Unbounded queue.** The queue and `lineSplitter` (`ndjson.ts:79-81`) are unbounded, as the splitter is today; lines written before the session is ready now wait in the process rather than in the socket buffer. Accepted within ASM-007's trust boundary: the socket's only clients are the operator's.
- **Strictly ordered.** Every line, including `abort`, waits for the previous line's handling. This is deliberate beyond the attach frame: an `abort` typed after an `input` must abort that input's run, and today's unordered handling can run the abort before the input is admitted. Costs, accepted:
  - `submit` returns on admission, but `beforeInput` precedes it. `coalesce` makes a caller that arrives during a read share the *next* read (`coalesce.ts:34-50`, DEC-086), so one input can wait up to two refresh deadlines (2 s each by default), serially for each queued input. Under a wedged `satan-mcp`, an `abort` queued behind k inputs waits up to 2k deadlines.
  - `abort` resolves only once the conversation's scope is idle (pi `Conversation.abort`), so a line after an `abort` waits for the aborted run to unwind.
- **Failed attach** writes one `ErrorMessage`, ends the socket, and marks the connection closed; queued lines are dropped, never acted on root.
- **No line after departure.** A line whose turn starts after its socket is destroyed is dropped, with every line behind it. A turn starts once `conversations` is ready and the previous line is done; the check is the turn's first step. Today a connection that has gone before the session opens is dropped with its lines (`daemon.ts:53-58` returns before the `data` handler is installed), while a still-open one has its lines acted on once the handler installs (`:66-75`); this keeps both, so an input followed by an immediate disconnect never starts an unwatched run, and an `attach` whose socket has gone before its turn creates nothing. Work already begun is not cancelled: an `attach` whose turn has started completes its resolution or create (the DEC-108 gap), acquires its stream and stops it at once; an `act` in flight finishes (today's behaviour). `serve`'s `close()` destroys every socket synchronously (`unix-socket.ts:131-141`), so `destroyed` is the only state the check reads; no closing flag is added.
- **Disconnect during resolution.** The close handler stops any stream already acquired; a stream acquired after the socket was destroyed is stopped immediately (today's check, kept, now inside bind). A create that commits after disconnect is the accepted create/acknowledge gap (DEC-108): the empty ownerless conversation remains.
- **Passive clients.** A connection that never sends a line is never bound and receives nothing. Documented in the protocol header (sec-2 lists the in-repo cases).
- **The input draft** passed to `submit` is built from the validated fields (`content`, `requestId`), never the parsed wire object (research X-5).

## serve()

```ts
serve({ socketPath, conversations, beforeInput }: ServeOptions): Promise<Daemon>
```

`conversations: Promise<Conversations>` replaces `session: Promise<Session>`. The daemon needs root, the resolver and each conversation's event stream, all three from `Conversations` (sec-4); it holds no `Harness`. `beforeInput` stays one daemon-wide coalesced gate (DEC-086); the header notes that it is shared by every conversation, so it is not mistaken for per-connection state.

<!-- doctrine:section sec-4 -->
# Conversations and configuration

## src/conversations.ts (DEC-109)

Daemon-only, root tier; imports pi-durable, `context.ts`, `protocol.ts` (the `AttachTarget` type), `session.ts` (the `Session` type).

```ts
export interface Conversations {
  root: Conversation;
  /** The conversation `target` names, or created; rejects with a client-facing message. */
  open(target: AttachTarget): Promise<Conversation>;
  /** `watchEvents(session.harness, conversation.id, context)`. */
  watch(conversation: Conversation): Promise<AgentEventStream>;
}
/** The daemon's creation defaults; `cwd` is required so the fallback below is always a string. */
export type ConversationDefaults = AgentChange & { cwd: string };
export function conversations(session: Session, defaults: ConversationDefaults): Conversations;
```

| target | behaviour |
|---|---|
| `root` | `session.root` |
| `existing N` | one read, `harness.commit((tx) => tx.conversation(N), context)`, `N` narrowed by `isConversationKey`. `undefined` → `no conversation N`. `record.owner !== undefined` → `conversation N belongs to a task`. Otherwise `harness.conversation(record.id, context)`; its `undefined` (unreachable in 1.3.0, which retires no conversation) is also `no conversation N`. Only pi's `record.id` is used after the read. |
| `new` | `harness.createConversation({ ownership: { kind: "ownerless" }, agent: { ...defaults, cwd: target.cwd ?? defaults.cwd } }, context)`. The explicit fallback matters: pi skips an `undefined` key, so spreading an absent `cwd` would store none. Model and `cwd` land in the creating commit; there is no window without a model. |

`isConversationKey(n: number): n is ConversationId` (`Number.isSafeInteger(n) && n > 0`) is the safe-positive-integer validation sec-2 requires, written as a type predicate: malebolge's lint forbids type assertions (`eslint.config.js`, `consistent-type-assertions: never`), and pi's `idFromNumber` is not exported. `protocol.ts` refuses the same ids at parse with its own check; the predicate exists to narrow inside `conversations.ts`, since the dependency runs conversations → protocol, never the reverse. The narrowed number is a lookup key only; the branded value the daemon keeps is pi's `record.id` (amended 2026-10-21, plan review RV-052). Header sentence (research F-15): this answers "which conversation does a wire reference name"; `runner/durable-ids.ts` answers "recover the branded id from the runner's TEXT column". Same file name as `src/runner/conversations.ts` (precedent: `project-context.ts`); each header names its program.

Ownership is immutable in pi's record, so the attach-time refusal of task-owned conversations is stable.

`watch` sits here, not in `daemon.ts`, because pi's only event-stream entry point is harness-first (`watchEvents(harness, id, context)`; `Conversation` has no stream accessor). Owning it keeps the `Harness` out of the transport and puts "the conversation exists before you watch it" in the module that resolved it.

## Configuration (DEC-104)

- `session.ts` keeps `root.configure(options.agent)` on every open. Its option comment becomes "applied to root on every open"; the module header drops "its root conversation" as the session's content in favour of "the store, and root opened as the default conversation".
- `daemon-start.ts` builds one `ConversationDefaults` `{ model, cwd: environment.cwd }` (assignable to `openSession`'s `AgentChange`) and passes it to both `openSession` (root) and `conversations` (defaults).
- No conversation other than root is configured on open. `test/session.test.ts:106-121` keeps its meaning.
- `harness.resume()` stays in `openSession`, before any client can attach; it resumes every conversation's unfinished work (risk, sec-7).

<!-- doctrine:section sec-5 -->
# Prompt section, environment and room faults

## Working-directory section

`cwd.ts` renders from the conversation, not from construction:

```ts
export const cwdExtension: Extension = defineExtension({
  name: "cwd",
  sections: [section("cwd", ({ agent }) =>
    agent.cwd === undefined ? undefined : `Current working directory: ${agent.cwd}`, { tag: false })],
});
```

`DaemonParts.cwd` is removed from `daemon-extensions.ts`. The list gains one comment stating each section's scope — persona, project context and skills are per profile; `cwd` is per conversation (research F-10) — so the next promotion (project context, RFC-002 OQ-7) starts from a named boundary. Root's `cwd` is always set (configured on open), so root's prompt is unchanged.

Accepted inconsistency (research X-6, DEC-080): a conversation created with another `cwd` states that directory and runs its tools there, while its project context was read once from the daemon's directory. The section comment carries the sentence.

## Environment

Unchanged. pi passes the conversation's `cwd` to the `env` hook (`EnvTarget.cwd`); `hostEnv` and `roomEnv` already use `state.cwd ?? <profile default>` (`daemon-env.ts:114,136`). The environment id `pi-env:daemon-room` stays the same for every conversation, so pi-durable keeps serializing file writes by that id and path (research X-4).

## Room faults (DEC-106)

No code change. The `DaemonConnection`, its trust latch and the `faultLog` observer are built once per daemon, below any conversation. `daemon-env.ts`'s header gains: faults and trust belong to the one room connection every conversation shares; a fault seen by one conversation's tool call is the daemon's fault, logged once.

<!-- doctrine:section sec-6 -->
# Line client

## Flags (attach.ts, called from attach-main.ts)

`attach.ts` exports a pure `attachTargetOf(args: string[]): AttachTarget` over `node:util` `parseArgs`, strict, which throws a usage error for a refused combination; `attach-main.ts` calls it, prints the usage line and exits 2 on that error. The parse lives in `attach.ts` so it is tested in-process: `attach-main.ts` runs at import and is outside coverage (amended 2026-10-21, RV-052).

| flags | frame sent |
|---|---|
| none | `{type:"attach"}` |
| `--conversation N` | `{type:"attach", conversation: N}` |
| `--new` | `{type:"attach", new: true}` |
| `--new --cwd S` | `{type:"attach", new: true, cwd: S}` |

Refused locally with a usage line and exit 2, mirroring the daemon's table: `--conversation` with `--new`; `--cwd` without `--new`; `--conversation` not a positive integer; any unknown flag or positional. The client does not interpret `S`.

## attach.ts

- `attach(socketPath, input, output, { target, wait })`: sends the frame first, on connect.
- `[connected]` at connect replaces `[attached]`, which asserted something nobody had confirmed (research F-11); the `attached` reply renders as `[attached to conversation N]`. Waiting on a slow daemon is therefore visible.
- Typed lines are held until `attached` arrives and then sent in order; an `ErrorMessage`, or a close by the daemon, before it prints the error and detaches, discarding held lines (DEC-108 create/acknowledge gap).
- Exit status: `attach()` rejects when the daemon ends the connection before `attached`, with an error whose `code` is `"NOT_ATTACHED"` (a client-side code, unrelated to the daemon's `AttachRefused` parse error). `attach-main.ts` already exits 1 without a stack trace for any error carrying a `code` (`attach-main.ts:10-15`, `codeOf`), after `attach` has printed why; so a refused attach is one error line and exit 1, and a normal detach still exits 0.
- **Version skew.** The daemon is a long-lived user unit and `malebolge-start` does not restart an active one, so after an upgrade a new client can meet an old daemon. That daemon answers `unknown message type "attach"`; the client prints `[the daemon predates attach: restart it (malebolge-stop, then malebolge-start)]` and exits 1. The README's upgrade note says to restart the daemon.
- Events that arrive before `attached` are rendered as they arrive; only typed lines are held. (An old daemon writes its snapshot at connect, so the skew case prints the snapshot, then the hint.)
- `/quit` or end of input while waiting ends the connection and resolves normally (exit 0): the user chose to leave, nothing was refused.

## render.ts

`Printable` gains `AttachedMessage` (`{type:"attached", conversation: number}`, exported from `protocol.ts`); the handler map makes the missing handler a compile error. `toPrintable` still checks only the discriminant, so an untyped future event type remains a runtime error — unchanged, noted in sec-7.

## Emacs

`malebolge.el` runs `malebolge-attach` with no flags under comint, so it sends `{type:"attach"}` and stays on root. The banner text changes; nothing in `malebolge.el` matches it (checked: no `attached` string in `emacs/`).

<!-- doctrine:section sec-7 -->
# Code impact, verification, risks and follow-through

## Code impact (design targets)

`src/protocol.ts`, `src/daemon.ts`, `src/conversations.ts` (new), `src/session.ts` (comments), `src/daemon-start.ts`, `src/cwd.ts`, `src/daemon-extensions.ts`, `src/daemon-env.ts` (header), `src/attach.ts`, `src/attach-main.ts`, `src/render.ts`, `README.md`, `docs/internals.md`. Tests under `test/` carry the change. Fixture changes: `test/harness-fixture.ts` (`systemPromptSections(test, conversation)`); `test/fixtures.ts` (`LineClient` gains `closed(): Promise<void>` and `write(raw: string): Promise<void>`, resolving on the socket's write callback, for one-chunk and split-frame input and for a frame that must reach the daemon before a disconnect); the `start` helper (options object, a `Conversations` with a `cwd` default), the `attach()` helper and raw `lineClient` uses in `test/daemon.test.ts`; in `test/attach.test.ts`, the `serve()` calls, the positional `attach(path, input, output, wait)` calls (`:42`, `:148`) and the banner sites — four `until("[attached]\n")` waits (`:96`, `:118`, `:155`, `:166`), whose text becomes `[connected]`, and two exact-output assertions (`:121`, `:131`), which keep `toBe` with the `[connected]` and `[attached to conversation N]` lines; `test/daemon-sections.test.ts`'s `cwdExtension(…)` and `daemonExtensions({cwd})` sites. Two passive-client tests are replaced, not deleted: `test/daemon.test.ts:174-183` (snapshot once the session resolves) by V-13, and `:185-196` (watch stopped when a client leaves before the session resolves) by V-11 and V-15: under DEC-108 a passive connection is never watched, so the property becomes "a departed connection leaves no live watch" for the two cases an `attach` can be in.

Docs, each verified by grep at design time:

- `README.md:35-36` ("all in the same conversation"), `:54` ("one durable conversation"), `:70`, `:121-122`: reworded to root by default, many possible (added 2026-10-21, RV-052).
- `README.md:17-19`: "one ongoing conversation" and "a new client sees the conversation so far" become many conversations, root by default, a client seeing its conversation once attached; plus the upgrade note (restart the daemon).
- `docs/internals.md:80-88` (§Protocol, the protocol reference): gains `attach`/`attached`, the error table's close rule and the passive-connection rule.
- `docs/internals.md:116-119`: "cwd … are constants" becomes per conversation.
- Module headers carry the five invariants of sec-1, saying "non-root" wherever DEC-104 excepts root.

## Verification

| id | behaviour | test site |
|---|---|---|
| V-1 | each row of the attach table resolves as stated; every refused shape (sec-2) errors, creates nothing, and closes (observed by `LineClient.closed()`) | `test/protocol.test.ts`, `test/daemon.test.ts` |
| V-2 | a first line that is a command binds root and is acted on; no `attached` is sent | `test/daemon.test.ts` |
| V-3 | `attached` precedes the snapshot; its id is the created/selected conversation's | `test/daemon.test.ts` |
| V-4 | **overlap:** A held mid-turn (faux factory awaiting a barrier); B attaches, submits and completes; A then completes. Each stream and transcript holds only its own input and output. Abort on A while B runs leaves B's run intact. Reattaching to A by id streams A only | `test/daemon.test.ts` |
| V-5 | `attach` and `input` in one `write`, and one frame split across two `write`s, are both handled in order | `test/daemon.test.ts` |
| V-6 | a second `attach`, well-formed and malformed, errors with `already attached`, a non-attach garbage line still gets its own error, and the binding is unchanged | `test/daemon.test.ts` |
| V-7 | unknown id, task-owned id refused | `test/conversations.test.ts` |
| V-8 | a created conversation stores the daemon's model and its own `cwd` (or the default); reopening the session reconfigures root and leaves the created conversation unchanged | `test/conversations.test.ts`, `test/session.test.ts` |
| V-9 | a created conversation's prompt states its own `cwd`, read with `systemPromptSections(test, created)` (not root, whose prompt is unchanged) | `test/daemon-sections.test.ts` |
| V-10 | client flags: each valid combination sends its frame; each refused one exits 2 without connecting; typed lines are held until `attached`; a refused attach rejects with `NOT_ATTACHED` (exit 1, one error line, no stack trace); `/quit` before `attached` exits 0; an old daemon's `unknown message type "attach"` prints the restart hint | `test/attach.test.ts` |
| V-11 | an `attach` (root, and `new`) sent, then a disconnect, before the session is ready: once it is, no stream is acquired and no conversation is created (with V-15, supersedes `:185-196`) | `test/daemon.test.ts` |
| V-12 | `test/structure.test.ts` passes unchanged; `just check` green | suite |
| V-13 | while the session is not ready a connection stays silent; its `attach` and `input`, sent in one `write`, are handled in order once it is (supersedes `:174-183`) | `test/daemon.test.ts` |
| V-14 | an `input` written then followed at once by a disconnect, before the session is ready, is never submitted (no submission on root) | `test/daemon.test.ts` |
| V-15 | an `attach` (root, and `new`) whose turn has started, with the socket destroyed while `open`/`watch` is pending (barrier on the `watchEvents` spy): `watched.streams` holds exactly one stream and its `closed` resolves stopped; for `new`, a `scanConversations` read finds the created ownerless conversation (the accepted DEC-108 strand) | `test/daemon.test.ts` |

Overlap tests drive the faux provider with transcript-aware factories or barriers (pi-ai 1.3.0 `faux.js:349-351`), never by scripted response order. Ordinary single-conversation tests may stay scripted.

## Risks

- **Startup resume fan-out:** `harness.resume()` restarts every conversation's unfinished turn, unattended and uncapped (RFC-002 OQ-3; REQ-004/REQ-010's daemon half remains deferred).
- **Stale models:** after a `MALEBOLGE_MODEL` change, non-root conversations keep their old model; no client verb changes it (RFC-002 OQ-2).
- **Unbounded concurrency** once creation is possible: accepted for one user (RFC-002 OQ-3).
- **Stranded conversations:** the create/acknowledge gap can leave empty ownerless conversations (DEC-108); bare ids are discoverable.
- **Abort behind `beforeInput`:** ordered lines let an abort wait up to two refresh deadlines per queued input, and a line after an abort waits for the run to unwind (sec-3).
- **Version skew:** a new client against an old running daemon fails with a restart hint until the daemon is restarted (sec-6).
- **Renderer exhaustiveness:** typed frames are compile-checked; untyped event types are still a runtime error.

## Governance follow-through (inq-7)

- DEC-074: no amendment — `durable-ids.ts` does not move.
- malebolge RFC-002: its "where the assumption lives" table and wire sketch are updated to the shipped `attach` frame at reconcile.
- ISS-053 (SPEC-002 transport row): note that the interactive socket now carries a creating verb.
- ADR-017 §3 ledger: confirmed untouched at audit.

