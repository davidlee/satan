## Decision

```json
{
  "schema": "pi-agent-result/1",
  "state": "completed" | "failed" | "incomplete" | "refused" | "timeout" | "ceiling_exceeded",
  "result": "<final assistant text>" | null,
  "transcript": "<markdown, budgeted>",
  "status": { ...pi-run-status/1... },
  "artifacts": { "dir": "…", "events": "…", "transcript": "…", "status": "…" },
  "refusal": { "reason": "…", "detail": "…" }
}
```

- `status` is the reducer's `pi-run-status/1` record verbatim — one shape for the shell entry point, the server and any later observer.
- `result` comes from a new `Reduced.result` field rather than by parsing `## Result` out of the transcript. Small, backward-compatible addition to `pi/reduce/reduce.ts` (the CLI and its 15 tests are unaffected); the slice's 'import only' note is widened for it.
- `state` unions the reducer's three verdicts with three server-only ones: `refused` (nothing spawned), `timeout` (the backstop fired, child exit 124), `ceiling_exceeded` (the stream gate aborted, DEC-090). `refusal` is present only for `refused`.
- `transcript` is budgeted at 8192 bytes by default via a `transcript_budget_bytes` argument (`0` = full); the unbudgeted text is always at `artifacts.transcript`.
- Run outcomes are MCP tool results (`content` + `isError`), never JSON-RPC errors: a failed run is a successful call. JSON-RPC errors are reserved for malformed requests (satan-mcp precedent, `satan-mcp.el:311-331`).

## Artefacts live outside the tree

`PI_MCP_RUN_DIR` (default `$XDG_STATE_HOME/pi-mcp/runs`), one directory per run id. Not under the call's root: the dispatch path imports a worker's uncommitted working-tree delta, and a run dir inside the repo would land in it. The server is not jailed (only the child wrapper is), so it may write there freely; inside a jail-run child that path is invisible, which is correct — the child never writes artefacts.


## RV-043 F-5 and F-12: the answer is the terminal message, and every abort has a cause

F-5 defeated the first predicate. `agent_settled` plus "any stop reason" is
satisfied by `error`, and the reducer selected the last prose block anywhere in
the run — so `final: true` could carry stale planning text, or only the last of
several text blocks in the final message.

Corrected rule: `result` is the **terminal assistant message** — the last
`message_end` with `role: assistant`, having a terminal `stopReason`, with no
later assistant message — with **all** its text blocks joined. `final` is true
only for `stop`; `length` yields `final: true` with `truncated: true`; `error`,
`aborted`, `toolUse`, `deferred`, and any server-caused stop yield
`final: false`. The reducer therefore gains `result`, `final` and
`terminalReason` rather than only `result`.

F-12 defeated the precedence rule: every server abort collapsed into
`ceiling_exceeded`. Every non-completed outcome now carries a named
`termination`, and the state follows it:

| cause | state | final | result |
|---|---|---|---|
| terminal `stop` | `completed` | true | text |
| terminal `length` | `completed` | true (truncated) | text |
| terminal `error` / `aborted` | `failed` | false | null |
| no terminal message, child exited | `incomplete` | false | null |
| `timeout` — the wall-clock backstop | `timeout` | false | null |
| MCP cancel / stdin EOF / driver death | `cancelled` | false | null |
| switch flipped mid-run | `cancelled` | false | null |
| measured ceiling crossing | `ceiling_exceeded` | false | null |
| unknown or unpriced usage | `accounting_unknown` | false | null |
| audit append failed mid-run | `audit_failed` | false | null |
| nothing spawned | `refused` | false | null |

Precedence: the **earliest** cause wins, and a cause discovered after the child
has settled still decides the state — a run cannot claim success when the reason
it stopped was an audit or accounting failure. `transcript` is returned in every
case; only `result`/`final` are withdrawn.

## RV-043 F-5 (second pass) and F-12: provisional success, the commit point, a total cause order

