# Review RV-021 — design of SL-021

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Second pass (inquisitor, 2026-09-26), after F-1..F-5. Held against:
DEC-034..DEC-040, ADR-001 Amendments §1–§2, ADR-018 D3/D5, SPEC-001 REQ-007,
SPEC-002 REQ-013/015/018, POL-001, DEC-016/018, perceptual-design §S6; code in
`satan/` and panopticon (`runner.py`, `diff.py`, `umbriel/session.py`,
`store.py`, `docs/schema.md`); live `raw/desktop-*.jsonl` (read-only).

Lines of attack:

1. Is the full-state-per-event contract (DEC-036) actually published by its
   owner, or only an implementation property?
2. Do the live raw logs contain shapes the design treats as corner cases
   (windowless state events, reconnect without snapshot)?
3. Does the design agree with the accepted DECs it cites, word for word?
4. Ordering and zone premises behind the backward walk and day keying.
5. DRY against existing day / zone / decode helpers.
6. Completeness of the test-fixture migration and the closure grep.
