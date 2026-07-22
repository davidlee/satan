# Notes SL-002: Remove bough integration

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## 2026-07-18 — Design inquisition

- Completed source-backed design review as RV-001: 8 terminal findings
  (3 blocker, 5 major); verdict is unsound to lock pending design
  reconciliation. The RV synthesis owns the detailed evidence and sentencing.
- Review cache/selector conformance remains unavailable because SL-002 declares
  no selectors; this is recorded as RV-001 F-8.
- Review-ledger and slice-note changes are uncommitted. No product source or
  accused design file was modified, and no code verification gate was run
  because this was a review-only task.

## 2026-07-22 — Plan authored

- Six phases (`plan.toml`); sequencing rationale in `plan.md`. Two orderings
  are forced, not stylistic: evidence (PHASE-02) precedes the tool-file
  deletion (PHASE-03) because `satan-memory-evidence.el:41` requires
  `satan-tools-bough`; and the tool surface is atomic because
  `satan-mode-check-tool-references` only passes with the tool unregistered
  *and* absent from every mode list.
- Boundary pins go first (PHASE-01), green-before / green-after. The risk here
  is not that removal breaks — it is that removal quietly takes preserved
  substrate with it and nothing notices, because bough data is dormant.

### Resurrection path

- **Pre-removal SHA: `74f82e057c823da344eb7f95e6a7ef5e5c337fc8`** (`74f82e0`,
  "governance: accept ADR-017 + ADR-018, amend POL-001 seat lists"). This is
  the last commit with the bough integration fully intact.
- Plus the SL-001 `design.md` §2/§10 ledger, retained as the authoritative seam
  map (slice §Context).

## 2026-07-22 — PHASE-01 complete (boundary pins)

Ten new pins, all green **with bough present**; no production file touched.
Suite: 1045 tests, 0 unexpected, 16 skipped (was 1035/0/16).

| Pin | File | Pins |
|---|---|---|
| `sync-admits-caller-supplied-bough-handle` | `satan-pattern-test.el` | fresh-introduction surface 1 — pattern sync admits a grammatical `bough_*` |
| `outcome-payload-forwards-bough-cue-handles` | `satan-attribute-test.el` | attribute outcome forwarding copies handles verbatim |
| `replace-admits-caller-supplied-bough-cue` | `satan-tools-motive-test.el` | fresh-introduction surface 2 — `motive_replace` |
| `historical-bough-trace-readable-all-paths` | `satan-memory-store-test.el` | RN-1 — all three preserved read paths in one test |
| `mark-admits-caller-supplied-bough-handle` | `satan-memory-store-test.el` | fresh-introduction surface 3 — `memory-store-mark` |
| `rank-mixed-bough-motive-fires-on-non-bough-overlap` | `satan-observer-test.el` | RN-2 (a) |
| `rank-bough-only-motive-dormant-without-bough-percept` | `satan-observer-test.el` | RN-2 (b) negative half |
| `rank-bough-only-motive-fires-on-historical-percept` | `satan-observer-test.el` | RN-2/RN-7 (b) positive half — the case round 0 got wrong |
| `bough-only-cue-stays-admittable` | `satan-motive-test.el` | D4 — preserved vocabulary |
| `audit-records-explicit-bough-cue-handles-verbatim` | `satan-broker-test.el` | fresh-introduction surface 5 — broker tool-call audit |

Surface 4 (`intervention-create` audit + projection) was already pinned at
`satan-intervention-test.el:410`; it and the other §2.D PRESERVE/ADD sites
(`satan-audit-intervention-test.el`, `satan-tools-atsatan-test.el:318/407/455`,
`satan-memory-grammar-test.el:74`, the counter-memory writer) now carry an
in-file `PRESERVED-BOUNDARY PIN — SL-002` comment naming why the bough token is
there. That is EX-3: a later pruning pass must not be able to mistake them for
integration residue.

Two small findings:

- The `satan_patterns` table stores cue handles as `cue_handles_json` (jsonb),
  not a `text[]` — the pin queries via `jsonb_array_elements_text`.
- `satan-jsonl-read-file` returns JSON arrays as **lists**, so the broker audit
  pin normalises with `append` before comparing (the arity trap again).

## 2026-07-22 — PHASE-02 complete (evidence layer)

`satan-memory-evidence.el` is at **zero** bough tokens. Suite 1036/0 unexpected
(11 bough tests removed, 2 added).

Removed: the `(require 'satan-tools-bough)`, `--bough-call`, the three read
wrappers, `--bough-tracking`/`--bough-attempts`/`--bough-ok`, `--bough-status`,
the `:bough` sensor_status key, the three evidence fields, the
`satan-memory-evidence-bough-limit` defcustom with its `:bough_limit` opt, the
`:bough_workspace` opt, truncation passes 1/4/5, and the three
`evidence.bough_*` trace-stage wrappers.

