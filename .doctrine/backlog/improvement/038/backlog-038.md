# IMP-038: malebolge: reconnect to satan-mcp when Emacs restarts it

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From CHR-012. The daemon connects to satan-mcp once at start
(`src/satan-tools.ts`). If Emacs restarts satan-mcp, the MCP client closes
(logged) and every SATAN tool call fails until the daemon restarts.

- Reconnect lazily on the next tool call, or with backoff on close.
- The tool list is fixed at install time; a changed tool set needs a registry
  reinstall (pi-durable registries can change while the Harness runs).

## Progress (2026-10-17)

Done in malebolge `9126b0c`: lazy reconnect on the next SATAN tool call;
concurrent calls share one attempt; a call while satan-mcp is down is an error
result, never retried (tools have side effects). `connectSatanTools` returns
`{ extension, close }` and logs close/reconnect through the daemon log. Tests:
restart-then-call and down-then-back (`test/satan-tools.test.ts`). Tool-list
refresh split out to IMP-039.

Jailed, reconnect also needs a directory bind of the satan-mcp socket — done
for every jail in ISS-042.

Pending: live check (restart satan-mcp under a running daemon, call a tool).