F-5 was contested once more, correctly. The previous table made a terminal `stop`/`length` sufficient for `completed`, so a valid answer message followed by EOF without `agent_settled`, or by a nonzero exit, still read as success. The F-12 rule then contradicted itself: "earliest cause wins" cannot coexist with "a cause discovered after settling still decides".

Corrected. **Success is one predicate, not a table row**: `completed` iff a terminal assistant message exists with stop reason `stop` (or `length`, which also sets `truncated: true`), **and** `agent_settled` was observed, **and** the child exited 0, **and** accounting is known, **and** the abort latch is empty at the commit point.

The **abort latch** collects causes as they are discovered. `completed` is provisional until the **commit point** — after the termination ladder, reap, stream drain, final accounting, and the `exit` and abort evidence appends. Any cause recorded before that point decides the state; nothing runs after it, so there is no window for a post-commit surprise.

The result carries `causes` (ordered by discovery) with `termination = causes[0]`, and the state is `causes[0]`'s row. A later cause is never hidden behind an earlier one: audit failure after a timeout reports `termination: "timeout"`, `causes: ["timeout","audit"]`.

| cause | state | final | result |
|---|---|---|---|
| `stop`, and the success predicate holds | `completed` | true | text |
| `length`, and the success predicate holds | `completed` | true (truncated) | text |
| `error` / `aborted` terminal | `failed` | false | null |
| `toolUse` / `deferred` terminal, no later message | `incomplete` | false | null |
| stream ended with no terminal assistant message, exit 0 | `incomplete` (`eof`) | false | null |
| child exited nonzero | `failed` (`exit`) | false | null |
| spawn failed after the run directory was allocated | `failed` (`spawn`) | false | null |
| `timeout` — the wall-clock backstop | `timeout` | false | null |
| MCP cancel / stdin EOF / driver death | `cancelled` | false | null |
| switch flipped mid-run | `cancelled` (`switch`) | false | null |
| measured ceiling crossing | `ceiling_exceeded` (`ceiling`) | false | null |
| unknown or unpriced usage | `accounting_unknown` (`accounting`) | false | null |
| evidence append failed mid-run | `audit_failed` (`audit`) | false | null |
| nothing spawned | `refused` (its own refusal token, or `audit-failed` / `audit-unavailable`) | false | null |

Pre-spawn failures are refusals, never states: an audit append that fails before spawn discards the run directory and refuses `audit-failed`; an unwritable `attempts.jsonl` refuses `audit-unavailable`. `audit_failed` as a *state* exists only for a spawned run.

And the reconciliation line the F-6 class needed: `status.state` judges the **stream**, `state` judges the **call**. They differ only when the deciding cause arose outside the stream (`exit`, `spawn`, `audit`, `accounting`, `timeout`), and `causes` names it.

## RV-046 F-6: one vocabulary for causes and outcomes

`termination` and `causes` are the same vocabulary, and a token names the outcome
rather than the mechanism: the wall-clock backstop's cause is `timeout`, matching
its state, and `backstop` is not a cause token (it is the mechanism's name in
prose). The tables above are corrected. A mapped outcome whose cause has no token
is a schema defect, not a naming preference, and the test asserts every mapped
outcome satisfies the advertised result schema.


## RV-043 F-6 (fourth contest): the tokens are pi's, verbatim

The tables above spelled a stop reason `tool_use`. pi emits `toolUse`
(`docs/message-types.md`: `stopReason: "pending" | "stop" | "length" | "toolUse" |
"error" | "aborted" | "deferred"`), so a matcher keyed on the snake-case spelling
would classify nothing while looking correct — and `pending` was not mapped at
all. Corrected throughout: model-reason tokens are pi's stop reasons verbatim, a
`message_end` carrying `pending` is counted and is not an answer, and a reason pi
adds later is carried verbatim, counted, usage-validated and never an answer until
this contract names it.
