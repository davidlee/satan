# CHR-024: Finish the dev-envs migration: drop dev jails and forms from the flake; doctrine out of dev-tools

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Satan's half of flakes:CHR-030. `.envrc` was already on dev-envs, but `flake.nix` still
built its own dev jails, forms and shell commands, and `dev-tools` carried doctrine, so
`doctrine` resolved to a store build ahead of the host install in both shell and jails.

## Done

- Deleted `jailed-pi`, `jailed-pi-research`, `jailed-claude`, `jailed-shell`, `bubblewrap`,
  the form family, the `d`, `jpi`, `jcl` and `jail-zsh` commands, and `workspaceDeps`.
- `dev-tools` no longer carries doctrine. `capsule-tools` adds it for the room, as
  flakes:DEC-112 did for doctrine's own repo.
- `quotient-hostile-audit` moved to dev-envs, and the `quotient` input went with it.
- `agents` stays: the harness jails and `mkJailedMalebolge` are production jails, until
  flakes:IMP-049 moves malebolge out.

## Evidence (2026-11-06)

- `type -a doctrine`: one entry, the host install, in the shell and in `jailed-shell`.
- `just check` exit 0 on the old shell, the new shell and in `jailed-shell`.
- `just check-jails` exit 0.
- `quotient-hostile-audit` against dev-envs forms for this project: PASS on read and write.

## Consequences

- Dev jails have no satan MCP socket. They already lacked it once `.envrc` moved, and
  `devEnv` cannot bind a path.
- `runner-socket-unjailed` and `op-unjailed` now scan production jails only.

## Open

- The dev-envs half of the audit move is committed in `~/flakes`, not yet pushed.
- `~/flakes/bin/dev-envs-forms`, then `quotient allow` and `direnv allow` (the operator's).
- `/srv/fleet/targets/satan.nix`: `toolsPackage = "capsule-tools"`, in the same change as
  the re-lock onto this commit. A re-lock alone drops doctrine from the room.
