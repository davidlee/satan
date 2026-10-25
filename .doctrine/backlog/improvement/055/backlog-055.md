# IMP-055: WPM sensor reads panopticon raw/keyrate-*; reading state; then close panopticon IMP-005

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-10-26. Handover from panopticon IMP-005
(`~/dev/panopticon`, `doctrine backlog show IMP-005` there): read that first.
It holds the design sketch, the decisions taken while building, and the
three-step cutover this item is step 2 of.

## State at handover

- **Step 1 done and deployed** (panopticon `4580f88`, `fd905a4`; `~/flakes`
  `6c07bec8`). `panopticon-keyrate.service` replaced `wpm-daemon.service`.
  It reads every keyboard and pointer through evdev and writes, per minute
  with any activity:
  - `~/.local/state/behaviour/raw/keyrate-YYYY-MM-DD.jsonl`, schema-v1 events
    `keyrate_minute`: `ts` (minute start, local offset, ms, e.g.
    `2026-10-26T06:31:00.000+11:00`), `keys`, `key_seconds`,
    `pointer_seconds`, `peak_5s_cpm`. Spec: panopticon `docs/schema.md`
    § Keyrate events.
  - the legacy TSV this sensor reads today
    (`~/.local/state/satan/log/wpm/YYYY-MM-DD.tsv`, same four columns), so
    nothing is broken in the meantime.
- Behaviour change already live: modifiers are no longer counted. Measured
  side by side over four full minutes: `keys` 4–18% lower, `active_seconds`
  (= `key_seconds`) within 2 s/min, peak WPM equal. Classification
  (`active_seconds` sum over 10 min) should not shift.
- Also live: a 1 Hz feed on `$XDG_RUNTIME_DIR/panopticon/keyrate.sock`
  (`cpm_5s`, `cpm_60s`, `pointer_seconds_60s`, `devices`). Not for the
  sensor; for a status bar.

## This item (step 2)

1. **Switch the source.** `satan/satan-sensor-wpm.el` reads
   `raw/keyrate-*.jsonl` instead of the TSV: sum `key_seconds` where it sums
   `active_seconds` today; add `pointer_seconds`. Thresholds unchanged.
   Log dir becomes panopticon's state root (`$XDG_STATE_HOME/behaviour/raw`).
2. **Add a reading state.** Today `typing_idle` conflates reading, thinking
   and away (design-contract line ~433 says so). With `pointer_seconds`:
   few keys + pointer activity = reading; neither = away. Whether this is a
   new reason (e.g. `reading`) or a split of `typing_idle` is a SATAN design
   call. A new reason touches:
   - `docs/attributes/design-contract.md` §6S (reason table + delta table),
   - `satan/satan-audit.el:449` reason allowlist (+ its test,
     `satan/test/satan-audit-attribute-test.el:373`),
   - attrd's reason validation (cf. ISS-011, attrd rejecting an unknown
     reason),
   - `docs/attributes/wiring-status.md`.
3. **Tests** for the new parser and classification (fixture JSONL).

## Gotchas

- **Timestamp format differs.** The TSV `ts` is naive local
  (`2026-10-26T06:31:00`); raw `ts` carries ms and an offset. The current
  cutoff is a string compare against `%Y-%m-%dT%T`; it happens to order
  correctly for same-offset strings but breaks across a DST change. Parse,
  don't string-compare (same trap as ISS-035).
- **Day boundary.** The sensor reads only today's file, so just after
  midnight the 10-minute window loses yesterday's rows. Pre-existing;
  the raw files are also per local day, so the same holds. Fix or keep
  knowingly.
- **Quiet minutes are absent**, in both formats: missing minute = zero.
- **Partial minutes** after a daemon restart undercount that one minute.

## Then: close panopticon IMP-005 (step 3)

Once this has shipped and the sensor runs off the raw stream:

- panopticon: remove the legacy TSV writer (`legacy_tsv` in
  `panopticon/keyrate/render.py`, the `legacy_dir` path in
  `panopticon/keyrate/__main__.py`, `--legacy-dir` / `--no-legacy`, their
  tests, the README / `docs/privacy.md` mentions); `just check`; commit
  `refactor(IMP-005): …`; push.
- `~/flakes`: in `features/compositor/sway.nix` remove `wpm-archive`
  (service + timer), `wpmPython`, `wpmScript`, `wpmArchiveYesterday` and the
  `home.packages` entry, and the IMP-005 comment; drop the "writes its TSV"
  comment in `features/attention/behaviour.nix`. Then
  `~/dev/panopticon/bin/reload-hm`.
- Delete `~/.config/waybar/wpm-status.py`. Old TSVs under
  `satan/log/wpm/` can stay as history or go — ask.
- Close IMP-005 in panopticon (`doctrine backlog edit` / status), and this
  item here.

Not in scope: panopticon RSK-002 (user in the `input` group), which stays
open on its own.
