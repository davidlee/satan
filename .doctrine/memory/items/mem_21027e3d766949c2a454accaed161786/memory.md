# SATAN ingest cursor store

# SATAN per-source ingest cursor store

`satan/satan-ingest-cursor.el` — the **evidence-assembly consumption
frontier**, DISTINCT from the per-sensor private probe watermarks
(`sensor-*.json`). Added by [[DE-010]] Phase 2 (DR-010 §3,
DEC-cursor-per-source-intra-day).

## Invariants

- **Per-source**, keyed on the source's native field: `:focus`/`:browser` →
  `end_ts`, `:content` → `captured_at`. **Git EXCLUDED** (git rows key on
  backdatable `%cI`; git keeps its own 24h re-scan window).
- **Intra-day only** — `(cursor, head]` cannot cross midnight (deferred, DR §8).
- Advance = `max(current, head)` per source, **idempotent**, stores the native
  timestamp **verbatim** ([[mem.pattern.satan.sensor-watermark-format]]).
- **Advanced ONLY on the child's first `ready`** (since SL-022 PHASE-03):
  `satan-broker--on-ready` → `satan-broker--commit-frontiers`, once per run
  (the `ready` slot on `satan-run` guards it). It advances to the heads
  **perceive snapshotted** (`satan-ingest-cursor-heads` →
  `:probe_snapshots :ingest`) via `(satan-ingest-cursor-advance HEADS)`, not
  the live heads, so rows landing during the launch are not skipped. A child
  that dies before `ready` (launcher refusal → `spawn_failed`), perceive, and
  all `--write-no-child-run` denial paths NEVER advance (perceive spied by
  VT-perceive-pure). `-advance` with no argument still reads live heads. See
  [[mem.fact.satan.perceive-consume-seam]].
- **Additive / low-risk**: missing/zero/unparseable cursor ⇒ consume-from-head.
- **No positive replay pass** — the cursor advances the frontier + feeds backlog
  depth; it does NOT (this delta) gate what `assemble-with-bounds` reads.

## ⚠ Comparator asymmetry (intentional — do NOT "simplify")

`-advance` compares **content** with `string<` (single UTC-millis-`Z` format) but
**focus/browser** with parsed-instant `time-less-p` (mixed local-offset day-files,
matching `satan-memory-evidence--newest-segment-end`). Collapsing both to one
comparator silently breaks focus/browser advance on mixed-offset rows. Locked by
VT `satan-ingest-cursor/advance-mixed-offset-focus-uses-parsed-instant`.

## API

`-read` / `-get SOURCE` / `-head SOURCE` / `-heads` / `-advance &optional HEADS` / `-backlog-depth`
(→ `(:focus N :browser N :content N :total N)`, emacsclient-callable waybar
surface). State file `~/.local/state/satan/ingest-cursor.json`. Test-fixture +
backlog-depth recipe: [[mem.pattern.satan.ingest-cursor-backlog-depth]].

## DRY note

`-read`/`-write` are the **4th** JSON-plist-state read/write idiom (curiosity,
content, wpm, ingest-cursor). A shared `satan-json-state` helper is a deferred
improvement (extraction touches 3 sensor files — out of DE-010's additive scope).