Two things the design's touch-set did not name, both forced:

- **`--flatten-tree` went too.** Its only caller was `--bough-active`. Its two
  unit tests went with it.
- **`--shrink-annotations` went too.** Its only caller was pass 4.

Judgement calls worth flagging at audit:

- **`--truncate` keeps its `hard-cap` parameter, now unused** (`_hard-cap`).
  Both surviving passes are target-gated, so nothing reads it. Deleting the
  parameter would change the call signature and leave ISS-001 nowhere to
  attach; the docstring says so explicitly rather than leaving a mystery arg.
- **Pass numbering is frozen, not compacted.** Passes 2 and 3 keep their
  original labels so `:truncated_at` strings stay comparable across the
  removal. The docstring records that 1/4/5 were removed.
- **The new VT-2 test asserts the object stays oversized** once the passes are
  exhausted. That is the honest post-removal behaviour and the thing ISS-001
  exists to fix; asserting a byte bound here would encode a guarantee that has
  never held.

Hard-cap wording surfaces (1) header `:budget_hard_cap_bytes`, (2) the
`budget-hard-cap` defcustom doc and (3) the `--truncate` docstring now say
last-resort / best-effort and name ISS-001. Surfaces (4) and (5) are docs —
PHASE-06.

## 2026-07-22 — PHASE-03 complete (tool surface)

`bough_read` no longer exists. Suite 1015/0 unexpected, 13 skipped (the three
`satan-bough/*` skips left with the test file). Harness: 52 tests OK.

- `satan/satan-tools-bough.el` (361 lines) and
  `satan/test/satan-tools-bough-test.el` (279) deleted.
- `satan-memory.el` require + docstring; `satan-mode.el` 5 specs;
  `satan-tick.el` tick-pulse + tick-agent; `runloop.py` tier-2 entry;
  `test_gptel_harness.py` fixture and its assertion.
- `satan-broker-test.el`: require, two manifest description fixtures, three
  prose comments. Its PHASE-01 audit pin stays.

VT-1 `(satan-mode-check-tool-references)` → nil. VA-4 holds: `satan-mode-test.el`
and `satan-mcp-test.el` are untouched and green.

VT-2's manifest half cannot run here — tool descriptions live under
`satan-tools-descriptions-dir` in `~/notes`, outside the repo, and the
corpus-integration tests `skip-unless` it is present. `satan-mcp-test` green
unmodified is the available evidence; the external `bough_read.md` still needs
the manual cleanup already flagged for close.

## 2026-07-22 — PHASE-04 complete (sensor, tank, persisted state)

Suite 1017/0 unexpected. Eight production modules still hold a bough token, all
PHASE-05's.

**The RN-17 prune was implemented generically, and that was forced.** The design
says "prune the `:streaks.bough_unreachable` + `:causes.bough_unreachable` keys
on state read" — but writing those literals into `satan-sensor-alerts.el` would
put a bough token in a production file and break §9's zero-token gate, whose
allowlist is exactly the grammar artifacts plus the one motive occurrence. The
inquisition did not catch the collision between its own RN-17 remedy and its own
R1 gate.

Resolution: `--prune-state` drops any `:causes` key **outside the currently
derivable set** (derived from `--causes`, not transcribed), and drops `:streaks`
wholesale — no cause uses a streak threshold now that the bough one is gone. It
names no retired cause, so it satisfies the gate, and it self-heals for the next
retirement instead of accumulating a list of ghosts. Strictly better than the
literal prune, and smaller.

Consequences worth flagging at audit:

- **`--streak` / `--set-streak` deleted**, not just their caller. The bough
  streak was the only user; `:streaks` is a retired slot.
- **`satan-sensor-alerts-bough-streak-threshold` defcustom gone.** Any user
  customisation of it is now inert — acceptable, it gated a tool that no longer
  exists.
- A `:bough` key surviving in a persisted `sensor_status` is now simply not
  rendered rather than erroring, because `--source-order` no longer names it.
  Pinned by `no-bough-segment-in-sensor-line`.

### Census at plan time (2026-07-22)

Live bough token counts, for divergence detection at audit — 67 files. Largest:
`satan-tools-bough.el` 108, `docs/memory/design.md` 95,
`satan-tools-bough-test.el` 93, `satan-memory-evidence.el` 70,
`satan-memory-evidence-test.el` 65. The design's touch-set covers all of them;
two fixture files (`test/canon-fixtures/rich_window.json` 8,
`minimal_firefox.json` 1) are not named as selectors but fall under §2.D
classification — disposition them at PHASE-05.
