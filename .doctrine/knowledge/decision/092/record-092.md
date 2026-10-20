## Decision

`profile` is untrusted text from an MCP client and is treated as an identifier, never a path:

- **Grammar**: `^[a-z][a-z0-9-]{0,31}$`. No `/`, no `.`, no leading `-`, no unicode escapes. Anything else is refused before the filesystem is touched.
- **Root**: the server's own profile directory, resolved once from the server's install location and overridable only by environment (`PI_MCP_PROFILE_DIR`). **Never** the call's `cwd`, never `$HOME`, never a path reachable from the request.
- **Absence is a refusal, not a default**: an unknown profile returns `refused` naming the profile and the directory searched. There is no implicit fallback profile — a silent default is how a read-only delegate becomes a writer.
- **Tracked**: the profile files ship in the repo (`pi/mcp/profiles/*.md`), not in `.pi/agents/`. `.pi/` is gitignored, so a security-relevant tool list whose only home is an ignored directory does not travel with the code (ISS-052).

## Evidence

`scripts/pi-agent:42` joins the caller's string straight into `.pi/agents/$profile.md`, rejecting only a leading `--` (`:33-37`). That is acceptable for a human typing a command in their own checkout; it is not acceptable for an MCP argument.

## Consequences

- The server carries its own profile documents and does not read pi's agent directory. Duplication with `.pi/agents/` is deliberate: one is a developer convenience, the other is an authority surface with a grammar.
- A wider `tools` argument may only *narrow* the profile's set (settled in inq-5); the profile file is the ceiling.
- The profile directory becomes part of the jail's read path: the child never needs to read it (the server resolves the profile and passes `--tools`/`--system-prompt`), so it is not bound.
