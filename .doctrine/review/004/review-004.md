# Review RV-004 — reconciliation of SL-014

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

**Reviewed surface:** in-tree (solo `/execute`, not dispatched). Commit `77ba06e`
on `main`; conformance computed from the recorded PHASE-01 source-delta.

**What this audit probes.** SL-014 produces one authored governance artifact
(`authority-ledger.md`) plus an additive pointer in `adr-017.md §3`. No code, no
VT (deliberate — plan.md "Why VA, not VT"). The audit holds the slice to:

- **EX-1** — the ledger carries all six required parts (legend, 7-row day-one
  table all `emacs-client`, row-4 + row-7 standing notes, transition-log format,
  worked D4.2 example).
- **EX-2** — the §3 pointer is additive/dated; no prior §3 text removed or
  renumbered.
- **EX-3 / VA-5** — `doctrine validate` clean; ADR-017 renders with the companion.
- **VA-1..4** — completeness against ADR-017 §3's six classes; single legend
  Owner per row (all `emacs-client`); every row cites a REQ or governing ADR
  (REQ-012/NF-004 addressability); the transition format is greppable (REQ-009/
  NF-001), demonstrated by the worked D4.2 example.
- **Fidelity to sources** — rows faithful to ADR-017 §3, SPEC-001 REQ titles, and
  the *verified-present* enforcement anchors.

**Lines of attack / where bodies may hide.**
1. Conformance `undeclared`: `slice-014.toml` touched — scope creep or benign
   lifecycle metadata? (→ F-1)
2. Anchor fidelity: design §5.3 cited `satan-mode.el:80-208`; that range is stale
   in-tree. Did the ledger silently diverge from the design, and does canon
   (design.md §5.3) now lie? (→ F-2)
3. Standing gap: row 7 cites ADR-002, not a REQ (QUE-001). Is the accepted-gap
   rationale intact and INV-2-legal? (→ synthesis, not a finding — already an
   entity + design §6 Q1).

## Synthesis

SL-014 is a single-artifact governance slice: it stands up
`.doctrine/adr/017/authority-ledger.md` (RFC-017 gate G2) and wires an additive
dated pointer from `adr-017.md §3`. The audit finds it **conformant and complete**.

**Closure story.** Conformance is clean — both design-target artifacts matched
(`conformant(2)`), nothing declared-but-undelivered (`undelivered(0)`), and the
sole `undeclared` touch is the slice's own status TOML (F-1, aligned). All exit
criteria hold: the ledger carries the owner legend, the seven-row day-one
inventory (every Owner `emacs-client`, verified by grep across all rows), the
row-4 attrd dual-write and row-7 trigger/policy standing notes, the append-only
transition-log format, and the worked D4.2 example; the §3 pointer is a pure
insertion (EX-2, confirmed by diff); `doctrine validate` is clean and ADR-017
renders with the companion present (EX-3/VA-5). VA-1..4 all pass: six ADR-017 §3
classes each map to ≥1 row, every row cites a REQ (or ADR-002 for row 7), and the
from→to transition shape is greppable.

**One divergence, minor and sanctioned** (F-2, verified → reconcile): the ledger
anchors rows 2/3 to stable symbol names rather than design §5.3's stale
`satan-mode.el:80-208` range. The ledger is *more* correct — design §5.2/F4
mandates symbol-first, lines advisory — but design.md §5.3 now carries anchors
that were inaccurate even at authoring and no longer mirror the delivered
artifact. Canon is reconciled to the symbols (Per-slice direct edit).

**Standing risks / consciously accepted.**
- **QUE-001 — SPEC-001 under-covers lifecycle/arrival authority.** Row 7 cites
  ADR-002, not a REQ, because no SPEC-001 invariant governs *who may start or gate
  a run*. INV-2 permits a governing ADR in place of a REQ, so the slice is legal;
  the gap is real and owned by the SPEC-001 owner as QUE-001. Not a finding — an
  entity already exists and design §6 Q1 records it. Does not block closure.
- **Row-4 audit dual-write** is a latent REQ-009/NF-001 hazard, tolerated today
  because both write paths sit inside the one `emacs-client` owner; the ledger's
  standing note ⚠ ensures the migration that gives audit a daemon owner must
  collapse it to a single writer. This is the ledger *doing its job* (surfacing a
  hazard), not a slice defect.
- **No VT by design** (plan.md "Why VA, not VT"); machine-gating the ledger is an
  explicit slice non-goal (design §8 R2). Correctness is fidelity-to-sources,
  audited by VA read. Accepted.

## Reconciliation Brief

### Per-slice (direct edit)
- **design.md §5.3 (rows 2–3 "Enforced at"), from F-2** — replace the stale
  concrete anchors with the symbol-first anchors the delivered ledger uses, so
  canon mirrors the artifact and honours the design's own §5.2 rule:
  - row 2: `mode/tool table satan-mode.el:80-208` →
    `mode-spec :tools via satan-mode-register; consistency satan-mode-check-tool-references (satan-mode.el)`
  - row 3: `mode specs satan-mode.el` →
    `satan-profiles defcustom / satan-mode--apply-profile (satan-mode.el)`
  Line numbers stay advisory (§5.2). This is prose-fidelity only — no selector or
  registry change (both artifacts are already conformant; the selectors matched).

### Governance/spec (REV)
- None. No ADR, policy, standard, spec, or requirement diverged. ADR-017 §3 gained
  only the sanctioned additive pointer (F6-resolved, in-slice, not a reconcile
  item). QUE-001 is a pre-existing open question owned by the SPEC-001 owner, out
  of this slice's scope — not a reconcile action here.

## Reconciliation Outcome

### Direct edits applied
- **design.md §5.3 (rows 2–3 "Enforced at")** — replaced the stale
  `satan-mode.el:80-208` / `mode specs satan-mode.el` anchors with the
  symbol-first anchors the delivered ledger uses (`satan-mode-register` +
  `satan-mode-check-tool-references`; `satan-profiles` / `satan-mode--apply-profile`).
  Canon now mirrors `authority-ledger.md` and honours design §5.2 (symbol-first,
  lines advisory). Drove: RV-004 F-2.

### REVs completed
- None. No governance/spec item in the brief — no ADR/spec/requirement diverged.

### Withdrawn / tolerated
- RV-004 F-1: aligned (benign `slice-014.toml` lifecycle-metadata touch; no write).

Reconcile pass complete — every brief item resolved. Handoff to /close.
