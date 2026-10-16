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
