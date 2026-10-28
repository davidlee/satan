# IMP-059: activity_read exposes per-window typing from panopticon keyrate_window

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-10-28 from a panopticon handover (panopticon IMP-006, commit
`1b05315`). Contract: `~/dev/panopticon/docs/schema.md` § Keyrate events
(`keyrate_window`) and § Histograms (`typing_per_app`). Related: IMP-055
(keyrate presence, which this builds on).

## Goal

`activity_read` answers "how long was I typing in emacs today, in which
buffer, how fast", in a form the model reads correctly.

## Data

- `keyrate_window` rows in `raw/keyrate-DAY.jsonl`: one per (minute, focused
  window), same `ts` as that minute's `keyrate_minute`; `app_id`, `title`
  (spinners stripped, or null), `keys`, `key_seconds`.
- **Trap:** a second can hold keys in two windows, so window `key_seconds`
  never sum to the minute's. Minute totals and presence stay on
  `keyrate_minute`; window rows feed only the typing figures.

## Design sketch (agreed with the user 2026-10-28)

Decisions:

- **D1 `today` source = raw rows.** `today` computes typing from the day's
  `keyrate_window` rows (current), and drops `typing_per_app` from the
  pass-through histogram so the model sees one figure, not a lagging second.
- **D2 segments: app total by default, titles opt-in.** Each `recent_focus`
  focus segment carries `typing` = keys, key_seconds, wpm of window rows with
  its `app_id` overlapping it (prorated as presence is). New optional boolean
  arg `titles`: when true, segment `typing` also lists titles. Gaps carry no
  typing (no app). `recent_browser` unchanged (its segments carry no
  `app_id`; tab titles are already there).
- **D3 `current`:** `typing` per app with titles over the last
  `satan-keyrate-window-minutes`.
- **D4 titles verbatim, top 5 per app by keys, rest folded into one
  `(other)` entry**; null title → `(untitled)` (panopticon's key). Titles are
  a list of objects, not map keys. `today` and `current` always include
  titles (fixed, small cost); segments only with `titles: true` (cost grows
  with `limit`: est. ~1.2k → ~2–4k tokens at limit 20).
- **D5 `titles` is harmless where unused.** Declared on the tool schema, so
  validation accepts it on every scope; scopes that always or never list
  titles ignore it.
- **D6 wpm** = (keys ÷ 5) per minute of `key_seconds`: rate while typing, not
  over focus time; nil when key_seconds is 0. One decimal.

Shape:

```
typing: [{app_id, keys, key_seconds, wpm,
          titles?: [{title, keys, key_seconds, wpm}, …≤5, {title:"(other)",…}]}]
```
apps sorted by keys, descending. Segment `typing` is the one app object.

Mechanism (one reader, no parallel path):

- `satan-keyrate--scan-file` takes the event name; `satan-keyrate-read` /
  `-read-day` keep reading `keyrate_minute`; `satan-keyrate-read-windows`
  reads `keyrate_window` through the same path.
- Pure `satan-keyrate-typing (windows from to &optional cap)` → the list
  above; shares the proration with `satan-keyrate-describe`.

Privacy: per-title typing widens the SATAN.md open thread "current-scope
title leak"; the user accepted verbatim top-5 titles (2026-10-28).

## Done means

- Behaviour tests on `keyrate_window` fixtures, incl. a minute split across
  two windows and a minute with no window.
- Byte-compile clean; `just check` green.
- `~/satan-corpus/tools/activity_read.md` and `docs/data-collection.md`
  updated.

## Outcome (2026-10-28)

Built as sketched, TDD.

- `satan-keyrate.el`: `satan-keyrate-read` / `-read-day` take an optional
  event (`satan-keyrate-minute-event` default, `satan-keyrate-window-event`);
  one scan path. Pure `satan-keyrate-typing (windows titles &optional from
  to)`; proration shared with `satan-keyrate-describe` via
  `satan-keyrate--share`. `satan-keyrate-title-cap` (default 5).
- `satan-tools-activity.el`: `today` → `:typing` from raw, histogram minus
  `typing_per_app`; `recent_focus` → per focus segment `:typing` (titles
  with `titles: t`); `current` → `:typing` over the presence window.
  `titles` declared as an optional boolean on the tool schema.
- Typing is omitted from a segment with none; an empty list at day / now
  level means no window rows. Until panopticon is redeployed every typing
  list is empty — expected, not a fault.
- Tests: `satan-keyrate-test.el` (window reader, split minute, title cap
  and fold, proration, no windows), `satan-tools-activity-test.el` (each
  scope, minute with no window, `titles` on every scope).
- Docs: `docs/data-collection.md` §3.2 / §6 / §7;
  `~/satan-corpus/tools/activity_read.md` (wpm and key_seconds semantics).

Open: verify against live rows once `~/flakes` bumps panopticon and
`panopticon-keyrate` restarts. The new `today`/`current` tests use
wall-clock `ago` stamps in the +10:00 fixture zone, so they share ISS-061's
00:00–01:00 AEDT window.
