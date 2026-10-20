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
| backstop fired | `timeout` | false | null |
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
