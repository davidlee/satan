# IDE-018: Move non-editor tools out of Emacs behind an MCP shim

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->
Raised 2026-10-26 by the user, during IMP-055.

Many SATAN tools don't use the editor as an editor (POL-001's
earns-the-seat test): `activity_read`, `content_read`, `vcs_log`,
`notify_send`, `goad_ask`, and others. The idea is to move them out of Emacs
into a separate process (the user floated TypeScript) and shim them, so they
stay available through the Emacs MCP server (`satan-mcp.el`) for the
foreseeable future.

Open questions:

- Where the shim sits. Either Emacs proxies tool calls to the external
  process (Emacs keeps registry, allowlists and audit, per the ADR-017 §3
  ledger), or the MCP client talks to the external server directly and Emacs
  drops out of the path.
- Which ledger rows move. Tool dispatch is ADR-018 D4.2's first named
  extraction candidate; this would be a step toward it.
- Language: see CHR-023 (Rust as default, not mandate).

Related: POL-001, ADR-017, ADR-018. IMP-055 adds a keyrate reader
(`satan-keyrate.el`) that would be one of the pieces to move.
