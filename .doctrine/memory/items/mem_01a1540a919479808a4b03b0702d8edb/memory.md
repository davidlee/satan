Observed 2026-10-19 (SL-026 PHASE-08).

- Room base floor is `git bash coreutils-full which` (oubliette `vm/room.nix`):
  no `find`. `rg` comes from `/etc/room/base/bin`.
- A repo's tool set (its `toolsPackage`) reaches a shell only through
  `session <repo> -- <cmd>`; the runner puts it first on PATH for every job
  exec. `nix develop` cannot work: the guest's `/nix/store` is read-only.
- Room clones carry no git author identity (ISS-049); bun has no DNS
  (ISS-048).
- A patch job's transcript: `~/.local/state/satan/runner/runner.sqlite`,
  `job_events` (by `job_id`; the `conversation` event names the id) and
  `pi_entries` (by `conversation_id`, `record` JSON). Open read-only.
- A detached HEAD at `refs/host/<branch>` is fine: the runner pushes the
  base itself and switches to `job/<id>` from the base oid; only a clean
  `git status --porcelain` matters.
