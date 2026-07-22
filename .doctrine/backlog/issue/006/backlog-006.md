
# SATAN git sensor bwrap-blind: jailed-agent commits never reach the feed

## Problem

The SATAN git-activity sensor undercounts commits, and the observation traces
(`dl-satan-observer` / tick-pulse) consequently report the user as "idle /
reading" while a bwrap-jailed agent (`clanker`) is shipping large volumes of
code. The perception layer is reasoning from a deaf sensor.

## Root cause

The feed is produced by a global git `post-commit` hook
(`satan/bin/satan-git-post-commit`) wired via host `core.hooksPath`. A bwrap
jail carries none of its three prerequisites: the `~/.config/git/hooks/`
symlink isn't bind-mounted, `~/.local/state/behaviour/segments/` isn't mounted
writable, and the overlaid `$HOME` has no `~/.gitconfig`. So jailed-agent
commits never produce a segment row. **Not** author-filtering — the hook
records `%an` verbatim.

Full analysis + evidence: [[mem.fact.satan.git-sensor-bwrap-blind]].

## Evidence (2026-06-05)

- `~/dev/forgettable` last 50 commits: 30 `clanker`, 20 `David Lee`.
- 06-04 segment file: 16 `forgettable` rows, all `David Lee`, **zero
  `clanker`**.
- Secondary undercount: feed is 24h-windowed + `seg-limit`-capped.

## Fix (placement decided)

Capture moves to **panopticon** (`~/dev/panopticon`, owns
`~/.local/state/behaviour/`) as a new host-side producer modeled on
`sway_watcher`: poll tracked repos with `git log`, dedup by sha, append
segments. Host-side → env-agnostic → catches jailed commits; sandbox stays
sealed (do **not** mount the segments tree into the jail). Producer is
**Python** (panopticon house language; workload is syscall-bound). POL-001
confirms a git poller does not earn an `.emacs.d` seat.

## Cross-repo sequencing

1. **panopticon** (separate repo, no spec-driver): build `panopticon-git`
   producer + systemd service/timer. *Primary work; not governed by this
   project.*
2. **.emacs.d** (this project, deferred): once panopticon emits git segments,
   retire/demote `satan/bin/satan-git-post-commit` to avoid double-write, and
   reconcile AGENTS.md + the hook CAVEAT docs. *This is the future `.emacs.d`
   delta — premature to scope until (1) lands.*

## Implementation brief for the panopticon agent

> NOTE: a panopticon agent works in a different repo and cannot read this issue
> or resolve `[[...]]` links. Copy this section into the panopticon work item.
> The schema below is the hard contract — emit it **byte-compatibly** or the
> SATAN evidence consumer (`.emacs.d/satan/dl-satan-memory-evidence.el`)
> mis-parses.

### Output contract (verified against `satan/bin/satan-git-post-commit`)

One JSON object per line, appended to
`~/.local/state/behaviour/segments/git-<day>.jsonl`:

```json
{"repo":"<toplevel abs path>","slug":"<slug>","remote":"<remote.origin.url or empty>","sha":"<short sha>","subject":"<commit subject>","author":"<%an>","files_changed":<int>,"start_ts":"<%cI>","end_ts":"<%cI>"}
```

- `<day>` = first 10 chars of `%cI` (committer date, ISO8601 **with offset,
  local tz**). Day-file rolls on committer-local date; consumer reads multiple
  day-files across a horizon.
- `start_ts == end_ts == %cI` (the commit instant). **Load-bearing**: the
  consumer filters the window and sorts "newest" on these two fields.
- `slug` = remote-origin basename with trailing `/` and `.git` stripped; else
  `basename(toplevel)`. **Must match** the hook — `slug` becomes the
  `project:<slug>` percept handle; a divergent slug forks the handle.
- JSON-escape backslash + double-quote; flatten tabs → space. Atomic
  single-line append.
- Write **directly to `segments/`**, real-time — do NOT route through
  panopticon's nightly `raw/ → segmentize` batch. Git is the documented
  freshness exception (the hook did the same); the evidence window needs
  commits visible within a poll interval, not next-day.

### Why host-side (the whole point)

bwrap-jailed agents can't fire the host hook. A host-side poller is
env-agnostic → it captures jailed `clanker` commits the hook misses. Keep the
sandbox sealed: do **not** mount the segments tree into the jail.

### Open decisions (resolve before/while building — do not guess silently)

- **Repo discovery**: `~/dev/*`? an explicit allow-list? a config file? (the
  hook was push-based so never needed a repo set; a poller does.)
- **Poll cadence**: interval value + mechanism (systemd timer like
  `segmentizer.timer`, vs a long-running watcher like `sway_watcher`).
- **Dedup state**: where to persist last-seen sha per repo, in panopticon's
  state conventions. Also backfill horizon on first run.
- **Hook coexistence**: during transition both hook and poller may write the
  same commit → dedup by `sha` (the `.emacs.d` hook retirement in step 2
  closes this, but order isn't guaranteed).

Model on `panopticon/sway_watcher/` (closest sibling producer). Producer is
**Python** (panopticon house language; workload is git-subprocess-bound).

