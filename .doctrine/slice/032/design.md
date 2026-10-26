<!-- doctrine:section sec-1 -->
## Shape

Design B (DEC-121, DEC-122, DEC-125): one MCP connection per active
(conversation, kind). DEC-5 — one run per connection — stands; what changes
is when the run is minted, what it records, and how it ends.

```
malebolge daemon                                  satan-mcp (Emacs)
 tool-list client ── conn 0 ── initialize{}  ───── session 0 (legacy identity, no run: never calls)
 (A, interactive) ── conn 1 ── initialize{satan:{conversation:"7",kind:"interactive"}}
                                                ── session 1 ──first tools/call──▶ run 1
 (B, interactive) ── conn 2 ── initialize{satan:{conversation:"9",kind:"interactive"}}
                                                ── session 2 ──first tools/call──▶ run 2
     idle close (no call in flight for satanIdleMs) ──▶ sentinel ──▶ finalise run (status done)
```

- A run is one activity window of one conversation of one kind.
- Runs of one conversation are linked by `:conversation` in their manifests.
- A client that names nothing (the pi coding-agent extension) gets today's
  behaviour, except that its run dir appears on the first call, not on
  connect.

<!-- doctrine:section sec-10 -->
## Invariants

Stated in the `satan-mcp.el` header:

- **I1.** A session's identity is fixed once `initialize` succeeds or its
  run is minted, whichever comes first.
- **I2.** A session has at most one run. Every request with an id that
  arrives while its session is `open` gets exactly one response, unless the
  client cancelled it or the transport closed first.
- **I3.** A run is finalised exactly once, and only when no call is in
  flight on its session.
- **I4.** Every finalised MCP bundle passes `satan-audit-verify-run`.
- **I5.** Memory-write attribution comes from an explicit argument, never
  ambient state.

<!-- doctrine:section sec-2 -->
## Wire (DEC-121)

`initialize` params:

```json
{"protocolVersion": "...", "clientInfo": {...},
 "capabilities": {"experimental": {"satan": {"conversation": "7", "kind": "interactive"}}}}
```

| field | rule |
|---|---|
| `satan` absent | legacy identity: conversation nil, kind `interactive` |
| `conversation` | string, 1–128 chars, no control characters; opaque to SATAN |
| `kind` | `"interactive"` or `"scheduled"`; absent → `interactive` |
| anything else malformed (`satan` not an object, wrong types, unknown kind) | error -32602 `invalid params`; the session stays uninitialised |

Repeated `initialize`:

- the same identity → answered as normal (idempotent);
- a different identity → -32602;
- after a run is minted → -32600 `invalid request` (I1).

Parsing lives in one pure function, `satan-mcp--parse-identity`
(params → `(:conversation C :kind K)` or `(error . MSG)`). The server's
`initialize` result does not change; the server advertises nothing new.

Kind and conversation are descriptive claims. Nothing grants scope, budget
or supervision status from them (RSK-018, RSK-019).

<!-- doctrine:section sec-3 -->
## Session and run lifecycle (DEC-122)

`satan-mcp-session` stays one per connection, minted at accept. Changed
slots:

| slot | meaning |
|---|---|
| `identity` | `(:conversation C :kind K)`; legacy identity until `initialize` sets it |
| `run-id`, `run-dir`, `audit`, `tool-ctx`, `prepare` | nil until the first `tools/call` |
| `in-flight` | list of the ids of `tools/call` requests on this session not yet settled; its length is the count (below) |
| `cancelled` | the in-flight ids the client cancelled |
| `state` | `open` → `closing` → `closed` |
| `bufs` | dropped; the line buffer becomes a process property (it is connection-scoped) |

```
accept ─▶ open(no run) ─initialize─▶ open(identity) ─tools/call─▶ open(run)
   │                                                        │
   └──────────── sentinel ───────────┬──────────────────────┘
                                     ▼
                     closing ──(in-flight = 0)──▶ finalise ──▶ closed
```

