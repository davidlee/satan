# Remove bough integration

## Context

Bough has been dormant since ~2026-05 (no active use for two months); its
return is uncertain. SL-001 designed a feature flag to make it absent-when-
disabled; the four-round inquisition there produced a complete, verified map
of every bough seam — and made clear the flag would add machinery (two-view
tool filtering, per-session freeze state) to preserve ~1,000 lines nobody is
exercising. Decision: remove the integration instead (YAGNI). SL-001 is
abandoned; its `design.md` §2/§10 ledger is retained as the authoritative
seam map for this removal and for any future resurrection.

Resurrection path: git history (record the pre-removal SHA in this slice's
notes at close) + the SL-001 ledger.

## Scope & Objectives

Remove the bough integration from SATAN entirely — code, evidence, sensor
signal, alerts, tests.

**Authoritative inventory: `design.md` §2 (seam map), §2.F (durable-state
census), §5.2 (touch-set).** The design (locked 2026-07-18 after an 8-round
codex inquisition, RV-001) corrected and extended the sketch below — it adds
surfaces this list omitted (the SQL grammar artifact, the two-schema
`focal_bough_nanoid` input, `:bough_limit`/`:bough_workspace` opts, `satan-motive.el`,
`satan-percept.el`, living/canon docs, `notified.json` state, tick telemetry)
and fixes the truncation-pass count. The boundary is **bough-specific
derivation/matching (removed) vs content-agnostic substrate (preserved)**: the
persisted grammar (elisp + SQL), the motive admitted-namespace vocabulary, and
the generic retrieval/copy-forward/seed-introduction machinery are **kept**;
legal bough literals therefore stay readable, copy-forwardable, and writable by
generic callers until the grammar-v2 retirement (Follow-Up). Original
SL-001-derived sketch (corrected in the design):

- `satan-tools-bough.el` — delete (361 lines), plus its
  `(satan-tool-register "bough_read")`.
- `satan-memory-evidence.el` — remove the require, the three bough wrappers
  and `--bough-call`, the tracking counters and `--bough-status`, `:bough`
  from sensor_status, the `:bough_recent`/`:bough_active`/`:bough_day`
  evidence fields, `satan-memory-evidence-bough-limit` **and its `:bough_limit`
  opt**, the `:bough_workspace` opt, and truncation passes **1 (bough_day),
  4 (bough_active), and 5 (bough_recent)** — leaving only passes 2 (browser)
  and 3 (focus). Also the `evidence.bough_*` trace-stage wrappers.
- `satan-memory.el` — remove the require.
- `satan-mode.el` — remove `"bough_read"` from the 5 static mode specs.
- `satan-tick.el` — remove `"bough_read"` from the `satan-tick-register`
  defaults (tick-pulse, tick-agent).
- `satan-sensor-alerts.el` — remove `:bough` from `--source-order` and
  `--source-label`, the `bough_unreachable` cause derivation, and the bough
  streak state.
- `satan-memory-canon.el` — remove the `bough.recent_status_change` and
  `bough.active_focus` rules.
- `satan-observer-classify.el` — remove `--predicate-bough-event-match` and
  its wiring.
- `satan-tank.el` — remove the `bough_active` render line and
  `--render-bough-active`.
- `harness/runloop.py` — remove `bough_read` from the tier-2 drop set (and
  its fixture reference in `test_gptel_harness.py`).
- Tests — delete `satan-tools-bough-test.el`; prune bough cases/fixtures
  from the ~17 other test files that reference bough (largest: observer,
  evidence, canon, sensor-alerts).
- Docs — `docs/memory/design.md` and any other in-repo prose describing
  bough evidence/sensors: mark removed. Mark
  `docs/bough-feature-flag-brief.md` superseded.

All suites green after each phase; `satan-mode-check-tool-references` and
the MCP description preflight pass with the tool gone.

## Non-Goals

- The external bough tool/service itself — untouched; only SATAN's
  integration goes.
- The hard-cap final reducer (ISS-001) — independent; note that removing bough
  truncation passes 1/4/5 leaves passes **2–3** only (browser, focus), which
  *narrows* the already-unenforced hard-cap chain further (the pass-5 "last
  resort" vanishes entirely). This slice reconciles the **five** false
  "mandatory hard-cap" doc surfaces (design §5.5/D3); ISS-001's body is updated
  to the post-removal inventory when this lands — **not closed**.
- **Retiring the bough grammar vocabulary** (elisp + SQL closed-world schema) and
  scrubbing residual bough literals from persisted stores — a grammar-v2 + data
  migration, out of scope here; tracked as the Follow-Up. This slice preserves
  the schema and leaves historical bough data readable/propagatable.
- The `bough_read` tool description file under `satan-tools-descriptions-dir`
  (`~/notes`, outside this repo) — flag for manual cleanup in the close
  notes.
- No resurrection scaffolding (no stubs, no commented-out code, no flag).

## Summary

## Follow-Ups

- **Complete bough retirement (grammar-v2 + data migration)** — design OQ-3.
  Retire the dormant bough vocabulary (elisp `satan-memory-grammar.el` + SQL
  `0002_grammar_v1.sql`) by rejecting `bough_*` at grammar admission, and
  disposition every residual store: scrub persisted traces (incl.
  `metadata_json`), motives, interventions, attributes, `satan_patterns` + the
  `patterns.eld` source; retention/whole-run expiry for the per-run audit bundle
  and tick telemetry. File as a backlog item (`DOCTRINE_RESERVATION_FALLBACK=1`),
  related-to SL-002.
