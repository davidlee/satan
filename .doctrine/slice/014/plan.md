# Implementation Plan SL-014: Stand up the ADR-017 §3 authority ledger

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Cite entities by padded id (SL-020, REQ-059); phases as PHASE-01,
     criteria as EN-1/EX-1/VT-1/VA-1/VH-1. See .doctrine/glossary.md § reference forms. -->

## Overview

SL-014 stands up the ADR-017 §3 authority ledger (RFC-017 gate G2). The design
(design.md) locked three questions: home/format (linked markdown companion in the
ADR-017 bundle, DEC-003), grain (one row per independently-ownable duty), and
owner vocabulary (fixed legend tokens). What remains is authoring one artifact and
a one-sentence pointer edit. That is a **single phase**.

## Sequencing & Rationale

**Why one phase.** The deliverable is `.doctrine/adr/017/authority-ledger.md`
plus an additive pointer in `adr-017.md §3`. The two touches are small and
coupled — the pointer is meaningless without the ledger, and the ledger's whole
purpose is to be the thing §3 points at. There is no verification boundary
between them and no independent shippable increment to gain by splitting, so
decomposition would be ceremony. PHASE-01 authors both and ends green.

**Why VA, not VT.** Every verification row is agent-checked (VA), not
test-checked (VT), and this is deliberate — not a skipped gate:

- The artifact is authored governance prose, not code. Its correctness is
  *fidelity to sources* (ADR-017 §3, SPEC-001 REQ ids, the verified enforcement
  anchors), which an agent judges by reading; there is no runtime behaviour to
  assert.
- Making the ledger machine-checkable is an **explicit slice non-goal**
  (slice-014.md, design §8 R2). The repo tests are `emacs --batch` ert; standing
  up an ert lint over a markdown table to mechanise "exactly one owner" would
  build the very tooling the slice deferred, and disproportionately.
- SPEC-001 NF-001's "grep both sides" is a **review action**, executed at each
  *future migration's* audit against the ledger — it is not a unit test of this
  slice. VA-4 verifies only that the format *supports* that grep (the worked
  D4.2 example), which is the most this slice can and should assert.

If CI-gating of the ledger is later wanted, it is the follow-up the slice already
names, and it would add VT rows to a *future* slice — not this one.

## Notes

- The pointer lands at `adr-017.md:59` ("Authority inventory with single
  ownership … recorded in a ledger as it migrates") — the natural §3 site. It is
  additive and dated; no existing §3 text is removed or renumbered (EX-2).
- Row 4 (audit) and row 7 (arrival) carry standing notes because they are the two
  live hazards the ledger exists to surface — a latent dual-write and a pending
  ADR-002 transition. The plan treats writing those notes as part of EX-1, not an
  optional extra.
- Residual QUE-001 (SPEC-001 lacks a lifecycle/arrival invariant) is **not** in
  this slice's scope; row 7 cites ADR-002 in the interim per INV-2.
