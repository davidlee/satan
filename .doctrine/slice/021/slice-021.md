# Replay current_window from the desktop event series

## Context

`IMP-013` (perception signal-model promotion) move 2. ADR-001's premise is
that a percept is a function over durable, time-addressable series ("class
A"). `:current_window` is the last class-B key in the evidence window:
`satan-memory-evidence-assemble-with-bounds` reads the live
`current/desktop.json` and judges freshness by its mtime against the real
clock. So a percept built for a past window (observer attribution,
replay) carries present-day window state, and staleness conflates "daemon
dead" with "user idle on one window".

Panopticon's compositor runner already writes every focus transition
(`window_focus` / `workspace_focus` / `window_title`) with the full focused
state to `raw/desktop-<date>.jsonl`, plus lifecycle events
(`panopticon/compositor/runner.py`, `_lifecycle`) for connect/disconnect.
`current/desktop.json` is a cache of the last such event.

## Scope & Objectives

Decisions: DEC-034..DEC-040 (all `shapes` SL-021).

- **Replay from raw (DEC-034):** `:current_window` for a window ending at `t`
  = the state keys of the last state-bearing desktop event
  (`snapshot` / `window_focus` / `workspace_focus` / `window_title`) at or
  before `t`, read from `raw/desktop-<date>.jsonl` under the behaviour root.
  Payload keys unchanged (`window_id`, `app_id`, `pid`, `title`, `workspace`,
  `output`) plus `:since` (ts of the deciding event), so canon and tank do not
  move.
- **No fold in SATAN (DEC-036):** fields are taken verbatim from one event;
  full focused state per event is required of panopticon per producer (today
  an implementation property of `diff_state`, not yet in its `schema.md`).
- **Liveness from lifecycle, not age (DEC-035):** no age-based staleness; the
  window is kept however old. A `compositor_disconnected` as the deciding
  event gives `disconnected`.
- **Status vocabulary (DEC-037):** `ok` / `disconnected` / `missing` /
  `malformed`; causes keep `panopticon_current_{missing,malformed}`, add
  `panopticon_current_disconnected`, retire `panopticon_current_stale`;
  hints carry no host literal. `satan-memory-evidence-current-window-stale-seconds`
  retires.
- **Lookback (DEC-038):** the parsed-local-date file of `t`, then the previous
  day; nothing in either → `missing`.
- **Reader (DEC-039):** backward line walk, lenient per line, instants not
  strings; `malformed` = non-empty file with no parseable line.
- **`activity_read` `current` scope (DEC-040):** shares the reader at
  wall-clock now; gains `:status` / `:since`. SATAN stops reading `current/`.
- Tests: fixtures move from `current/desktop.json` to raw day files.

## Non-Goals

- Widening panopticon's projection (window inventory, `urgent`, workspace
  names) — new signal, not promotion (`IMP-013`: "do not bundle it").
- Git status segments and the active-project signal (`IMP-013` move 3,
  `ISS-004`).
- Folding partial-state producer events (sway, future mango) — panopticon's
  contract (DEC-036).
- `ISS-021` for the existing segment/git readers (DEC-038).
- Panopticon changes, incl. disconnect-on-shutdown (DEC-035 follow-up).
- The evidence truncation reducer (`ISS-001`).

## Summary

Affected surface:

| path | change |
|---|---|
| `satan/satan-memory-evidence.el` | replace `--current-window-status` mtime probe with the raw replay reader |
| `satan/satan-sensor-alerts.el` | `:current_window` causes / hints |
| `satan/satan-tools-activity.el` | `current` scope calls the reader |
| `satan/satan-desktop.el` | new reader module |
| `satan/satan-memory-canon.el`, `satan/satan-goad.el` | shared local-date / day-shift helpers lifted into canon; goad and evidence delegate (RV-021 F-10) |
| `satan/protocol/fixtures.json` | retired cause name in sample data |
| `satan/test/satan-memory-evidence-test.el`, `satan-percept-test.el`, `satan-resonance-test.el`, `satan-sensor-alerts-test.el`, `satan-tools-activity-test.el`, `satan-memory-canon-test.el`, `satan-audit-test.el`, `satan-broker-test.el`, new `satan-desktop-{fixture,test}.el` | fixtures + replay cases + sample cause strings |

Risks:

- Residual liveness blind spot (DEC-035): a watcher stopped by SIGTERM with no
  restart, or a hung IPC stream, reads as `ok` with an old `:since`.
- sway (unused) may yield a partial window until its adapter meets the
  full-state contract (DEC-036).
- The full-state rule is unpublished by panopticon (RV-021 F-6): a refactor of
  `diff_state` could break SATAN silently; only the pin test guards it.
- Replay premises (RV-021 F-9): append order = `ts` order (a backward clock
  step breaks replayability within the step) and panopticon/Emacs share a
  local zone (day-file choice).
- DEC-013: compositor `app_id` transiently mislabelled; replay inherits it.
- Observer's `:current_window` becomes historically correct; nothing reads it
  today (research cross-thread 5).

Verification / closure: evidence assembled for a past `[start, end]`
returns the window focused at `end`, not now (VT); a long-idle window stays
`ok` with its `:since`, a trailing disconnect reads `disconnected` (VT);
cross-midnight lookback and torn-last-line tolerance (VT); no remaining read
of `current/desktop.json` and no retired cause name anywhere in `satan/`,
tests included (grep, design sec-5); `just check` green.

## Follow-Ups

- `IMP-013` move 3 (git status + active project) — separate slice.
- Panopticon: emit `compositor_disconnected reason:"shutdown"` on cancel
  (closes DEC-035's SIGTERM hole); sway adapter onto `diff_state` (DEC-036).
  Cross-repo, ungoverned here.
- Panopticon `docs/schema.md` (RV-021 F-6): publish "every state event
  carries the full focused state" per producer (niri, umbriel), replacing the
  sway partial shape as the documented default; correct the claim that a
  `snapshot` immediately follows `compositor_reconnected` (live
  `raw/desktop-2026-09-25.jsonl:338-339` disproves it; reconnected is written
  before the session has connected). Cross-repo, ungoverned here.
