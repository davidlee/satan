
# Extract patch runner to satan-patcher daemon

Extraction candidate under [[POL-001]]. **Status: pivot-pending, already in
flight.** `~/dev/satan-patcher/` exists (Go, ~5k LoC); the
`dl-satan-patch-runner-enabled` defcustom can hand the queue off. Tracked in
`docs/satan/governance.md` Open Thread 12 + `docs/satan/patch/handover.md`.

Modules in scope: `dl-satan-patch-{store,listener,runner,worktree,adapter,
adapter-pi,prompt,classify,inbox}.el`. The tools surface
`dl-satan-tools-patch.el` is RPC into the runner and stays elisp.

Fit failure: queue worker, worktree allocator, subprocess driver — no editor
primitive used; already conceptually a daemon.

Language note: the Go implementation is incidental (an agent jumped to it
without surfacing Rust vs Go). Rewrite trigger is "grows past
evening-rebuildable" or real workload-fit pain, not "feels wrong"; until then
treat the Go as deployed reality.

**Blocked / trigger:** act when surface area grows in the next refactor theme,
or a recurring fit-bug appears (POL-001 §Verification). Disable switch already
wired.