- **Mint.** `satan-mcp--ensure-run` runs at the top of `tools/call`. It uses
  the existing mint body (`satan-run-new-ctx`, `satan-run-mint-id`,
  `satan-audit-open`; DEC-001 is unchanged) and records the identity in the
  manifest and bundle. It publishes the run slots only after
  `satan-audit-open` returns. The mint is failure-atomic: on error, it
  deletes the run dir if one was created (`satan-audit-open` writes its
  files one by one, `satan-audit.el:61-67`), then answers that request with
  -32603. The next call retries, so a failed mint leaves no dir and a retry
  leaves exactly one. The DEC-8 refusal at the head of the mint goes
  (DEC-124).
- **Every request is answered.** `satan-mcp--handle-message` wraps request
  handling: an uncaught error in a request with an id answers -32603. Today
  the filter only logs it (`satan-mcp.el:375-385`), so a client waits for its
  timeout.
- **Admission.** `satan-mcp--handle-message` checks the session's state for
  each message. A `closing` or `closed` session dispatches nothing and
  answers nothing, because its transport is gone. This matters because the
  filter decodes every complete line of a chunk before dispatching any
  (`satan-mcp.el:365-372`): if the connection closes during a nested wait in
  the first call, the later lines are dropped (and logged), not run against
  a finalised run.
- **Settle.** Every audited call is settled before it releases `in-flight`.
  `--tools-call` records the `tool-call`, then dispatches inside
  `unwind-protect`:
  - normal return → the `tool-result` as today;
  - non-local exit (an error that escapes `satan-tool-dispatch`'s guard;
    `quit`, which that guard does not catch, `satan-tools.el:191-199`; or
    any other exit, such as a `throw` from a `while-no-input` in an
    enclosing wait) → a `tool-result`
    `{:id <call id> :ok false :error "interrupted: <reason>"}` (the verifier
    pairs on `:id`, `satan-audit.el:647-648`), then `call-interrupted`
    (`:reason "error"`, `"quit"` or `"exit"`). An error then answers -32603
    if the session is `open` and its transport live.
  - `quit`, and any non-error exit (DEC-126), closes the session's
    transport (`delete-process`) after settling and releasing, and before a
    quit is re-signalled. The caller sees a disconnect, not a
    silent timeout. A quit inside a nested filter
    (`satan-mcp--filter-depth` > 1) is deferred to `quit-flag`
    (`satan-mcp--resignal-quit`): the C process reader between the filters
    cannot carry a Lisp quit ("error in process filter: Quit";
    mem.fact.satan.quit-in-process-filter), so the enclosing wait raises it
    and the enclosing call settles on it as a quit. Decoded sibling lines meet a `closing` session and are
    dropped (Admission). Both cases fall under I2's transport-closed
    exception. The client reconnects on its next call, and that call mints
    a new run.

  Delivery and the cancellation and disconnect records below happen inside
  the settle, so `in-flight` drops only after the call's last audit write.
  Today the counter is released before the result is recorded
  (`satan-mcp.el:301-307`); that order goes.
- **Cancellation.** `notifications/cancelled {requestId}` for an id in
  flight adds it to `cancelled`. Dispatch is not interrupted: Emacs dispatch
  is synchronous, and a tool may already have acted. When it returns, its
  result is audited as normal, followed by a `call-interrupted` transcript
  record (`:reason "cancelled"`), and no response is sent. Unknown ids are
  ignored.
- **Close.** The sentinel sets `closing`. If `in-flight` is 0, it finalises
  now. Otherwise the `tools/call` unwind path finalises when the count
  reaches 0. A call whose response cannot be delivered (the process is dead)
  gets a `call-interrupted` record (`:reason "disconnected"`). The call's
  result is never replayed. `satan-mcp-stop` goes through the same path.
  `closed` makes a second sentinel event a no-op (I3).
