# IMP-020: SATAN rewrites its own goad backend via satan-patcher

Deferred follow-up to [[SL-016]] (goad as SATAN's elicitation surface), split
out at scoping on 2026-09-21 so the elicitation loop can land first.

The premise: `~/satan/goad/backend.py` is 164 lines of stateless Python that
owns everything goad knows about the keeper's day. If SATAN can rewrite it, it
can change what it asks and how — self-edit-mind extended from prompts and
framing to behaviour.

## The blocker that is now cleared

`goad/` was **untracked** in the corpus repo until `eeb4f3c` (2026-09-21).
That was a hard blocker, not a nuisance: `satan-patch-worktree-path-allowed-p`
matches each entry against `git diff --name-only base...HEAD` inside the
worktree, so an untracked file yields nothing, and a worktree checked out at
`base` would not have contained `backend.py` at all.

## Prerequisites that remain

1. **`backend.py` has no tests, no fixtures and no check recipe.** Per
   [[mem.fact.satan.patch-job-contract]], `checks` are rendered into the patch
   agent's prompt and run by the *agent* in its worktree — the runner never
   executes them. With nothing to run, a rewrite is unguarded. Worse, a check
   whose glob matches nothing exits 0, so an empty suite reports green
   ([[mem.fact.satan.green-is-not-green]]).
2. **The job must target the corpus repo.** Mechanism (`~/dev/satan`) and
   corpus (`~/satan`) are separate repos and need separate jobs. `repo` must be
   passed **absolute** (`git -C` via `call-process` does not expand `~`), and
   `allowed_paths` must be **repo-relative** (`goad/backend.py`, not
   `~/satan/goad/backend.py` — a home-anchored entry matches nothing and fails
   silently as dead text).

## Blast radius

`backend.py` runs eight times a day under a live systemd unit. The goad host
survives a backend fault without crashing, but prompts stop — and goad's own
field notes already record that *"waiting and dead look the same"*. Fixtures are
the mitigation, which is why prerequisite 1 gates this.
