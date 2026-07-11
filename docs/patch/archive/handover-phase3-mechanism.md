---
name: satan-patch-handover-phase3-mechanism
description: SATAN patch-agent handover — superseded; covers Phase-3 mechanism landing
metadata:
  type: handover
  topic: satan-patch
  status: archive
  updated_at: 03398479
  verified_at: 03398479
---

# SATAN patch-agent — Handover (post-Phase-3-mechanism)

> **Direction change (post-handover-2)**: the runner has been
> extracted out of Emacs into a standalone Go daemon at
> `~/dev/satan-patcher/`.  Reason: Emacs restart fragility, direnv
> env coupling, per-process op-unlock cost.  The DB schema +
> NOTIFY channels are the wire contract; Emacs keeps the broker
> tools (INSERTs) and the inbox handoff (LISTEN).  Start there
> for any future work on the runner / adapters / worktree
> write-paths: see `~/dev/satan-patcher/docs/handover.md`.
>
> **Elisp companion changes (this session, on `rust` branch — not
> yet committed):**
> - `satan-patch-store.el`: INSERT now uses a CTE that fires
>   `pg_notify('patch_jobs_new', $id)` for queued rows only, so the
>   daemon's LISTEN wakes immediately without polling.  Non-queued
>   inserts (seeded history) deliberately suppress the NOTIFY.
> - `satan-patch-runner.el`: new `satan-patch-runner-enabled`
>   defcustom (default `t`).  Flip to `nil` to hand the queue off to
>   the satan-patcher daemon — `tick`, `kick`, and `start-timer` all
>   short-circuit when nil.
> - Tests: 2 new store tests (NOTIFY-fires + NOTIFY-suppressed-on-non-queued)
>   and 1 new runner test (disabled-short-circuits).  All 248 satan
>   tests pass (1 pre-existing unrelated grammar failure; 2 intentional
>   skips).
>
> The sections below describe the *pre-extraction* elisp state
> and remain accurate for the Phase-3 mechanism that landed in
> commit `17575424`.

Patch-agent extension lands through Phase 3 *mechanism*.  Mode-prompt
content edits + memory hooks deferred.  Substrate, runner, and inbox
handoff are end-to-end on the Phase-2 fake adapter; jailed-pi is wired
but only smoke-tested live behind `SATAN_PATCH_LIVE=1`.

## Read in order

1. `../brief.md` — brief (21 §).  What + why.
2. `../plan.md` — plan (§0 decisions, §1 file plan,
   §3 Phase 2, §4 Phase 3, §5 risks, §6 commit cadence).
3. `~/.emacs.d/docs/emacs/traps.md` — Nix wiring traps.  Trap #1 (untracked .el
   invisible to flake) still bites every new file.
4. `~/.emacs.d/CLAUDE.md` + `~/.claude/projects/-home-david/memory/MEMORY.md`.
5. This file.

## What landed

### Phase 1 (commit 5bad646f)

```
satan/memory/migrations/0005_patch_jobs.sql        prod-applied? see "DB state" below
satan/satan-patch-store.el                       PG CRUD; FOR UPDATE SKIP LOCKED claim-next
satan/satan-patch-worktree.el                    branch name + worktree add + allowlist
satan/satan-tools-patch.el                       5 broker tools + satan-patch-prepare stub
satan/test/satan-patch-store-test.el             13 ert
satan/test/satan-patch-worktree-test.el          12 ert
satan/test/satan-tools-patch-test.el             11 ert
~/notes/satan/tools/patch_job_{create,status,result,cancel,cleanup}.md
```

### Phase 2 (commit aa8d43b4)

```
satan/satan-patch-adapter.el                     registry + invoke dispatcher
satan/satan-patch-adapter-pi.el                  jailed-pi -p --mode json --no-session
                                                    --no-context-files --tools read,write,
                                                    edit,bash,grep,find,ls --system-prompt-file
                                                    auto-registers as "pi"
satan/satan-patch-prompt.el                      directive assembler (system prompt +
                                                    allowlist bullet + checks + commit footer)
satan/satan-patch-runner.el                      claim-next → prepare → adapter invoke →
                                                    on-finish ladder; single global active job;
                                                    satan-patch-runner-tick / -kick / -hook
satan/satan-patch.el                             aggregator (require all + register hooks)
satan/test/satan-patch-adapter-test.el           5 ert
satan/test/satan-patch-runner-test.el            10 ert (1 SATAN_PATCH_LIVE-gated)
~/notes/satan/patch-agent/prompt.md                 harness system prompt
```

