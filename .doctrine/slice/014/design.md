# Design SL-014: Stand up the ADR-017 §3 authority ledger

<!-- Reference forms (.doctrine/glossary.md § reference forms): entity ids padded
     (SL-020, REQ-059, ADR-004); doc-local refs bare — OQ-1 (§6), D1 (§7),
     R1 (§10), Q1. -->

## 1. Design Problem

ADR-017 §3 requires that every item of SATAN authority has **exactly one owner at
any time**, recorded in a ledger as it migrates. The ledger does not exist, and
ADR-017 lists it as an obligation *due before the first authority item migrates*
(D4.2 in the RFC-017 spine). Without it, ADR-017's "authority ledger exists and is
current" verification and SPEC-001 NF-001 ("no dual enforcement") are uncheckable.

This slice creates and populates that instrument for the first time. It is not a
new decision (ADR-017 decided single-ownership; SPEC-001 owns the invariant
contract) and not evergreen spec — it is one concrete artifact plus a one-line
pointer edit to ADR-017.

## 2. Current State

- **No ledger.** Authority is enforced implicitly in broker elisp; no artifact
  names owners. Enforcement sites are known and were located during design:
  schema validation `satan-tool-validate-args` (satan-tools.el:132), mode/tool
  table (satan-mode.el:80-208), audit `satan-audit-record` (satan-audit.el:95),
  budget `satan-budget-exceeded-p` (satan-budget.el:67) / broker deny
  (satan-broker.el:464), disable switches (`satan-*-enabled` defcustoms),
  arrival `satan-tick-quiet-p` (satan-tick.el:33).
- **Two latent hazards the ledger must surface on day one:**
  1. **Audit is a latent dual-write.** `satan-audit-record` (client) and the
     attrd bridge (`satan-attribute-listener.el` → `transcript.jsonl`) both
     append audit — ADR-018's "split authority already realised." This is an
     NF-001 violation-in-waiting the ledger row must flag.
  2. **Arrival policy has a pending transition.** Owner is `emacs-client`
     (satan-tick.el) today; ADR-002 (still `proposed`) places the clock in
     `satan-attrd`. The ledger is where that transition is recorded if/when
     ADR-002 is accepted.
- **`.doctrine` entity bundles tolerate a companion file** — verified: `doctrine
  validate` reports the corpus clean and `adr show ADR-017` still renders with an
  extra `.md` present in `.doctrine/adr/017/`.

## 3. Forces & Constraints

- **ADR-017 §3** — single owner per item; owner recorded as it migrates; reviewed
  at each extraction's audit.
- **SPEC-001** — the invariant contract. Rows cite REQ-001..008; the ledger
  operationalises NF-001 (no dual enforcement, "grep both sides"), NF-004
  (addressable at audit), and the "retrospective where already true" principle
  (Emacs is the accurate day-one owner).
- **ADR-018 D1/D2** — the topology the owner vocabulary keys to; D4.2 (policy +
  registry → `daemon-core`) is the first transition the ledger will record.
- **RFC-017** — this slice is gate **G2**; unblocking D4.2 is its purpose.
- **Doctrine storage model** — ADRs record *why* (immutable decision record);
  living current-state must not mutate the decision record (drove DEC-003).

## 4. Guiding Principles

- **The ledger tracks ownership transitions** — so its grain, format, and owner
  vocabulary all serve one question: "who owns this, and when did it move?"
- **Greppable over clever.** NF-001 is a grep; the format optimises for that, not
  for tooling that does not yet exist.
- **Accurate on day one.** Every row's owner is truthfully `emacs-client` before
  any migration; the ledger is not aspirational.
- **The ledger earns its keep by surfacing hazards** (dual-write, pending
  transitions), not by bookkeeping.

## 5. Proposed Design

### 5.1 System Model

One authored markdown file, `.doctrine/adr/017/authority-ledger.md`, a sibling of
`adr-017.{toml,md}` inside the ADR-017 entity bundle (DEC-003). `adr-017.md §3`
gains one pointer sentence linking to it. The file has three parts: an **owner
legend**, the **ledger table**, and a per-row **transition log**.

```
.doctrine/adr/017/
  adr-017.toml        (unchanged)
  adr-017.md          (+1 pointer line in §3)
  authority-ledger.md (NEW)
```

### 5.2 Interfaces & Contracts

**Owner legend** (fixed vocabulary keyed to ADR-017 §1 / ADR-018 D1 topology;
tokens added as items are received — DEC captured in §7 D3):

| Token | Component |
|---|---|
| `emacs-client` | The permanent privileged Emacs client (ADR-017 §1) |
| `daemon-core` | The single daemon repository/core (ADR-018 D1) |
| `satan-patcher` | Patch runner daemon (IMP-006) |
| `satan-memoryd` | Memory substrate daemon (IMP-007) |
| `satan-audit` | Audit verifier CLI (IMP-008) |
| `satan-attrd` | Attribute/arrival daemon (ADR-002) |

**Ledger table columns** (grain = one independently-enforced duty — §7 D2):

`# · Authority item · Owner · Governs (REQ) · Enforced at · Since`

