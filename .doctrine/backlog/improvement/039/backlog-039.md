# IMP-039: malebolge: refresh the SATAN tool list when satan-mcp's tools change

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From IMP-038. Malebolge reconnects to satan-mcp after a restart, but keeps the
tool list satan-mcp offered at daemon start (`src/satan-tools.ts`
`connectSatanTools`). A tool added, removed or re-schema'd in Emacs reaches the
model only after a daemon restart.

- On reconnect, re-list tools and reinstall the `satan` extension; pi-durable
  registries can change while the Harness runs.
- Decide what a removed tool does mid-conversation (the model may still call it).
