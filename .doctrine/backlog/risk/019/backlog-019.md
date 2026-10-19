# RSK-019: Any MCP client submits patch jobs as unbounded interactive mode

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Risk

Under DEC-068 an MCP session's patch jobs carry mode `interactive`, which
SL-025 configures unbounded (`repos = "*"`, `allowed_paths = "*"`). Reaching
the MCP socket (`$XDG_RUNTIME_DIR/satan/mcp/mcp.sock`, bound into the malebolge
daemon's and pi's jails) is enough to submit a job on any configured repo,
including `satan` and `satan-corpus`. Socket access does not establish that a
human is supervising (GPT second opinion on SL-025, 2026-10-19).

## Accepted

User ruling 2026-10-19: accept for freedom of the interactive session.
Mitigations that remain: no egress from the room, human review before
promotion, promotion only creates a new branch.

## Treatments, if it bites

- Scope `interactive` like `tick-agent` (exclude SATAN's own repos).
- Restrict which jails bind the MCP socket, or give unsupervised MCP clients a
  distinct mode.
