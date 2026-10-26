# MCP run identity per conversation, not per connection

## Context

IMP-054. The SATAN MCP (Model Context Protocol) server in `satan-mcp.el`
mints one *interactive run* per client connection. That run is a run-id, a
run dir and an audit bundle, and DEC-5 of the pre-doctrine MCP design is the
rule that each connection gets exactly one. The rule fitted one pi
coding-agent session per connection (the `~/notes/.pi/extensions/satan.ts`
client).

It does not fit the malebolge daemon (`~/dev/malebolge`). That daemon runs
threaded conversations in parallel over one long-lived, reconnecting
connection (`src/satan-tools.ts`), and scheduled async sessions are about to
join them. Today:

```
connection ──1:1── session ── run-id / run dir / audit / tool-ctx / boot-cache
   ▲
   └── malebolge daemon: N conversations, interactive + (soon) scheduled
```

- **One run for everything.** A single interactive run and audit bundle
  spans the daemon's whole lifetime, across every conversation.
- **Attribution is per connection.** Memory writes are attributed to the
  session's run-id: `satan-mcp--tools-call` binds
  `satan-memory-store--current-run-id` to it. Conversations are
  indistinguishable.
- **One boot context.** The `satan_boot_context` cache is per connection, so
  every conversation gets the first one's capsule.
- **DEC-8 keys on the connection.** DEC-8 is the pre-doctrine rule that a
  scheduled run and an interactive session exclude each other. ISS-058
  (2026-10-25) narrowed the scheduler side to in-flight tool calls. The
  reverse side still refuses a *new connection* while a scheduled child is
  live, and nothing yet says what the exclusion should mean once some
  sessions run unattended.

## Scope & Objectives

Target shape (design B, user-agreed 2026-10-26; research X-1, pi's own
session model):

```
malebolge                                   satan-mcp
 conversation A ── connection A ── initialize{experimental.satan} ── session ── run A
 conversation B ── connection B ── initialize{experimental.satan} ── session ── run B
 tool list      ── shared connection (no conversation, no tool calls, no run)
```

1. **Conversation identity on the wire (DEC-121).** `initialize` carries
   `capabilities.experimental.satan = {conversation, kind}`. One connection
   is one conversation; DEC-5 (one run per connection) stands.
2. **Legacy clients.** A client that sends no `satan` capability gets today's
   behaviour, kind `interactive`.
3. **Run lifecycle (DEC-122).** The run is minted on the connection's first
   `tools/call` and finalised by connection close, deferred while calls are
   in flight. A call cut off by close or `notifications/cancelled` is
   recorded as interrupted, never replayed. A mint failure answers with a
   JSON-RPC error. The synthetic final writes status `done`, so MCP bundles
   pass the verifier (pre-existing defect). The client's idle close gives the
   activity window.
4. **Session kind.** `:conversation` and `:kind` are recorded in the
   manifest and bundle; `:mode` stays `interactive`. Groundwork for IMP-053.
5. **DEC-8 retired (DEC-124).** No exclusion in either direction; remove the
   in-flight counter, the broker's `session_blocked` gate and both MCP
   refusals.
6. **Explicit attribution (DEC-123).** The memory-store emitter takes the
   run as an argument. Tool writers and the observer pass their run's `:id`;
   an `@satan` directive passes the consuming tick's run (as today); M-x
   counter-memories pass none (no signal, as in the usual case today).
   `satan-memory-store--current-run-id` goes.
7. **malebolge client (DEC-125).** A pool keyed by (conversation, kind) beside
   the shared tool-list connection, with the lifetime contract in DEC-125;
   any pooled reconnect, and the first connection of each new pool entry,
   triggers the tool-list refresh. Sequenced after the server change.

## Non-Goals

- **IMP-053:** implementing ceilings on unattended turns. This slice only
  makes the kind visible.
- **ISS-050:** auditing the coding-tool calls that never reach SATAN.
- **ISS-057:** attribute feedback into interactive sessions.
- **QUE-001:** authoring SPEC-001's run-lifecycle requirement. SPEC-001 (the
  trust-boundary protocol spec) asks who may start or gate a run. The
  slice's protocol change is reconciled into SPEC-001 at close, through a
  revision. It does not answer QUE-001 in general.
