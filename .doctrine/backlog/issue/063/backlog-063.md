# ISS-063: Pattern layer is write-only: patterns.eld is never synced in production and no code reads satan_pattern_stats

## Observed (2026-11-06)

- `satan-pattern-sync` has **no production caller** anywhere in `satan/`. The only
  way `satan_patterns` is ever populated is a hand-run `M-x`.
- `satan-pattern-stats` and `satan-pattern-scars` have no callers outside
  `satan/test/`.
- No tool exposes patterns to the model (`satan-tools-*.el` has no pattern tool),
  and nothing in `satan-context`, `satan-resonance` or `satan-attribute*` reads
  them.
- The only production reference to the subsystem is the observer's guarded rebuild
  (`satan-observer.el:485-495`).

Consequences: `satan_patterns` is empty on a live install unless someone typed the
sync, so `satan_pattern_outcomes` (a containment join against `satan_patterns`,
`0007_patterns.sql:73-100`) cannot match anything, and `satan_pattern_stats` renders
a table nothing reads. The three curated patterns in `satan/patterns.eld` have no
behaviour attached to them at all.

## Why it matters

`docs/epistemics-roadmap.md` treats DE-009 as the step that unblocks Suspicion
semantics and the hypothesis board, and a discarded tick-gate card treated "pattern
coverage" as data worth gating on. Both assume the layer is live. It is inert, so
measuring its coverage today measures nothing — IMP-063 computes the near-miss
numbers anyway precisely because that computation needs no DB rows.

## Decide

- **Wire it**: sync at boot (or a `just` target) from `satan-pattern-file`; surface
  `satan-pattern-stats` / `-scars` somewhere that changes behaviour — the tick
  capsule, an existing memory tool, or the attribute layer's Suspicion source; and
  settle whether `:enabled` and `:intrusion_ceiling` gain enforcement.
- **Retire it**: delete the layer and `patterns.eld` under POL-001's earns-the-seat
  test, and retract the roadmap's claim.

Recommendation: wire — `docs/epistemics-roadmap.md`'s sequencing argument is sound —
but that is a slice with a design, not a chore. Two live defects bite the moment it
is wired: ISS-025 (the psql row splitter drops rows containing `|`) and ISS-059
(tests read the gitignored `satan/patterns.eld`).