- **Finalise.** As today, but the status is `done` (`satan-audit.el:686`
  accepts no `completed`; pre-existing), and the summary names the identity:
  `"interactive conversation 7"` or `"interactive session"`. A session with
  no run finalises nothing.
- The boot-context cache stays a session slot, which is now one per
  conversation window. `satan-mcp--current-session` stays as the route for
  `satan_boot_context`. It is let-bound per dispatch, and a nested dispatch
  rebinds it, so it is correct under nesting.

The verifier has no event registry and already ignores transcript events
other than calls and results, so `call-interrupted` needs no new
predicate: a `calls-match-results` docstring line documents it, and a test
pins both halves. `calls-match-results` still requires a
`tool-result` for each `tool-call`; the settle rule writes one on every exit
path, so the check still catches a call that was never settled.

<!-- doctrine:section sec-4 -->
## Attribution (DEC-123)

Today `satan-memory-store--emit-trace-marked` emits the hippocampus
`trace_marked` attribute signal with `satan-memory-store--current-run-id`.
The MCP server `let`-binds that variable; the broker `setq`s it at spawn and
clears it at finalise (`satan-broker.el:262,757,953`). `satan-patch-rpc.el:137`
serves other processes while it waits, so a nested dispatch reads whatever
binding encloses it.

Change:

