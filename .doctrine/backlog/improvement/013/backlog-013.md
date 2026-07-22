
# SATAN perception signal-model promotion (class B to class A)

Split out of **[[DE-010]]** (2026-06-09) after an adversarial review (gpt-5.5)
showed the promotion has consumer fan-out that the DE-010 structural cut does
not. DE-010 lands the perceive/consume cut, ISSUE-001 fix, and the ingest
cursor; this item promotes *what perception reads*.

## Problem

[[ADR-001]]'s premise — perception is "a pure function over the durable segment
log" — is aspirational. The percept (`dl-satan-memory-evidence-assemble`) fuses:

- **Class A — replayable window evidence**: focus/browser/content panopticon
  segments, the git-commit feed, bough recent/day. (Caveat: not uniform —
  `content_recent` is tail-N, `bough_recent` is since-start with no end, bough
  is a separate store, not panopticon.)
- **Class B — non-replayable present-tense reads**: `:current_window` (live
  `current/sway.json`), `:git_state` (live cwd git), `:fs_state` (live cwd
  recent files), `:bough_active`.

Until class B is promoted to replayable series, decoupled perception (DE-010's
cut + [[ADR-002]]'s future gate) produces archaeology fused with wrong-era live
state. The `:cue_only` flag *resembles* the A/B seam (it splits heavy-window vs
cue probes) but is an optimization, not an authority model — do not treat it as
the partition.

## Target

Promote class B into replayable series so perception reads (near-)only
time-addressable sources:

- `:current_window` → derive a current-state view from the `focus` series.
  **Not a free swap**: the live snapshot schema (`app_id/workspace/output/
  title/pid`) differs from focus rows (closed intervals, `duration_s`,
  `last_title`); freshness clocks/thresholds differ; `sensor-alerts` has
  current-specific causes pointing at `current/sway.json`. Needs a new
  `current_window_from_focus` schema + status + alert redesign, or panopticon
  emitting an explicit current-state segment.
- `:git_state` → registry-driven `git status` segments. **ISSUE-006-extended**:
  one host-side panopticon git producer emits commit *and* status segments, fed
  by a repo registry (poller owns discovery; commit-hook upsert is a
  non-load-bearing fast-path). Cross-repo (panopticon, ungoverned) dependency.
- `:fs_state` → **drop**, but not in isolation: canon loses `cwd.project`
  fallback + `cwd.file_kind`; observer loses `:fs_recent_delta`. Replace those
  signals or explicitly delete/update the canon rules, observer predicates,
  motives, and tests.
- bough → **deprecate end-to-end**: canon emits bough handles, observer
  classifies bough outcomes. Retire those consumers too, or keep bough in
  evidence until they are removed. (denote/org displaced bough; keep query code
  dormant; solve storage if usage revives.)

## Dependencies / sequencing

- Depends on [[DE-010]] (the cut + cursor) landing first.
- `:git_state` promotion depends on the panopticon git producer (ISSUE-006
  extended) — a separate, ungoverned repo work-item.
- Interacts with [[ADR-002]]: replayable perception is what makes the
  stochastic arrival gate's late/irregular consumption honest.

## Net

This is the work that makes ADR-001's premise *true*. Each B→A move carries
downstream fan-out (canon/observer/motives/alerts) — scope per-key, with tests,
when promoting. Promote to a delta once DE-010 lands.
