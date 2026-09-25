
# SATAN perception signal-model promotion (class B to class A)

The work that makes [[ADR-001]]'s premise true: perception is a pure function
over durable, time-addressable series. Today the evidence window
(`satan-memory-evidence-assemble-with-bounds`) still fuses replayable window
evidence (class A) with present-tense live reads (class B), so a percept
built for a past window carries present-day state.

*Rewritten 2026-09-25 against the extracted package. The original body
(2026-05-30, `.emacs.d`) cited `DE-010` / `ISSUE-006`, which resolve in the
frozen `.emacs.d` corpus; its `dl-satan-*` names are now `satan-*`.*

## State of each key

| key | today | class | move |
|---|---|---|---|
| focus / browser / content segments | panopticon series | A | — |
| `:git_commits` | `segments/git-%F.jsonl` (panopticon `git_poller`, cwd-independent) | A | — |
| bough | **removed from evidence** (`SL-002` PHASE-02, `2928f0f`) | — | residual grammar/data: [[IMP-016]] |
| `:fs_state` | **dropped** ([[IMP-034]], 2026-09-25) | — | — |
| `:git_state` | **dropped** ([[IMP-034]], 2026-09-25); `cwd.project` with it | — | status segments are now *new* signal (below) |
| `:current_window` | live `current/desktop.json` + mtime freshness | B | replay from the desktop event stream (below) |

`DE-010`'s perceive/consume cut and ingest cursor have landed
(`satan/satan-ingest-cursor.el`), so the original "promote once DE-010 lands"
gate is met. [[ADR-002]] (stochastic arrival) is still `proposed`: motivation,
not a binding driver.

## Upper bound: what the compositor can tell us

Panopticon can only be as rich as the supported compositors' IPC (sway, niri,
umbriel). A sampled umbriel IPC stream (2026-09-25; `windows` and
`workspaces` events) shows the ceiling:

- **Every event is a full snapshot**, not a delta: all windows with `id`,
  `app_id`, `pid`, `title`, `workspace`, geometry, `focused` / `active`,
  `floating`, `urgent`, `scratchpad`, `xwayland`; workspaces with `name`,
  `named`, `occupied`, `layout`, `output`.
- **Focus is per workspace/output**: more than one window can carry
  `focused: true` at once, so "the focused window" is a projection panopticon
  chooses, not a primitive.
- **No per-window cwd.** All terminal windows share one `pid` (one ghostty
  process), so `/proc/<pid>/cwd` cannot distinguish them.
- **Titles carry the project, informally.** Shell titles carry the cwd and
  running command (`~/dev/satan> ls`); agent harness titles carry the repo
  (`π - satan-corpus`) or the session topic. That is the only
  compositor-sourced candidate for the *active-project* signal [[ISS-004]] is
  blocked on, and it is a heuristic over free text.

Panopticon today narrows this to a focused-window `DesktopState` (`window_id`,
`app_id`, `pid`, `title`, `workspace`, `output`;
`panopticon/compositor/model.py`), emits one `source:"desktop"` event per
transition (`window_focus` / `workspace_focus` / `window_title`) to
`raw/desktop-*.jsonl` with that full state as fields, and also overwrites
`current/desktop.json`. The inventory, urgency and workspace names are
dropped at the adapter.

## Moves

### `:current_window` — replay, no new producer

The desktop event stream already makes current state replayable: current at
`t` is the state carried by the last `desktop` event at or before `t`. The
live file is a cache of the same thing. What changes is freshness:

- mtime staleness conflates "daemon dead" with "user idle on one window".
  In the series these differ: the runner's lifecycle events
  (`panopticon/compositor/runner.py`, `_lifecycle`) mark connect/disconnect,
  so "no transition since X, daemon connected" is a fact, not a guess.
- `satan-sensor-alerts.el`'s `:current_window` causes point at the live file;
  they need rewording against the stream.
- Payload shape stays (`app_id/workspace/output/title/pid`, plus
  `window_id`), so canon consumers of `:current_window` should not move.

Open: read `raw/desktop-*` directly, or have panopticon's segmentizer emit a
`current` point series SATAN reads like the other segments. The first adds
a new raw-reading path to SATAN; the second keeps "SATAN reads segments" as
the invariant. Prefer the second unless it costs a producer change for little.

Optional, separable: widening panopticon's projection (window inventory,
`urgent`, workspace names) is possible within the IPC ceiling, but is new
signal, not promotion. Do not bundle it.

### Git status — new signal, not a promotion

IMP-034 dropped the cwd-anchored `:git_state` outright (the broker cwd is
Emacs's `default-directory`, not the user's project). Working-tree status is
therefore no longer a class-B key to promote but a new signal, if wanted.

Panopticon's `git_poller` (`panopticon-git`, 5-minute timer over `~/dev`)
already polls repo work trees for commits. Extending it to emit periodic
`git status` segments (dirty / ahead / branch per repo) is the natural home:
one host-side producer, cwd-independent, and it captures jailed work. What
remains open is *which* repo is the user's: that is [[ISS-004]]'s
active-project signal, for which window titles (above) are the only
compositor-sourced candidate. Scope the two together.

Cross-repo: panopticon is ungoverned by this corpus, so the producer change
is a work item there.

## Known gaps in the commit feed (the surviving project signal)

- **Coverage:** `panopticon-git` scans only the immediate children of
  `~/dev`. Repos elsewhere (`~/notes`, `~/satan-corpus`, `~/flakes`,
  `~/.emacs.d`) reach the feed only via the host post-commit hook, which
  never fires inside jails (and whose install is not visible in the flake).
- **Resonance cue:** `memory_resonate`'s cue derivation (`:cue_only`) skips
  the commit feed, so resonate cues carry no `project:` handle since
  IMP-034.

## Sequencing

1. [[IMP-034]] — drop every cwd read. **Done 2026-09-25.**
2. `:current_window` replay — mostly SATAN-side; decide the read path first.
3. Git status + active project — new signal; needs the panopticon status
   producer and an active-project signal. [[ISS-004]] items 1–2 are obsolete.

Each move carries canon / observer / alert / test fan-out; scope per key.