- `satan-memory-store-mark` gains `&key run-id` and passes it to
  `--emit-trace-marked`, which emits only when it is non-nil and attribute
  updates are enabled (today's guard).
- The variable `satan-memory-store--current-run-id` is deleted, along with
  its `defvar` copies in `satan-mcp.el:23` and `satan-broker.el:45`.

Callers (complete; `grep -n satan-memory-store-mark satan/*.el`):

| caller | passes `:run-id` | behaviour vs today |
|---|---|---|
| `satan-tools-memory.el:145` (`memory_mark` tool) | `(plist-get ctx :id)` | same run, now immune to nesting |
| `satan-tools-hippocampus.el:74` (hippocampus write) | `(plist-get tool-ctx :id)` | same |
| `satan-observer.el:129` `--persist-positive` (via `:memory-mark-fn`) | the broker run's `(plist-get tool-ctx :id)`, threaded from `satan-observer-process`'s ctx (`satan-broker.el:819`) | same: the observer runs after the spawn `setq` |
| `satan-intervention.el:828` counter-memory, `@satan` directive (`notes_at_satan_intervention_done`, a broker-tick tool, `satan-tick.el:121`) | the consuming tick's run, `(plist-get ctx :id)` (`satan-tools-atsatan.el:559`) | same as today: the tick that processed the directive made the write |
| `satan-intervention.el:828` counter-memory, M-x mark (`satan-intervention-mark.el`) | nil | same as the usual case today (no run bound, so no signal); fixes mis-attribution to a live broker run |

Both counter-memory paths go through
`satan-intervention-write-manual-outcome`, which gains `&key run-id` and
forwards it to its mark function. Neither passes the intervention's
historical run. That run's audit receives the outcome event
(`satan-run-manual-tool-ctx`), but the counter-memory is not its activity,
and emitting `trace_marked` against a finished run would put a fresh signal
on it.

`:id` is the existing tool-ctx field (`satan-run.el:345`); no `:run-id`
slot is added.

<!-- doctrine:section sec-5 -->
## DEC-8 retired (DEC-124)

Removed:

| site | what |
|---|---|
| `satan-run.el:308-323` | the DEC-8 comment block and `satan-run--interactive-calls` |
| `satan-mcp.el:109,159-161` | the session-busy comment and the mint refusal |
| `satan-mcp.el:300-305` | the increment and decrement around dispatch (replaced by the session's `in-flight`, which serves I3 only) |
| `satan-mcp.el:431-432` | the `satan-mcp-start` refusal |
| `satan-broker.el:698-706` | the `session_blocked` gate |

Kept:

- `satan-run--spawn-running` and the `run_busy` gate (DEC-023, one broker
  run at a time) — unrelated to MCP.
- `session_blocked` in the failure-streak transparent reasons
  (`satan-broker.el:319-321`), because historical run dirs carry it. A
  comment marks it historical.

A broker tick now spawns while MCP calls run, and the reverse. The shared
state DEC-8 guarded was attribution, which DEC-123 removes. The rest is the
same as during today's post-ISS-058 overlap: a broker run already live
while an MCP call arrives.

<!-- doctrine:section sec-6 -->
## Bundle fields and readers (inq-4, inq-7)

The manifest and `bundle.json` gain `:conversation` (string or JSON null)
and `:kind`. `:mode` stays `"interactive"`, so the run-id format, the tool
allowlist and the broker failure streak are unchanged.

No reader changes:

- `satan-context--list-recent-runs` and `satan-tank` show more interactive
  dirs, capped at their usual count.
- `runs/most-recent` is broker-only.
- The budget sums transcript usage, and MCP transcripts carry none.

IMP-053 is the first consumer of `:kind`.

<!-- doctrine:section sec-7 -->
## malebolge client (DEC-125)

```
satanTools(socket)
 ├─ discovery: reconnectingClient(socket, log, refresh)        tools/list, refresh  (SL-028, as today)
 └─ pool: Map<key, Entry>   key = `${conversationId}\u0000${kind}`
      Entry { client: reconnectingClient(socket, log, refresh, capabilities),
              inFlight, timer?, announced }
```

- **`reconnecting-client.ts`**: `reconnectingClient(socketPath, log,
  onReconnect)` gains an optional fourth parameter, `capabilities`. `connect`
  passes it to every `McpClient` it creates (`reconnecting-client.ts:63`),
  so each replacement connection repeats the identity.
- **`conversation-context.ts`** (malebolge DEC-018) gains
  `satanIdentity(conversationId, kind)`. It returns
  `{experimental: {satan: {conversation: String(id), kind}}}`, the same id
  form as `SATAN_CONVERSATION` (DEC-020). Kind is `"interactive"` until a
  scheduled producer exists (IDE-017).
- **Pool** (new module `src/satan-pool.ts`, pure apart from timers):
  - `acquire(key)` returns the entry, creating it if absent. Creation is
    synchronous (`reconnectingClient` connects lazily, and its `get()`
    already shares a pending attempt), so concurrent acquires share one
    entry.
  - `inFlight++`, and the idle timer is cleared.
  - `release(entry)`: `inFlight--`. At 0 it arms `satanIdleMs`
    (`DEFAULT_SATAN_IDLE_MS` = 15 min in `satan-pool.ts`, overridable by
    `MALEBOLGE_SATAN_IDLE_MS`, a positive integer of milliseconds).
  - **Expiry:** delete the entry from the map, then `close()` it. A later
    call creates a fresh entry.
  - `closeAll()` at daemon shutdown.
- **`execute(args, api, context)`** calls tools through
  `pool.acquire(key(api.conversationId, kind))`, and releases in `finally`.
  Abort works as today, via `signal`.
- **Refresh.** The pool, not each handle, owns discovery invalidation. A
  handle's `onReconnect` fires only after that handle saw its own connection
  drop (`lost` is per handle, `reconnecting-client.ts:120-148`). An entry
  created after expiry starts with no history, so a server restart while no
  entry was alive would leave the tool registry stale for the rest of a
  running turn. Two triggers call the existing `refresh`, shared and
  coalesced as now:
  - a pooled client's `onReconnect`;
  - the first call through a new entry (`announced` false → true). The
    refresh runs after that call, and the call's result waits for it
    (bounded by the 2 s refresh deadline); the call is neither held back
    nor replayed. Without the wait, a restarted tool stays "not available"
    for one more step, because pi resolves tools at step start (PHASE-07
    VA-1). A failed refresh empties the satan extension: malebolge
    IMP-013.

  The cost is one `tools/list` per conversation window. A discovery
  reconnect that lands during that read adds one more, because `coalesce`
  queues one follow-on run by design (`coalesce.ts:9-12`). No deduplication
  is added. The failed call is not replayed: `reconnectingClient` already
  surfaces the loss to the caller.
- **Rollout (R1).** Satan lands first. An older server ignores
  `experimental` and still mints one run per connection, so the client is
  correct against either server.
- malebolge IDE-002 gets a note: `api.taskId` exists for tools.

<!-- doctrine:section sec-8 -->
## Code impact (design targets)

satan:

- `satan/satan-mcp.el` — identity parse, `initialize`, the session slots,
  failure-atomic `--ensure-run`, request error answering, admission on
  closing sessions, call settling, cancellation, deferred finalisation, the
  status `done`, removal of the DEC-8 refusals.
- `satan/satan-run.el` — remove `satan-run--interactive-calls` and the
  DEC-8 block.
- `satan/satan-broker.el` — remove the `session_blocked` gate and the global
  run-id `setq`/clear; pass the run id to the observer.
- `satan/satan-memory-store.el` — the `:run-id` key; delete the variable.
- `satan/satan-tools-memory.el`, `satan/satan-tools-hippocampus.el`,
  `satan/satan-observer.el`, `satan/satan-intervention.el`,
  `satan/satan-intervention-mark.el`, `satan/satan-tools-atsatan.el` — pass
  `:run-id` (sec-4).
- `satan/satan-audit.el` — the verifier knows `call-interrupted`.
- Tests: `satan/test/satan-mcp-test.el`, `satan-broker-test.el`,
  `satan-memory-store-test.el`, `satan-observer-test.el`,
  `satan-audit-test.el`, `satan-intervention-mark-test.el`,
  `satan-tools-atsatan-test.el`, `satan-tools-memory-test.el`, and any test
  that binds the deleted variable.

malebolge (separate repo, after satan):

- `src/reconnecting-client.ts`, `src/satan-tools.ts`, new
  `src/satan-pool.ts` (including its refresh trigger),
  `src/conversation-context.ts`, config.
- Tests: `test/satan-tools.test.ts`, `test/fixtures.ts` (the fake server
  records `initialize` params and requests per connection), and a new
  `test/satan-pool.test.ts`.

<!-- doctrine:section sec-9 -->
## Verification

satan (ert, `just check`):

- **V1.** Two connections with different identities produce distinct run
  dirs, manifests carrying `:conversation`/`:kind`, distinct boot caches and
  distinct `trace_marked` run ids. Each bundle passes
  `satan-audit-verify-run`.
- **V2.** A legacy connection behaves as today, except that it has no run
  dir before its first call. A connection that only lists tools leaves no
  dir.
- **V3.** Identity: malformed → -32602; repeated with a different identity
  → -32602; after a mint → -32600; the same identity again → ok.
- **V4.** `satan_boot_context` as the first call mints the run and answers.
  A mint that fails after the run dir exists (the second file write inside
  `satan-audit-open` fails) answers -32603 and leaves no dir. The next call
  mints exactly one dir. A disconnect after a failed mint leaves no dir.
- **V5.** A disconnect during a nested wait (a stub tool that calls
  `accept-process-output` while the test closes the client) records the
  result and `call-interrupted`, finalises once afterwards, and verifies
  clean. With two requests in one chunk and the close during the first, the
  second never starts and nothing is appended after finalisation.
- **V6.** `notifications/cancelled` during a nested wait: no response is
  sent, `call-interrupted :reason "cancelled"` is recorded, and the session
  stays usable.
- **V7.** Attribution under nesting: a broker-ctx `memory_mark` dispatched
  inside an MCP call's wait attributes to the broker run. An observer
  positive verdict inside a differently attributed MCP wait emits
  `trace_marked` with the observer's broker run id. An `@satan` directive
  emits `trace_marked` with the consuming tick's run id, not the
  intervention's run. M-x marks emit no `trace_marked`.
- **V8.** No exclusion: a scheduled broker run spawns while an MCP call is
  in flight, and an MCP connection and call succeed while
  `satan-run--spawn-running` is set.
- **V9.** Double close (a sentinel event plus `satan-mcp-stop`) finalises
  once.
- **V14.** Same-session nesting: outer call A waits, and call B on the same
  session runs inside the wait. `in-flight` goes 2 → 1 → 0. With the client
  closed during B, finalisation happens once, at 0, never at 1. With the
  transport live, A and B each get exactly one response. A boolean busy
  flag in place of the count must fail this row.
- **V15.** Settle: after the `tool-call` is appended, dispatch exits with an
  escaped `error`, and separately with `quit`. Each writes a `tool-result`
  and `call-interrupted` carrying the call's `:id`, and the bundle verifies
  clean. On a live transport the error answers -32603. `quit` closes the
  transport, then propagates: an uncancelled live caller sees the
  connection close, and a second request in the same chunk never starts.
  Both cases run on a live and on a closing session. Whether the quit
  reaches an enclosing caller's wait cannot be observed in batch
  (`read_process_output` catches a quit raised in a real filter and kills
  batch Emacs); the test drives `satan-mcp--filter` directly over a live
  socket pair.
- **V16.** An uncaught error in a non-tool request handler (stubbed) answers
  -32603.

malebolge (`just check`):

- **V10.** Each (conversation, kind) gets its own connection carrying the
  capability, and a replacement connection repeats it.
- **V11.** Return after idle gets a fresh entry. Overlapping calls keep the
  entry alive. Expiry racing an acquire creates a new entry, not a closed
  one. 50 conversations produce 50 entries, and idle closes them all.
- **V12.** Using the real `reconnectingClient` against the fake server: the
  server restarts with its tool set changed while no pool entry is alive,
  and the first call through a new entry triggers a refresh, after which
  the registry holds the new tool set. Both triggers run together, with the
  discovery connection's own reconnect left real (not mocked): at most two
  `tools/list` reads (the coalescer's one queued follow-on). A pooled
  reconnect also triggers a coalesced refresh. The tool-list connection
  makes no `tools/call`.

Live (VH):

- **V13.** Two malebolge conversations produce two interactive run dirs, and
  a broker tick spawns while both are active. Record the malebolge revision
  exercised (RSK-020).

<!-- doctrine:section sec-91 -->
## Risks and governance follow-through

- **Re-entrant filters.** Nested dispatch on the same connection is
  possible during `satan-patch-rpc` waits. I2, I3 and I5 are written to hold
  under it; V5 to V7, V14 and V15 exercise it.
- **More run dirs.** There is one per activity window; readers are capped
  (inq-7). Revisit if the capsule's recent-runs block crowds out broker
  runs.
- **Idle default.** At 15 min, a long tool call keeps its window open
  (the timer arms only at zero). A conversation that sits idle between turns
  for longer gets a new run per turn burst. This is intended.
- **RSK-020.** The room daemon runs from the live tree; V13 names the
  revision it used.

At reconcile:

- **SPEC-002:** the MCP transports row gains "one connection per
  conversation window; identity in `initialize`".
- **SPEC-001 revision:** REQ-007 is reconciled explicitly — the run opens
  implicitly on the first call and closes on transport close, with no
  request/response. Either REQ-007 admits transport-scoped lifecycle, or the
  divergence is recorded against QUE-001. Transport cleanup is not cited as
  ADR-017 §4 evidence.
- **Memory:** correct `mem_eb8e5cff…` (DEC-8 at call granularity) to
  "DEC-8 retired (DEC-124)".
- **malebolge:** a note on IDE-002.

