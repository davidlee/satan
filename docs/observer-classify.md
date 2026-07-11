# Observer Classify — Verdict Semantics

Reference for `dl-satan-observer-classify` (§S5, outcome-semantics §2).

## Verdict plist shape

```elisp
(:classification :worked | :ignored | :neutral | :unknown
 :confidence     :low | :medium | :high
 :predicates     (KEYWORD ...)   ; which P fired; nil when none
 :reason         KEYWORD or nil  ; why :unknown, when applicable
 :evidence       PLIST           ; present on :ignored / :neutral;
                                 ; absent on :worked / :unknown
 :maturity       :pending | :mature)
```

## Confidence derivation (§4)

- 1 predicate fires → `:medium`
- ≥2 fire → `:high`
- none → `:low` (always paired with `:unknown` / `:ignored` / `:neutral`)

## NOW parameter and maturity lifecycle (T1.5b PR 3, §3, §6.1/§6.2)

Optional NOW is the broker's frozen `:time_now` ISO string.

| NOW value | maturity result | behaviour |
|-----------|----------------|-----------|
| nil | `:mature` | maturity check skipped; test-fixture convenience — direct callers in ert don't need to thread NOW |
| present → `:pending` | `:pending` | returns `(:classification :unknown :confidence :low :predicates nil :reason :pending :maturity :pending)` without consulting predicates (§2 invariant 3) |
| present → `:stale` | — | returns nil; caller skips persist (§3, §6.3 — auto re-pass forbidden past stale cutoff). `dl-satan-intervention-pending` excludes stale rows in SQL, so this branch should be reachable only when the SQL window and the elisp `maturity-state` disagree. **It did, for months** — `psql -A` dumps `timestamptz` as the space-separated `YYYY-MM-DD HH:MM:SS+00` form, which `date-to-time` mis-parsed ~1.5 days into the past, so every in-window intervention read `:stale` here and was skipped (the cold outcome pipeline). Closed 2026-05-29 by normalizing the cell at the DB-row boundary (`dl-satan-intervention--normalize-pg-timestamp`); this branch is now genuinely defence-in-depth. |
| present → `:mature` | `:mature` | existing flow below |

## Guard order (`:mature` / NOW-nil)

1. **A14** — MOTIVE marked `:dormant` → `:unknown :motive_dormant`
2. **Window crosses calendar-day boundary** → `:crosses_midnight`
   (v0 punts cross-day per §S5 watch-out — `assemble-with-bounds` would read tomorrow's panopticon segment file)
3. **Baseline absent** (budget-denied / pre_spawn-denied runs lack `bundle.json`) → `:no_baseline`
4. **Run predicates P1–P4**; ≥1 fires → `:worked` + firers list
5. **None fire** → `dl-satan-observer-classify-negative` →
   - `:ignored` (user-facing kind)
   - `:neutral` (non-user-facing)
   - `:unknown :low :reason nil` when intervention is user-facing AND ≥1 focus segment starts after emit ts (per outcome-semantics §1)

## Scope and invariants

- Single-motive only; multi-motive correlation (overlap-count + file-order tiebreak) lands in Phase 5.7. Callers iterate motives and combine themselves.
- Final verdict passes through `dl-satan-observer--assert-auto-classification` so auto callers can never construct `:harmful` / `:contradicted` (manual-only per §2 invariants 1 + 2).
