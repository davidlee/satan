# ISS-030: satan-patcher has never completed a job

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

The `satan-patcher` user unit is active, but all 17 `patch_jobs` rows are `failed` (newest 2026-05-20) and no clone has survived. Probable cause (unverified): the unit PATH is only nix, git and coreutils (`~/dev/satan-patcher/nix/module.nix:139`); with no `.satan-patch.toml` `flake_attr`, the program falls back to bare `jailed-pi`, which does not resolve.

Also: the review commands in `finish.go:208-220` cherry-pick a sha that exists only in the job clone; the adapter axis is recorded but never dispatches. Decide the patcher's direction (IMP-006, oubliette rebuild — `satan-patcher/docs/oubliette.md:124-157`) before fixing in place.
