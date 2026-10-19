# ASM-006: rg is on the PATH the in-room pi-env daemon inherits via session

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

## Assumption

SL-026's `grep` tool runs `rg` through the job's `ExecutionEnv` (pi-env daemon
in room `assistant`). We assume `rg` is on that daemon's PATH.

## Basis

- Room base = floor (`git bash coreutils-full which`) + `room.extras`, on
  `environment.systemPackages` (`~/dev/oubliette/vm/room.nix:50-56, 122`;
  oubliette DEC-052).
- `rooms.assistant.extras` includes `search` (`/srv/fleet/flake.nix:147`),
  whose packages are `ripgrep fd` (`~/dev/oubliette/fragments.nix:91-93`).
- The daemon is launched through the room's `session` program
  (`~/dev/malebolge/src/runner/room.ts:471-478`), which puts a repo's tools in
  front of the base.

Not verified: the PATH the launched daemon actually holds. Tests against
`localConnection()` use the host's `rg` and prove nothing about the room.

## Falsify by

Live: `capsule assistant ssh agent -- session <repo> -- command -v rg`, or a
patch job whose `grep` call succeeds in the room (SL-026 VH).