- **Authenticating conversation ids.** Any local client can still claim any
  id. The id is for attribution, not authority (RSK-018, RSK-019).
- **Scheduling async sessions.** Malebolge owns that. This slice only gives
  them an identity.

## Affected surface

- satan: `satan/satan-mcp.el` (initialize, lazy mint, refusals),
  `satan/satan-run.el` (DEC-8 state), `satan/satan-broker.el` (gate, global
  run-id `setq`), `satan/satan-memory-store.el` and every emitter caller
  (`satan-tools-memory.el`, `satan-tools-hippocampus.el`,
  `satan-observer.el`, `satan-intervention.el`, `satan-tools-atsatan.el`),
  `satan/satan-audit.el` (verifier coverage), and their tests. Bundle fields go through the existing
  `satan-audit-open`.
- malebolge: `src/satan-tools.ts`, `src/reconnecting-client.ts`
  (capabilities option), `src/conversation-context.ts`, tests and
  `test/fixtures.ts` (fake server must record initialize params).
- Specs: the SPEC-002 transports row and a SPEC-001 revision at close. (The
  `docs/` files never describe MCP; nothing to revise there.)

## Risks & assumptions

- **A1 verified:** pi-durable passes `api.conversationId` to `execute`
  (research Thread 3).
- **R1, cross-repo ordering.** Satan first. An older server ignores
  experimental capabilities, so the client is safe against either.
- **R2, more run dirs.** One per active conversation window; readers cope
  (research inq-7 disposition).
- **R5, RSK-020.** The room daemon runs from the live tree; the live check
  must name which revision it exercised.

## Open questions

All slice OQs are settled by the design run: OQ-1/OQ-4 by DEC-122, OQ-2 by
the kind disposition (declared, recorded, never trusted), OQ-3 by DEC-124.
OQ-5 (child conversations) is deferred to malebolge IDE-002.

## Verification / closure intent

- ert tests:
  - two connections naming different conversations get distinct run dirs,
    audits, attribution and boot caches, each passing `satan-audit-verify-run`;
  - a connection with no `satan` capability behaves as today, except that no
    run dir exists before its first call;
  - a malformed capability fails `initialize` with -32602; a repeated
    `initialize` with different identity is refused; `satan_boot_context`
    as the first call works; a mint failure answers with a JSON-RPC error;
  - a disconnect or `notifications/cancelled` during a nested wait leaves
    the call recorded as interrupted and the bundle finalised after it, and
    the bundle passes `satan-audit-verify-run`;
  - a broker-ctx memory write nested inside an MCP call attributes to the
    broker run; an `@satan` counter-memory attributes to the consuming
    tick's run; M-x counter-memories emit no `trace_marked`;
  - a broker tool call nested inside an MCP call keeps the broker's
    attribution;
  - a scheduled broker run spawns while an MCP call is in flight, and an MCP
    call proceeds while a broker run is live.
- malebolge tests: each (conversation, kind) uses its own connection with
  the capability; return after idle; overlapping calls; init/expiry races;
  many conversations; a pooled reconnect triggers refresh; the tool-list
  connection makes no calls.
- Live check: two malebolge conversations produce two interactive run dirs,
  and a scheduled tick spawns while they are active. Name the malebolge
  revision exercised (RSK-020).
- Governance: transport cleanup is not ADR-017 §4 evidence (that section
  concerns Emacs being absent). The SPEC-001 revision reconciles REQ-007
  explicitly.
- `just check` passes in both repos; SPEC-001 and SPEC-002 revisions at
  reconcile.

## Summary

Move SATAN's MCP run identity from the connection to the conversation, so
the malebolge daemon's parallel and scheduled conversations each get their
own run, audit and attribution, and settle what DEC-8 should mean afterwards.

## Follow-Ups

- IMP-053 builds its unattended-turn ceilings on the kind marker.
- QUE-001 is the question of SPEC-001's general run-lifecycle invariant.
