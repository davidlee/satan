# RSK-018: malebolge daemon socket grants submit/abort to any local process that can connect

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From CHR-012 (RFC-018 F3). `$XDG_RUNTIME_DIR/satan/durable.sock` accepts
`input`, `abort`, `compact` from any client. The only guard is the 0700
permissions on `$XDG_RUNTIME_DIR`: any process of the user, including a jailed
agent with the runtime dir bound, can drive SATAN.

- Acceptable for the interactive spike; not for non-interactive event
  delivery (IDE-009) or for binding into jails.
- Needs a SPEC-001 view: is this socket an authority surface with an
  ADR-017 ledger row?
