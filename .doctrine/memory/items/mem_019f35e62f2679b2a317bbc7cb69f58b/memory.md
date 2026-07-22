# Background git status takes index.lock — set GIT_OPTIONAL_LOCKS=0

`git status` (and other read commands that refresh the stat cache) writes
`.git/index.lock` as an optional side effect. Any background tooling running
`git status` in a user's working repo will contend with the user's own git
operations — symptom: sporadic "index.lock exists" failures with "nothing
else" running.

## Fix

- Environment: `GIT_OPTIONAL_LOCKS=0` on the subprocess, or
- Flag: `git --no-optional-locks status …` (git ≥ 2.15).

Designed exactly for background/IDE tooling. Read results are identical; the
stat-cache refresh is simply not persisted.

## Where this bit us

SATAN evidence assembly: `dl-satan-memory-evidence--git-state` runs
`git status --porcelain` against segment-derived cwds (repos the user was
recently active in) on every tick → background index locks in working repos.
Fix applied at the `--git-output` choke point (SL-011).

Rule: **every** read-only git invocation from SATAN (or any daemon/sensor)
sets `GIT_OPTIONAL_LOCKS=0`. Only intentionally-writing ops (patch worktree
management, in satan-owned trees only) may take locks.