Worktree module gained `commits` / `diffstat` / `status-clean-p`
helpers and now appends `.satan-patch-manifest.json` to the
worktree's per-worktree `info/exclude` so a no-op pi run shows up as
truly clean.

`patch_job_create` takes a new boolean `:start` arg (default t).  When
t, kicks `satan-patch-runner-kick` after insert.  Phase-1 tests
pass `:start nil` to keep state assertions deterministic.

### Phase 3 mechanism (commit 17575424)

```
satan/satan-patch-inbox.el                       runner-hook target;
                                                    needs_review → "Patch ready: ...",
                                                    failed → "Patch failed: ..." :urgent:.
                                                    Body carries commits/diffstat/checks/
                                                    warnings/review-commands block.
satan/satan-patch-classify.el                    keyword heuristic →
                                                    `satan-patch-classify' →
                                                    'patch | 'dispatch
satan/satan-tools-inbox.el                       extracted satan-tools-inbox-write
                                                    (no caps check); tool handler wraps it
satan/satan-tools-atsatan.el                     notes_at_satan_done gains :patch-job;
                                                    renders `patch-job: queued <id>` block
satan/test/satan-patch-inbox-test.el             5 ert
satan/test/satan-patch-classify-test.el          5 ert
satan/test/satan-tools-atsatan-test.el           +1 ert (patch-job-arg-renders-queued-block)
```

Total: 244 ert expected, 2 skipped (`satan-integration/morning-
end-to-end` and `satan-patch-runner/real-pi-edits-and-commits`).

## What's left

### Phase 3 content (deferred — touches user-owned prompt files)

Plan §4.3: tick + self-edit-mech + self-edit-mind prompts under
`~/notes/satan/prompts/` need text edits so the *model* uses the
mechanism.  Mechanism is ready; nothing else blocks this.

Specifically:

```
tick prompt          tell model to call satan-patch-classify-style
                     reasoning, then patch_job_create for patch-shaped
                     directives, then notes_at_satan_done :patch-job <id>.
                     Do NOT also claim the directive done.
self-edit-mech       default allowed_paths ["~/.emacs.d/satan/",
                     "~/.emacs.d/test/", "~/notes/satan/tools/"]
                     default checks: ert + emacs --batch byte-compile
self-edit-mind       default allowed_paths ["~/notes/satan/",
                     "~/.emacs.d/satan/prompts/"]
                     default checks: prompt lint