- **Owner** — exactly one legend token. The "exactly one" invariant is a visual +
  greppable property of this column.
- **Governs** — one or more SPEC-001 REQ ids (NF-004 addressability).
- **Enforced at** — the current grep anchor. **Prefer a stable symbol name**;
  line numbers are advisory (they rot as code moves). On migration this field
  moves to the new site and the old site is deleted (the cutover proof, NF-001).
- **Since** — the decision/slice that set the current owner.

**Transition-log line** (append-only, one per owner change):

```
↳ YYYY-MM-DD  <from> → <to>  (SL-NNN audit; <old enforcement> deleted; <verification> green)
```

### 5.3 Data, State & Ownership

The initial population (day-one, all `emacs-client`):

| # | Authority item | Owner | Governs | Enforced at | Since |
|---|---|---|---|---|---|
| 1 | Action schema validation | `emacs-client` | REQ-001 | `satan-tool-validate-args` satan-tools.el:132 | ADR-017 |
| 2 | Mode/tool allowlist | `emacs-client` | REQ-002, REQ-006 | mode-spec `:tools` via `satan-mode-register`; consistency `satan-mode-check-tool-references` (satan-mode.el) | ADR-017 |
| 3 | Capability / jail profiles | `emacs-client` | REQ-002 | `satan-profiles` / `satan-mode--apply-profile` (satan-mode.el) | ADR-017 |
| 4 | Append-only audit | `emacs-client` | REQ-003 | `satan-audit-record` satan-audit.el:95 | ADR-017 |
| 5 | Token / budget ceiling | `emacs-client` | REQ-004 | `satan-budget-exceeded-p` satan-budget.el:67 | ADR-017 |
| 6 | Kill / disable switches | `emacs-client` | REQ-005 | `satan-*-enabled` defcustoms; broker halt | ADR-017 |
| 7 | Arrival policy (gating) | `emacs-client` | ADR-002 — *no SPEC-001 REQ covers lifecycle/arrival authority* (§6 Q1) | `satan-tick-quiet-p` / `satan-tick-pick` satan-tick.el | ADR-017 |

Row 4 carries a **standing note** on the attrd dual-write (the NF-001 hazard).
Row 7 carries a **standing note**: the *trigger* is a dumb external systemd timer
(satan-tick.el:4 — "systemd timer fires the broker every ~30 min"); the *policy*
(quiet-hours, weighted mode pick, per-tick budget ceiling) is `emacs-client` in
satan-tick.el. ADR-002 (still `proposed`) would move the *policy* to `satan-attrd`
as "the only periodic clock" — the pending transition this row will record.
Delivery
mechanisms REQ-006 (read-only artifact) and REQ-007 (control-plane RPC) are *not*
rows — they surface inside a row's "Enforced at" as it migrates. REQ-008 is the
ledger itself, not a row.

### 5.4 Lifecycle, Operations & Dynamics

- **Read** — a reviewer or agent opens the file (linked from ADR-017 §3) or greps
  it (`rg 'emacs-client|daemon-core' authority-ledger.md`).
- **Migrate** — the migrating slice's **audit** phase edits the moved row's Owner
  + Enforced-at and appends a transition-log line. The audit checklist gains
  "ledger row moved; old enforcement grep returns zero" (generalising ADR-018
  VT-3 to every item). This is a downstream-slice obligation, documented here,
  not built here.
- **Review** — ADR-017's per-extraction audit reads the ledger as the "current"
  check.

### 5.5 Invariants, Assumptions & Edge Cases

- **INV-1** — every row has exactly one Owner token drawn from the legend.
- **INV-2** — every row cites ≥1 SPEC-001 REQ (or a governing ADR where no REQ
  applies, cf. arrival policy / ADR-002).
- **INV-3** — a migration edits Owner + Enforced-at *and* appends a transition
  line in the same change; a row whose Owner moved without a transition line is
  malformed.
- **Assumption** — the seven-row set is complete for *today's* authority surface.
  If SPEC-001 gains a sixth+ invariant (its stated hypothesis), a row is added
  here, not smuggled into a slice.
- **Edge case** — an item genuinely co-owned during a transition window is *not*
  representable and *must not* be; that is the NF-001 hazard the single Owner
  column exists to forbid. A half-migrated item is malformed by construction.

## 6. Open Questions & Unknowns

All three scoping open questions are closed (§7 D1–D3). Residual, surfaced by the
adversarial pass:

