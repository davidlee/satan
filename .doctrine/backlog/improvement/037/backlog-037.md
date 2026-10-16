# IMP-037: malebolge: run the daemon jailed

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From CHR-012. `just hello-durable` runs `op run -- node daemon-main.ts`
unjailed. The daemon runs CodingTools (`bash`, `write`, `edit`) in its cwd
(`~/notes`), so it needs the same posture as `jpi`.

- Cheapest: start it from `jailed-shell` (`~/notes/flake.nix` `mkJail`).
- Proper: a `jailed-malebolge` via `jailLib`, binding the satan-mcp socket,
  `$XDG_RUNTIME_DIR/satan/` (daemon socket), `~/satan-corpus` (read),
  `$XDG_STATE_HOME/satan/durable/` (rw).
- Keys: follow the jailed-agents path (bwrap `--args FD`), never
  `try-fwd-env` (ISS-029), until `~/flakes` IDE-003 (LiteLLM) lands.
