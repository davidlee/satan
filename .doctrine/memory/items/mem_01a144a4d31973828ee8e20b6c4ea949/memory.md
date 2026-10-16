# pi-durable is a library, not a harness binary

`@earendil-works/pi-durable` (pi monorepo `packages/durable`) is a TypeScript
library: Harness, conversations, durable tasks, storage (memory/SQLite/JSONL),
compaction, `watchEvents` client stream. It has **no CLI and no TUI**, and the
announcement says it "does not replace the Pi coding agent".

- Coding-agent extensions (`ExtensionAPI`, `pi.registerTool`, `pi.on(...)`)
  do **not** load. Port them to `defineExtension`/`defineTool`.
- `pi-durable-subagents` (pi.dev package) is unrelated: a third-party
  coding-agent extension (`pi install`), not built on this library.
- SATAN's host program is `~/dev/malebolge` (CHR-012 spike); findings in
  RFC-018 § "Spike findings".
- MCP: use `@earendil-works/pi-mcp` (stdio/HTTP transports only;
  malebolge adds a unix-socket transport for satan-mcp).
- pi-ai's built-in model catalog lags the coding agent's remote catalog
  (cached in `~/.pi/agent/models-store.json`).

## watchEvents gotcha: an answer's text is spread across events

`message_start` carries the first partial (up to ~100 ms of text);
`message_update` carries deltas *or* whole `block`/`message` replacements;
the final entry at `message_end` may hold a tail no update delivered. A client
that only appends `text_delta`s drops the opening and the tail. Track the
answer's text and print the unseen suffix (malebolge `src/render.ts`).
Reproduce in tests with the faux provider at `tokensPerSecond: 40`,
`tokenSize: {min: 1, max: 1}`; at 400 tok/s the answer arrives unstreamed.
