# patch_job_create: allowed_paths is repo-relative; checks are the agent's, not the runner's

Three facts about the `patch_job_create` tool contract that its own
model-facing prompts got wrong for months (found closing [[CHR-004]]).

## allowed_paths is repo-relative, and only that

`satan-patch-worktree-path-allowed-p` (`satan/satan-patch-worktree.el`)
matches each entry against paths from `git diff --name-only
base...HEAD` inside the worktree — always repo-relative. Trailing `/`
is a prefix match; without one it is an exact match. Nothing expands
`~`.

So a home-anchored entry like `"~/satan/tools/"` **matches nothing**.
It does not widen access and it does not fail loudly — it is dead text
that tells the model it may edit somewhere it cannot. Mixing
repo-relative and home entries in one list is the tell.

## One job edits one repo

`repo` is validated with `file-directory-p` (which does expand `~`)
but is then handed to `git -C <repo>` through `call-process`, which
does not. Pass it absolute. Corollary: mechanism (`~/dev/satan`) and
corpus (`~/satan`) are separate repos and need separate jobs — see
[[mem.concept.satan.three-roots]].

## checks are instructions, not a runner step

`satan-patch-prompt.el` renders `checks` into the patch-agent's prompt
under `## Checks`; `satan-patch-adapter-pi.el` returns `:checks nil`.
The runner never executes them. They are commands the agent runs
itself in its worktree, so they must be runnable there (`just check`
is, as of 2026-09-17).

Related trap: a check whose glob matches nothing exits 0. The stale
`satan/test/dl-satan-*-test.el` glob made `emacs --batch … -f
ert-run-tests-batch-and-exit` load no tests and report green — one
more way the suite lies, cf.
[[mem.fact.satan.verifying-green-five-ways]].
