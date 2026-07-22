# SATAN ingest cursor store

# SATAN per-source ingest cursor store

`satan/dl-satan-ingest-cursor.el` — the **evidence-assembly consumption
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
- **Advanced ONLY in `dl-satan-broker--spawn` on a successful run**
  (`-advance`, broker.el ~:859). perceive + all `--write-no-child-run` denial
  paths NEVER advance (spied by VT-perceive-pure). See
  [[mem.fact.satan.perceive-consume-seam]].
- **Additive / low-risk**: missing/zero/unparseable cursor ⇒ consume-from-head.
- **No positive replay pass** — the cursor advances the frontier + feeds backlog
  depth; it does NOT (this delta) gate what `assemble-with-bounds` reads.

## ⚠ Comparator asymmetry (intentional — do NOT "simplify")

`-advance` compares **content** with `string<` (single UTC-millis-`Z` format) but
**focus/browser** with parsed-instant `time-less-p` (mixed local-offset day-files,
matching `dl-satan-memory-evidence--newest-segment-end`). Collapsing both to one
comparator silently breaks focus/browser advance on mixed-offset rows. Locked by
VT `dl-satan-ingest-cursor/advance-mixed-offset-focus-uses-parsed-instant`.

## API

`-read` / `-get SOURCE` / `-head SOURCE` / `-advance` / `-backlog-depth`
(→ `(:focus N :browser N :content N :total N)`, emacsclient-callable waybar
surface). State file `~/.local/state/satan/ingest-cursor.json`. Test-fixture +
backlog-depth recipe: [[mem.pattern.satan.ingest-cursor-backlog-depth]].

## DRY note

`-read`/`-write` are the **4th** JSON-plist-state read/write idiom (curiosity,
content, wpm, ingest-cursor). A shared `dl-satan-json-state` helper is a deferred
improvement (extraction touches 3 sensor files — out of DE-010's additive scope).
