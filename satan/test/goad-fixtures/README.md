# goad fixtures

Golden output of goad's `backend.py` (corpus repo `~/satan`, `goad/`) for a
fixed script of SATAN asks. SATAN's tests read these files so that they test
against the producer's own bytes, never a hand-built value (SL-016 design
sec-8; the ISS-014 lesson).

**Never hand-edit these files. Regenerate them:**

```
cd ~/satan/goad && just goldens /home/david/dev/satan/satan/test/goad-fixtures
```

`just goldens` runs `goad/goldens.py`, which drives `backend.run` (the code
path `main()` wraps) with fixed instants, then copies `queue.json` and
`data/*.json` here. SL-016 PHASE-08 (VT-43) re-derives them.

## Provenance

| | |
|---|---|
| corpus commit | `e896597` |
| `goad/backend.py` sha256 | `3359a7582d30cc1b1027084203c37f4a63648c66d5ef3b2f03b616a946998c7c` |
| `goad/goldens.py` sha256 | `2fe0f542fc01bd7100f0e6589b3e9e1284d14341089500d0c811b5eff6e1839c` |
| `queue.json` sha256 | `83be191d4e6021a8a60ca743390080891908c142b46ec67a32bf323b5f4450ef` |
| `data/2026-09-23.json` sha256 | `627277ddd4564abf49b48cabc669d60fa82053fa1d105861c360732ec2a7aee3` |

Same `backend.py` and `goldens.py` bytes give the same output bytes.

## Files

- `queue.json` — the queue as of the script's last step: all eight asks, in
  emit order, expired ones included (SATAN had not retired them). One of them
  (`form`) carries an answer form. The schema is goad's `README.md`, "SATAN
  asks".
- `data/2026-09-23.json` — the only day file the script produces. Every ask
  event, including the answer given at 00:05 on the 24th, is filed under its
  emit date, so there is no `2026-09-24.json`.

## Scenario

All times 2026-09-23, `+10:00`, unless marked. Script stamps carry
microseconds, as `datetime.now()` gives them.

| outcome | `intervention_id` | emitted → expires | script | record left in `2026-09-23.json` |
|---|---|---|---|---|
| expired | `20260923T080000-tick-pulse-7b2e90.iv001` | 08:00 → 09:00 | never rendered | **absent** from every day file |
| answered | `20260923T093000-tick-pulse-a3f01c.iv001` | 09:30 → 10:30 | evaluate 09:31 (presented); `opt:yes:ask:` 09:32 | `presented_at`, `value: {option: "yes", values: {}}`, `at` |
| later | `20260923T093000-tick-pulse-a3f01c.iv002` | 09:30 → 10:30 | rendered after the answer (presented 09:32); `later:ask:` 09:33 | `presented_at`, `deferred_at`, `deferred_by: "later"` |
| enough-seen | `20260923T093000-tick-pulse-a3f01c.iv003` | 09:30 → 10:30 | rendered after Later (presented 09:33); `enough:` 09:34 | `presented_at`, `deferred_at`, `deferred_by: "enough"` |
| enough-unseen | `20260923T093000-tick-pulse-a3f01c.iv004` | 09:30 → 10:30 | behind enough-seen at 09:34 | `deferred_at`, `deferred_by: "enough"`, **no** `presented_at` |
| untouched | `20260923T111000-tick-pulse-c41d5e.iv001` | 11:10 → 12:10 | evaluate 11:15 (presented), nothing more | `presented_at` only |
| form | `20260923T130000-tick-pulse-d82c4f.iv001` | 13:00 → 14:00 | evaluate 13:01 (presented; `untouched` already expired at 12:10); `opt:rate:ask:` 13:02 with one value of each field kind | `presented_at`, `value: {option: "rate", values: {energy, blocker, note, walked, back_at}}`, `at` |
| midnight | `20260923T231500-tick-pulse-e90f27.iv001` | 23:15 → 00:15 (24th) | evaluate 23:16; `opt:yes:ask:` 00:05 on the 24th; evaluate 00:10 (not re-rendered) | `presented_at`, `value: {option: "yes", values: {}}`, `at` (on the 24th) |

The Enough at 09:34 also deferred all fourteen checklist items in the same
file's `items`, with `deferred_by: "enough"`. That is real output; keep it.
