# Notes SL-014: Stand up the ADR-017 §3 authority ledger

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Audit harvest (RV-004, 2026-07-24)

**Outcome:** conformant + complete. Two findings, both terminal, no blockers.
- **F-1 (aligned)** — conformance `undeclared` flagged `slice-014.toml`; it is the
  slice's own status TOML (ready→started), not a design surface. No action.
- **F-2 (verified → reconcile)** — ledger rows 2/3 anchor to symbols, not design
  §5.3's stale `satan-mode.el:80-208` range. Ledger is correct (design §5.2/F4
  mandates symbol-first); design.md §5.3 is stale and gets a per-slice direct
  edit at reconcile. See RV-004 `## Reconciliation Brief`.

**Standing (carried, not slice defects):**
- **Row-4 audit dual-write** — `satan-audit-record` ↔ attrd bridge
  (`transcript.jsonl`) both append audit; latent REQ-009/NF-001 hazard, tolerated
  while both sit inside the one `emacs-client` owner. The migration giving audit a
  daemon owner must collapse to a single writer. Home = ledger row-4 standing note.
- **QUE-001** — SPEC-001 has no lifecycle/arrival invariant; row 7 cites ADR-002
  (INV-2-legal). Owned by the SPEC-001 owner; out of SL-014 scope.

**Gotcha (→ memory):** id-allocating doctrine MCP verbs (`review_new`) fail
`-32603` in this sandbox — the MCP server lacks `DOCTRINE_RESERVATION_FALLBACK`.
Use the CLI with the env var for id-allocating calls. Recorded in
[[sandbox-doctrine-reservation-fallback]].
