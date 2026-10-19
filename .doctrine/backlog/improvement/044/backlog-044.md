# IMP-044: Runner repo entries from one source: fleet room data feeds runner.nix instead of hand-copied literals

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

`~/flakes/features/satan/runner.nix` hand-copies the room's data from
`/srv/fleet/flake.nix` (`rooms.assistant`, `targets/<name>.nix`): room name,
repos user, and per repo `guest_path` (`/work/<name>`) and `quarantine`
(`/var/lib/capsule/collect/<room>/<name>.git`). The fleet exposes no room data
to home-manager (SL-023 PHASE-12 E4; RV-029 F-8). Design §5.3 wants one source
at Nix eval.

Accepted for now (user, 2026-10-19): ISS-046 adds a `repo.<name>` entry per room
target by hand, about 15 entries.

## Do

One source for the room's repos: the fleet exports room data that
`runner.nix` reads at eval, or both import a shared data file. Per-repo values
the fleet does not hold (`default_branch`, `transfer_timeout_s`, host `path`)
stay in `runner.nix`, keyed by target name. Adding a target to the room then
can't silently leave the runner out of step (and the reverse: ISS-047, a held
job whose repo leaves config wedges the seat).
