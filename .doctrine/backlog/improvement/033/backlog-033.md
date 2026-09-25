# IMP-033: Rework git-activity capture: per-repo opt-in, provenance filtering, cheaper polling

## Context

Two writers append to `~/.local/state/behaviour/segments/git-<day>.jsonl`:

- the **global** `post-commit` hook `satan/bin/satan-git-post-commit`, installed with
  `git config --global core.hooksPath ~/.config/git/hooks`;
- the `panopticon-git` systemd oneshot, every 5 minutes, scanning immediate children
  of `~/dev` (`git log --branches --since=7.days`).

Measured 2026-09-25: 317,435 rows / 116 MB, of which **304,879 (96.05%) are test
fixtures** under `/tmp` (authors `Test`, `t`, `Doctrine Test`, `T`, `test` — no human
or agent identity). The corpus board's IT-004 landed the *symptomatic* fix: a temp-path
guard in the hook, a temp-repo/temp-cwd filter in `satan-memory-evidence.el`, and a
temp-root guard in `discover_repos`. This item is the structural fix — the guards are
heuristics over *path*, and they do nothing about the two real costs below.

## Problem 1 — the hook is global and unconsented

`core.hooksPath` applies to every repo on the machine and **shadows every repo's local
`.git/hooks/`**. Every commit in every repo is captured by default, including throwaway
checkouts and repos the user never intended SATAN to observe. Wanted: capture is
**opt-in and explicit**. Candidate shapes:

1. A per-repo marker the hook checks (`git config satan.gitFeed true`, a
   `.satan-git-feed` file, or the `.satan-patch.toml` precedent), with the global hook
   exiting otherwise. Keeps one install, makes the boundary declarative.
2. Per-repo hook installation (`just install-hook` / a doctrine command) — honest, but
   every new repo is dark until installed.
3. Keep global, but require an explicit allowlist of roots (`~/dev`, `~/satan`,
   `~/notes`, …) checked against the toplevel. Cheapest, still centrally managed.

Decide which repos are actually wanted; then make that boundary legible rather than
implicit in "it's on the machine".

## Problem 2 — the hook taxes every commit on a busy repo

The hook is **synchronous** and shells out to git ~7 times per commit:
`rev-parse --show-toplevel`, `rev-parse --short HEAD`, `log -1` ×3 (`%cI`, `%s`,
`%an`), `config --get remote.origin.url`, `diff-tree --root`. No timeout, and no
`GIT_OPTIONAL_LOCKS=0` (the evidence layer sets it; the hook does not). On a repo with
concurrent agent commits, each commit pays that latency and the process churn, and a
slow/large repo blocks the commit — the concern that motivated this item.

Cheap wins: fold the three `log -1` calls into one
(`--pretty=format:%cI%x00%h%x00%s%x00%an`); drop `diff-tree` if `files_changed` has no
consumer; add a hard timeout; set `GIT_OPTIONAL_LOCKS=0`; consider appending
asynchronously (background the write, never block the commit).

## Problem 3 — the poller re-walks 7 days every 5 minutes

`_poll_unlocked` enumerates `git log --branches --since=7.days` for every repo on every
tick, then dedups candidate shas in Python against the day-file. On a busy repo that is
a repeated full 7-day history walk for a handful of new commits. The dedup is correct
but stateless, so it cannot remember where it stopped. Candidate fixes: a per-repo
cursor (last-seen sha or committer date) persisted in the state root, so the horizon
becomes "since cursor" with a periodic full reconcile; a shorter horizon; or
event-driven capture via inotify on `.git/refs` / the reflog instead of clock polling.

## Problem 4 — path is a proxy for provenance

Both guards and the reader filter classify by *where* a repo is. A scratch repo under
`~/dev` (not a temp root), or a fixture authored `t@example` anywhere, still passes and
becomes a real `project:` handle. The durable discriminator is **provenance**:
- have every test harness opt out the way panopticon's already does —
  `make_repo` sets `core.hooksPath /dev/null` so its fixtures never touch the real feed
  (`panopticon/tests/test_git_poller.py:36`); generalise to satan elisp, satan-patcher
  Go, and doctrine's Rust suite; and/or
- filter on known fixture author identities as a backstop.

Opt-out at the harness is strictly better than guessing in the reader: it removes the
rows at source, and it stops `cwd.project` / `artifact:commit` ever seeing them.

## Acceptance

- A repo is captured **iff** it opted in (or is on an explicit, documented allowlist);
  the opt-out path is documented and one harness in each of satan, satan-patcher,
  panopticon and doctrine exercises it.
- The hook's per-commit cost is bounded: at most one git read for metadata (plus the
  toplevel probe), a hard timeout, `GIT_OPTIONAL_LOCKS=0`, and no measurable commit
  latency regression on a busy repo.
- The poller's per-tick cost is proportional to *new* commits, not to a fixed 7-day
  window.
- `git-<day>.jsonl` contains no row whose repo is a test fixture, by provenance rather
  than by path.

## Relationship

Corpus board IT-004 (closed 2026-09-25) landed the path guards and the reader filter.
This item supersedes them: when it lands, the temp-path heuristics should be removable
(or kept only as belt-and-braces). Author under RFC-016's "close the loop" framing if a
design pass is wanted first.