```

These are content edits, not code.  Reasonable to draft them inside a
patch-agent job once the prompts route through it.

### Plan §4.5 memory hooks (optional)

On terminal state (runner-hook fires already with the row plist), call
`memory_mark` with topic=[patch-agent, <project>], outcome by state.
Mechanism: `satan-tools-memory` exposes the tool; the runner hook
is the natural call site.  Skipped at user's discretion ("Add iff
doing so doesn't blow scope" — plan §4.5).

### Phase 4 (plan §17 + §1.1)

Out of v1.  Branch acceptance detection, stale detection, cleanup
sweep, parallel runners, automatic merging, push to remotes — all
explicitly non-goals (brief §19).

## Risks observed at impl time

1. **DB state.** Migration `0005_patch_jobs.sql` applied to
   `satan_memory_test` only.  Prod `satan_memory` still pending
   operator-applied (0004 was the prior pending one — confirm before
   running this in prod).  No prod kick will succeed until 0005 is
   applied.

2. **AGENTS trap #1.**  New `.el` files are git-tracked but
   `home-manager switch` not run.  The flake-built Emacs running in
   the user session does **not** see the new modules yet.  Until then,
   `M-x satan-run` against any mode that pulls in patch-agent will
   `void-function satan-patch-runner-kick`.

   ```
   cd ~/flakes && home-manager switch --flake .#david
   ```

3. **Stale `.elc` ate the patch-job test once.**  Compile-angel
   recompiles on save inside Emacs, but `emacs --batch` does not.  If
   adding new arg-paths or arity to a tool, delete the stale `.elc` /
   `.eln` if a batch ert run shows a mismatch between source and
   observed behavior:

   ```
   rm satan/<mod>.elc eln-cache/*/<mod>-*.eln
   ```

4. **Pi `--accept-all` does not exist** (plan §5.3 was wrong).  Pi
   `-p --mode json --no-session` is non-interactive by construction;
   jail is the safety boundary as planned, just without that flag.
   `satan-patch-adapter-pi.el` does not pass the flag.

5. **jailed-pi cwd inside jail = `/workspace/<basename>` where
   basename is `<job_id>`.**  Pi did not refuse this in smoke test
   (`/workspace/.emacs.d` worked from this repo).  Real-pi gated test
   exists; only run with `SATAN_PATCH_LIVE=1`.

6. **The user has uncommitted WIP unrelated to patch-agent** —
   `CHANGELOG.md`, `satan/satan-memory.el`,
   `satan/satan-memory-store.el` (memory-list command + drop
   `LEFT(payload, 200)` from `store-recent`).  Phase-2 and Phase-3
   commits did **not** touch these.

## Verify

```sh
# DB reachable + tables present
psql -h /run/postgresql -d satan_memory_test -c '\dt patch_*'

# Phase-2 modules byte-load
emacs --batch -L satan -L core -L lisp \
  -l satan/satan-patch \
  --eval '(message "adapters=%s" satan-patch-adapters)'

# Full satan ert (244 expected, 2 skipped)
emacs --batch -L satan -L satan/test -L core -L lisp -L org -L apps \
  -L editing -L completion -L dev -L lang \
  $(for f in satan/test/satan-*-test.el; do echo "-l $f"; done) \
  -f ert-run-tests-batch-and-exit

# Real-pi smoke (opt-in)
SATAN_PATCH_LIVE=1 emacs --batch ... -l satan/test/satan-patch-runner-test.el \
  --eval '(ert-run-tests-batch (list (quote member) (quote satan-patch-runner/real-pi-edits-and-commits)))'

# Which jailed-pi binary
which jailed-pi
```

## File map (patch-agent)

```
satan/
  satan-patch.el                aggregator
  satan-patch-store.el          PG CRUD
  satan-patch-worktree.el       git mechanics + post-run inspection
  satan-patch-adapter.el        protocol + registry
  satan-patch-adapter-pi.el     jailed-pi adapter
  satan-patch-prompt.el         directive builder
  satan-patch-runner.el         orchestrator
  satan-patch-inbox.el          runner-hook → inbox.org headline
  satan-patch-classify.el       patch | dispatch heuristic
  satan-tools-patch.el          5 broker tools + satan-patch-prepare stub
  satan-tools-inbox.el          shared inbox writer + inbox_append tool
  satan-tools-atsatan.el        notes_at_satan_done :patch-job
  memory/migrations/0005_patch_jobs.sql
  test/satan-patch-*-test.el
~/notes/satan/patch-agent/prompt.md
~/notes/satan/tools/patch_job_*.md
~/.local/state/satan/patch-agent/worktrees/<job_id>/
~/.local/state/satan/patch-agent/logs/<job_id>.jsonl
```

## Don't

- Apply 0005 to prod `satan_memory` without explicit user OK.
- Mock the DB in DB-touching tests; `satan_memory_test` is cheap.
- `git stash` anywhere under `~/` — `~/` IS a git repo.
- Skip-unless on tests should check both psql reachability AND `git`
  binary where used.
- Rewrite queued `@satan-was-here` blocks in place when patch
  completes — by design.  Inbox is the user surface (plan §4.1).

## Suggested next move

Decide whether to:

(a) **Land Phase 3 content**: edit `~/notes/satan/prompts/tick/*` +
    `~/notes/satan/prompts/self-edit-{mech,mind}.txt` to route
    patch-shaped directives through `patch_job_create`.  Then drive
    one real `@satan rewrite ...` end-to-end with
    `SATAN_PATCH_LIVE=1` to satisfy plan §4.6 acceptance.

(b) **Memory hooks** (plan §4.5) — small, isolated; one runner-hook
    target similar in shape to `satan-patch-inbox-handoff`.

(c) **CHANGELOG.md sweep** — append Phase 2 / Phase 3 entries above
    the user's pending memory-list entry, then `home-manager switch`.

Pick (a) for acceptance; (b)+(c) are housekeeping.
