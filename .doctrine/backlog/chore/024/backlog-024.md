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

## Fleet (2026-11-06)

`/srv/fleet` `384c141`: the room's target takes `capsule-tools`, with the re-lock onto
`e399fae`. `just` was red on `.#fragmentsCases` (`attribute 'lounge' missing`), also at
`a9b384f` and `b9d6a2e`, so this change did not cause it. oubliette:ISS-028 fixed that in
`27612b8`, and fleet `b130609` locks it.

- `just` exit 0 at `b130609`, and again at `3809645`, which drops satan's stale
  `inputs.goad.follows`. `.#roomImages` is the same store path either side of that commit.
- `fragmentsCases` logs `skip case 6: no room fits`. Case 6 needs a room with no fragments,
  and fleet's only room selects `postgresql-18`. The postgresql cases ran.
- Pushed to origin/main through `3809645`.

## Room (2026-11-06)

`just refresh-build assistant`: `current` and `booted` both moved to `9gbi3cna…`.

- `session satan -- type -a doctrine`: one entry, `/etc/room/repo/satan/tools/bin/doctrine`,
  which is `doctrine-0.48.1` in `satan-capsule-tools`. `doctrine status` runs in `/work/satan`.
- `doctrine` is not on a login's `PATH`, for `agent` or `satan`. That is by design: a room's
  tool set is reached only through `session` (oubliette `docs/contract-target.md`).
