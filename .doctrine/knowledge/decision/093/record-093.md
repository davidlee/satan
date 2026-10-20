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