- **Q1 — SPEC-001 under-covers lifecycle/arrival authority.** ADR-017 §3 lists
  "arrival policy" as an authority item, but SPEC-001's invariant set
  (schema / allowlist / audit / ceiling / kill + single-owner) contains no
  invariant for *who may start or gate a run*. Row 7 therefore cites ADR-002, not
  a REQ — INV-2 permits a governing ADR in place of a REQ, so the slice is not
  blocked. But this is a real gap in SPEC-001 (its own stated hypothesis: "if a
  sixth invariant surfaces, add it as a requirement"). Captured as QUE-001 for
  the SPEC-001 owner; **does not block SL-014**.
- **Q2 — the ADR-017 pointer edit** (see §10 F6): **RESOLVED 2026-07-24 (david):
  add the pointer.** An additive sentence in adr-017.md §3 pointing at the ledger,
  in keeping with ADR-017's existing dated-amendment style. adr-017.md stays in
  the design-target touch-set.

## 7. Decisions, Rationale & Alternatives

- **D1 — Home/format: linked companion `.md` in the ADR-017 bundle** (DEC-003,
  accepted). Alternatives (append to adr-017.md; standalone docs/; .toml)
  rejected — see DEC-003. Rationale: co-locates with the mandate, keeps the ADR
  immutable, stays in the governance tier, stays greppable.
- **D2 — Grain: one row per independently-enforced duty** (~7 rows). Rejected:
  ADR-017's six classes verbatim (conflates REQ-001/002/006 under "allowlists",
  too coarse to track ownership); one row per REQ (over-splits, mixes duties with
  delivery mechanisms 006/007 and the meta REQ-008). Rationale: rows sit at the
  grain of an *independently-ownable duty*. A single migration may move several
  rows at once — D4.2 moves rows 1, 2 and 3 together (all in satan-mode.el /
  satan-tools.el) — so the grain is not one-row-per-migration; it is the finest
  unit at which ownership *could* diverge.
- **D3 — Owner vocabulary: fixed legend-defined tokens keyed to ADR-018
  topology.** Rejected: free-text (drifts, breaks the grep); entity-id references
  (components are not doctrine entities). Rationale: minimum that keeps "exactly
  one owner" and the from→to grep trustworthy over time.

## 8. Risks & Mitigations

- **R1 — the ledger goes stale** (edited at slice time, forgotten). Mitigation:
  the update is bound to the migrating slice's *audit* step (§5.4), and ADR-017's
  per-extraction audit already reads it — staleness is caught at the next
  migration's gate, not left to drift.
- **R2 — companion file is an unconventional bundle inhabitant** a future CLI op
  might not expect. Mitigation: validated clean today; it is inert data the engine
  ignores; the risk is a future doctrine-CLI change, out of this slice's control
  and cheaply relocated if it ever bites (the link is the only inbound reference).
- **R3 — row set drifts from SPEC-001** as invariants evolve. Mitigation: INV-2
  ties each row to a REQ; a new REQ without a row is visible at review.

## 9. Quality Engineering & Validation

No code, no tests — this is an authored governance artifact. Validation is by
agent/human review (VA) against the sources:

- **VA-1** — every ADR-017 §3 authority class appears as ≥1 row (completeness).
- **VA-2** — every row names exactly one legend Owner token (INV-1); all
  `emacs-client` on landing (retrospective accuracy).
- **VA-3** — every row cites its governing SPEC-001 REQ or ADR (INV-2, NF-004).
- **VA-4** — the transition-log format makes a from→to change greppable (INV-3,
  NF-001), demonstrated by the worked D4.2 example in the ledger preamble.
- **VA-5** — `adr-017.md §3` links the ledger; `doctrine validate` clean.

Closure = ADR-017's "authority ledger exists and is current" reads as satisfiable
and RFC-017 G2 is met.

## 10. Review Notes

Internal adversarial pass (self-review), findings + disposition:

- **F1 — row 7 cited a bogus REQ.** Draft cited "REQ-005 (kill-adjacent)" for
  arrival policy; REQ-005 is kill switches, not lifecycle authority. **Fixed:**
  row 7 now cites ADR-002 only, and the underlying SPEC-001 coverage gap is
  raised as Q1 / QUE-001. *(Confirmed against SPEC-001 invariant set.)*
- **F2 — row 7 owner precision.** Verified against satan-tick.el:4-5: the trigger
  is a dumb external systemd timer; the *policy* (quiet-hours / weighted pick /
  per-tick budget) is emacs-client. Owner `emacs-client` holds; **the standing
  note was rewritten** to state trigger-vs-policy precisely. *(Confirmed.)*
- **F3 — "grain = migration unit" overclaimed.** D4.2 moves rows 1–3 together, so
  the grain is not one-row-per-migration. **Fixed** §7 D2 wording ("finest unit
  at which ownership could diverge").
- **F4 — line-number rot.** Enforcement anchors used file:line, which drifts.
  **Fixed:** §5.2 now prefers stable symbol names; line numbers advisory.
- **F5 — INV-1/2/3 are review-checked, not enforced.** Machine-checking is a
  slice non-goal, so these are conventions verified by VA at review, not runtime
  invariants. §9 VA-2/3/4 already map to them; framing left as-is (they are
  invariants *of the artifact*, checked by review — honest given §9).
- **F6 — editing an accepted ADR (unresolved, for the user).** The design adds a
  forward pointer to `adr-017.md §3`, an accepted ADR. ADR-017 already carries
  dated amendment text, so an additive pointer is arguably in-keeping — but this
  is a governance-convention call. Alternative: leave ADR-017 untouched; the
  ledger back-references it and DEC-003 + RFC-017 G2 supply discoverability.
  **RESOLVED 2026-07-24 (david): add the pointer** — additive sentence in §3, an
  in-keeping dated amendment; adr-017.md remains a design target.
