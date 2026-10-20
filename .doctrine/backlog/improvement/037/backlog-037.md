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

## Progress (2026-10-17)

`jailed-malebolge` in `~/notes/flake.nix`: `mkJail jailLib.makeJailedAgent`,
agent = a `writeShellScriptBin` running the pinned `nodejs_latest` on
`~/dev/malebolge/src/daemon-main.ts`. `just hello-durable` runs it (no outer
`op run`; the launcher wraps itself).

- Keys: `apiKeys = ["DEEPSEEK_API_KEY" "OPENROUTER_API_KEY"]`, forwarded over
  bwrap `--args FD`; the list carries a comment on how to add a provider.
- Binds (after the jail-home bind): the shared `jailEnvOptions` (satan-mcp
  socket directory, ISS-042), `/run/user/1000/satan` rw (daemon socket),
  `~/dev/malebolge` ro (tools cannot rewrite the daemon), `~/satan-corpus` ro,
  `~/.local/state/satan/durable` rw.
- Jail home is jailed pi's (`~/.local/share/jail.nix/home/agent` at `~`), so
  `~/.pi/agent/models-store.json` is jailed pi's catalog cache — the one whose
  models the default `deepseek/deepseek-flash` comes from.
- Cwd becomes `/workspace/notes` (was `/home/david/notes` unjailed).

Verified: devshell builds; launcher args inspected (bind order, two keys on the
FD, no `mcp.sock` file bind). Pending: live run (1Password prompt; outside
Claude Code's sandbox).

## History (closed by SL-027, 2026-10-20)

The progress notes above are history (SL-027 DEC-076). The jailed daemon now
lives in `~/dev/satan/flake.nix` as `jailed-malebolge`, room profile: no
network, no launch dir, no `~/notes`; its gateway key is a file; its coding
tools run in oubliette room `assistant` as room user `satan`. Grants and their
dispositions: SL-027 design §4.7.
