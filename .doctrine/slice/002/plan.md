# Implementation Plan SL-002: Remove bough integration

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Cite entities by padded id (SL-020, REQ-059); phases as PHASE-01,
     criteria as EN-1/EX-1/VT-1/VA-1/VH-1. See .doctrine/glossary.md § reference forms. -->

## Overview

Six phases. The design (locked 2026-07-18, RV-001, 8 rounds) already did the
hard thinking: §2 is the seam map, §2.F the durable-state census, §5.2 the
touch-set, §9 the validation contract. This plan adds only sequencing — which
seam must fall before which, and where the safety net goes.

The removal is a **cascade, not a minefield** (§2.E): every reader is
absent-key / nil-safe, verified under SL-001. That is what lets each phase end
green rather than requiring a big-bang cutover.

## Sequencing & Rationale

**Why pins first (PHASE-01).** The load-bearing decision (D1) is a boundary:
bough-specific *derivation* goes, content-agnostic *substrate* stays. The risk
is not that removal breaks — it is that removal quietly takes some of the
substrate with it, and nothing notices because bough data is dormant. So the
§9 preserved-substrate assertions are written **while bough still works**, green
before the first deletion and green after the last. They are characterization
tests: their value is that they never go red.

This inverts the usual red/green order for one phase, deliberately. The
removal-asserting tests stay red-then-green in their own phases.

**Why evidence before the tool file (PHASE-02 → PHASE-03).**
`satan-memory-evidence.el:41` holds `(require 'satan-tools-bough)`. Deleting the
tool file first would break evidence assembly mid-slice and force the phase to
end red. Evidence is also the deepest seam — three reads, a call wrapper, a
status synth, three output fields, two opts and three truncation passes — so
doing it first gets the hardest work done against a fully green tree.

The three in-file hard-cap wording surfaces ride along in PHASE-02 rather than
waiting for the doc phase, because passes 1/4/5 leave in that same edit and the
wording is only false *after* they go.

**Why the tool surface is atomic (PHASE-03).**
`satan-mode-check-tool-references` passes only when the tool is unregistered
*and* absent from every mode list. Splitting the file deletion from the mode
specs would leave a phase that cannot end green. The tick defaults and the
harness tier set join it for the same reason.

**Why sensor state is its own phase (PHASE-04).** `notified.json` is the only
**active** bough-specific durable state in the census — everything else is
append-only telemetry, a run audit bundle, or a content-agnostic handle store
(§2.F). It needs a one-time read-path prune rather than a code deletion, and it
is the one place this slice mutates persisted state. Isolating it keeps that
fact legible in the history.

**Why derivation ends in PHASE-05.** After canon rules, the observer predicate
and the `focal_bough_nanoid` producer input are gone, no bough handle can be
*derived* anywhere. That is the slice's actual invariant. It is deliberately
weaker than "no bough handle exists": historical handles still propagate by
copy-forward, which is correct for a preserved vocabulary and is what OQ-3
closes.

**Why gates come last (PHASE-06).** The zero-token gate and the grammar no-diff
check can only pass at the end. They are what turn "we removed it" from an
assertion into a checkable fact, and — more usefully — into a standing guard:
the substrate files carry no bough token today, so a future accidental bough
branch there fails the gate.

## Notes

- **Preserved on purpose, and it will look like an oversight.** Three things
  survive that a reviewer will reach for: the grammar (elisp + SQL) whole,
  `satan-motive--admitted-namespaces` (D4 — removing it would flip persisted
  bough-only motives to dormant and reject future writes), and the five
  fresh-introduction surfaces that still accept a caller-supplied `bough_*`
  literal. Each is pinned by a test that says so.
- **Not closed by this slice.** ISS-001 (the hard-cap reducer) — its body is
  updated to passes 2–3, not closed. OQ-3 (grammar-v2 + data migration) — filed
  as a backlog item. The external description file under `~/notes` — manual,
  flagged at close.
- **`docs/attributes/outcome-semantics.md` is `authority: blocking`** and is not
  edited. Its bough cue example stays semantically valid under the preserved
  vocabulary. Resist the tidying instinct.
- **Resurrection path** is git history (pre-removal SHA in `notes.md`) plus the
  SL-001 §2/§10 ledger. No stubs, no commented-out code, no flag.
