# Review RV-003 — reconciliation of SL-013

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

**Mode:** conformance. **Surface reviewed:** the main tree at `2c16d84` — SL-013
was executed in-tree via `/execute`, not dispatched, so there is no candidate
interaction branch and `review/*` / `phase/*` carry no evidence refs.

**What this audit probes.** SL-013 is ADR-018 D4.1's in-language rehearsal of
single-owner discipline. Its whole claim is a *property of the tree at a moment*
(design D3): the duplication is gone, and the gates that say so name actual
symbols rather than sampling them. So the audit's first duty is to re-run the
gates independently rather than read the phase notes' report of them — the slice
itself twice found a criterion satisfiable while the defect stood (RV-002 F-1,
and PHASE-02's own control-grep discipline).

**Lines of attack:**

1. **Re-run every zero-hit grep from a clean shell, with a live control.** All 15
   deleted/renamed names, each counted individually. A summarised "no hits" and
   a silently-broken invocation are indistinguishable — the notes record this
   trap twice, and it recurred during this audit's own first attempt (a `bc`
   fallback printed 15 spurious zeros).
2. **ADR-018 VT-2 tree-wide, not per-symbol.** Design §9 maps VT-2's third clause
   ("no symbol defined both as struct accessor and as `defun`") onto PHASE-02
   EX-3, which is worded for `satan-run-prepare` alone. Check the clause against
   *every* `cl-defstruct` in `satan/*.el`, not the one the slice was looking at —
   the same widening A1's falsification (F1) already forced once.
3. **I3 / C1 by reading the require block.** The invariant that preserves the MCP
   constraint; if it fails the clone comes back. Read, never inferred.
4. **R5 docstring union, pairwise against the pre-collapse tree.** Diff each
   survivor against the deleted twin at `1be1f3e`, in both directions. A
   mechanical "keep the broker's" would have deleted `satan-run-mint-id`'s only
   docstring; a mechanical "keep the leaf's" would have deleted the `:audit` /
   `satan-intervention-create` contract.
5. **Residual soft-coupling in modules the slice touched but did not enumerate.**
   EX-5 names five reachers and PHASE-03 converted a sixth (`satan-tank`, DEC-002).
   Look for a seventh — and for the *renamed-fork* duplication class that §2.1's
   symbol-keyed census structurally cannot see (RV-002 F-2), now that the leaf
   publishes a layout API every dependant may call.
6. **Conformance algebra as a lead, not a verdict.** Read `slice conformance`'s
   undeclared/undelivered cells against design §5.4's impact table and decide
   which cell is drift and which is registry noise.
7. **The reconcile debt already on record.** Design §10 and the phase notes book
   two governance corrections against ADR-018 and one against design §10 itself.
   Confirm they are still owed and route them, rather than let them dissolve.

**Invariants held.** C1 (MCP gets run identity without context/percept), C2 (no
behavioural change to run identity), C4 (`just check` clean), I1–I5, ADR-018 VT-2,
POL-001's "precondition, not an extraction" — nothing may have moved out of elisp
and no ADR-017 §3 authority may have changed owner.

## Synthesis

**The slice did what it said, and the gates that say so hold under independent
re-run.** Eleven findings, no blockers, no majors against the implementation.
The one `major` is against *governance*, not against the code.

### What was verified, not read

Every gate was re-run from a clean shell rather than taken from the phase notes.
The trap the slice warned about twice recurred immediately: this audit's first
grep sweep piped through `bc`, which is absent from this environment, and the
`|| echo 0` fallback printed **fifteen spurious zeros** — a perfect pass for a
search that never ran. Re-run with `rg` and per-symbol counting against live
controls (`satan-run-locate-dir` 19, `satan-run--spawn-running` 18,
`satan-run--session-active` 14):

- **All 15 deleted/renamed names: zero hits** across `satan/**` including tests.
  PHASE-02's seven (`satan-broker--{mint-run-id,iso-time-format,prepare,tool-ctx,failed-suffix,date-bucket-for-run-id}`,
  `satan-broker-run-dir-for-id`) and PHASE-03's eight
  (`satan-broker-{locate-run-dir,list-run-dirs,run-dirs-for-date}`,
  `satan-broker--{bucket-name-p,legacy-run-name-p,run-id-from-leaf,spawn-running}`,
  `satan-mcp--session-active`).
- **ADR-018 VT-2, clauses 1–2:** exactly one `cl-defstruct satan-run`
  (`satan-run.el:30`), one `defcustom satan-runs-dir` (`:15`), one `defcustom
  satan-hippocampus-dir` (`:20`). No `defvar`/`defconst` of either name anywhere
  after F-5's repair.
- **ADR-018 VT-2, clause 3 — widened past the slice's own gate.** PHASE-02 EX-3
  is worded for `satan-run-prepare` alone; design §9 nonetheless maps VT-2's
  tree-wide clause onto it. Checked properly: `satan/*.el` contains exactly three
  `cl-defstruct`s (`satan-run`, `satan-audit-handle`, `satan-mcp-session`), and
  no `defun` in the tree collides with any accessor of any of them —
  `satan-context.el`'s `satan-run-perceive` / `-enrich` / `-assemble-context`
  (design F2) match no slot name, which is what makes F2's "leave them alone"
  correct rather than merely convenient. **VT-2 holds of the tree, not just of
  the symbol the slice was looking at.** This is a stronger discharge than the
  authored gates provide, and it is the one place the audit had to widen a
  criterion rather than run it.
- **I3 / C1:** `satan-run.el`'s require block read verbatim — `cl-lib`, `subr-x`,
  `satan-custom`, nothing else, and nothing pulled in transitively by a moved
  body. The invariant that keeps the clone from coming back.
- **R5 docstring union, pairwise against `1be1f3e`.** Every survivor diffed
  against its deleted twin in the pre-collapse tree. `satan-run-tool-ctx` carries
  the broker's `:audit` / `satan-intervention-create` contract verbatim;
  `satan-run-mint-id` keeps the leaf's docstring, which the broker copy did not
  have at all; `satan-run--iso-time-format` correctly sheds *"the broker
  stamps"*; the struct keeps the leaf's docstring **and** the broker's four-line
  `prepare`-slot comment; `satan-hippocampus-dir` carries D7's union naming both
  roles. The obligation ran in both directions, as R5 required.
- **`just check` exit 0 · 1030 tests · 0 unexpected · 13 skipped**, skip set
  byte-identical to the 1018-test baseline's. Re-run after this audit's own
  repairs: same numbers.

### The one thing the slice got materially wrong is not in the code

**F-1.** ADR-018's Context still asserts a mechanism for the
accessor/`defun` collision that EVD-001 falsified — it credits byte-compilation,
in a project whose tests run interpreted. The slice knew this from design
onward and correctly refused to hand-edit an accepted ADR. It is real reconcile
debt, and it is load-bearing: the stated mechanism implies a false safety
condition, so a future reader could reason their way back into the hazard.

**F-2 sharpens it, and partly rehabilitates the hypothesis the design dismissed.**
Design §10 asserts flatly that "load order is not the variable". PHASE-02's very
first edit falsified that for the escape hatches: adding `(require 'satan-run)`
to the broker put the leaf first, the broker's surviving `cl-defstruct` then
re-installed the accessor over the `defun`'s function cell, and PHASE-01's
`funcall`-based test went red. The verdict *latent* is untouched — it rests on
the syntactic rows, which inline under either order. But the `funcall`/`apply`/
`eval` rows describe a function cell whose occupant **was** decided by load
order. Both prior explanations were *incomplete* rather than simply wrong, and
the corrected mechanism has to say so in both places.

### Standing risks

- **The duplication class is measured clean, not made un-reintroducible.** This
  was already on record (RV-002 F-2, design §9) and this audit supplies the
  evidence for it: **F-3** found a *twelfth* instance — `satan-context.el`'s
  `satan-context--bucket-regexp` and `satan-context--list-recent-runs` are a
  renamed fork of `satan-run--bucket-name-p` and `satan-run-list-dirs`, in a
  module this very slice gave a hard `(require 'satan-run)`. §2.1's symbol-keyed
  census never reached it, exactly as RV-002 F-2 predicted a symbol-keyed scan
  would not. Captured as [[IMP-018]], which is now the concrete cost argument
  [[IMP-017]] previously lacked.
- **The leaf now touches the disk.** Design §5.3 records this deliberately.
  `satan-run.el` went from path arithmetic to `directory-files` /
  `file-directory-p` enumeration, and I3 survives because those primitives are
  C-core — not because the code is pure. Any future addition to this module must
  be checked against the require block, never against the code's character.
- **`doctrine check gate` is broken in this repo** (**F-11** → [[CHR-002]]). No
  verification was skipped — every phase ran `just check` — but a mandated audit
  step exits non-zero for a config reason, and that trains readers to skip it.

### Tradeoffs consciously accepted

- **F-3 was not fixed here, and the reason is not size.**
  `satan-context--list-recent-runs` is not behaviourally equivalent to
  `satan-run-list-dirs` (newest-first ordering, early exit at N, a run-id regexp
  with capture groups the leaf's bare predicate does not offer). Collapsing needs
  a design call about whether the leaf grows an ordered/limited variant and a
  parser. Making that call inside an audit would be improvising design — and five
  of the suite's 13 skips are `satan-context` corpus-integration tests, so the
  change would land least-observed of anywhere in the module.
- **F-9 and F-10 are criteria the phases met in substance and not in letter, and
  both stay as authored.** `plan.toml` ids are immutable-append, so PHASE-01
  VA-1's wrong noun (a `.FAILED` branch `satan-run-dir-for-id` never had) cannot
  be corrected in place — and should not be: PHASE-03 later added the tests that
  exercise `.FAILED` on the functions that actually implement it. PHASE-02 VA-3's
  letter would require deleting the one test that detects the defect VA-3 exists
  to prevent. Both phases reported the deviation rather than quietly satisfying
  it, which is the behaviour the ledger wants.
- **Three fix-now repairs were taken in-audit**, all code-only, all zero
  behaviour change, all residue of the duplication this slice collapsed: the dead
  `(boundp 'satan-runs-dir)` guard (**F-4**), the observer test's stale
  cycle-breaker (**F-5**), and `satan-run.el`'s pre-collapse file header
  (**F-6**). Suite re-run green after.

### Verdict

SL-013 discharges ADR-018 D4.1. The seam has one owner, the leaf holds at three
requires, both require cycles are gone, six modules stopped paying for
soft-dependency scaffolding, and the property ADR-018 VT-2 asserts holds of the
whole tree rather than of the one symbol the gates named. The rehearsal of
single-owner discipline succeeded. What it did **not** establish — and this
audit found a fresh instance of — is that the class cannot recur; that claim
belongs to [[IMP-017]], and [[IMP-018]] is now its evidence.

## Reconciliation Brief

### Per-slice (direct edit)

- **`design.md` §10 (F-2)** — the EVD-001 call-form table and the paragraph
  beneath it. Qualify the `funcall` / `apply` / `eval` rows: they describe a
  function cell whose occupant was decided by load order, which PHASE-02's first
  edit flipped. Soften *"Load order is not the variable"* to *"Load order is not
  the variable for syntactic call sites"*, and restate the two prior explanations
  as **incomplete** rather than simply wrong. Evidence: `notes.md`, 2026-07-24
  PHASE-02, "EVD-001 refined — the `funcall` row is load-order-contingent".
- **Selector registry (F-7)** — `doctrine slice selector rm SL-013
  satan/test/satan-context-test.el`. This is the load-bearing change: `slice
  conformance` reads the registry (`slice-013.toml`), and the selector is what
  puts the file in the `undelivered` cell. **No `design.md` mirror edit is
  owed** — §5.4's impact table never listed the file, so removing the selector
  makes registry and design agree rather than requiring both to move. Re-run
  `doctrine slice conformance SL-013` afterwards; `undelivered` should be empty.

### Governance/spec (REV)

- **ADR-018, Context paragraph (F-1, F-2)** → **REV modify**. Replace the
  accessor/`defun` collision's stated mechanism. Currently credits byte-compiled
  callers inlining before the clobber; the operative mechanism is that
  `cl-defstruct` accessors are `cl-defsubst`s installing a **`compiler-macro`
  property** that `defun` does not remove, applied at macroexpansion — i.e. on
  load — so every *syntactic* call site inlines to the slot read, **interpreted
  and compiled alike**. The correction must also carry F-2's refinement: the
  non-syntactic forms (`funcall` / `apply` / `eval`) reach whichever definition
  load order left in the function cell, so the escape hatch was never stable and
  only the rename made the symbol single-meaning. Cite EVD-001 and SL-013 design
  §10. This matters because the current wording implies a false safety condition
  — that an interpreted-only tree is exposed — from which a future reader could
  reason their way back into the hazard.

### Not on either surface — recorded here so reconcile does not look for them

- **F-3 → [[IMP-018]]**, **F-11 → [[CHR-002]]**. Follow-up work, already
  captured; no reconcile write.
- **F-4, F-5, F-6** — fixed in-audit; source only, no artefact change.
- **F-8, F-9, F-10** — disposed `aligned`; nothing owed. In particular **F-9's
  remedy is *not* a `plan.toml` edit**: PHASE-01 VA-1's noun is loose, but plan
  criteria are immutable-append and off-surface for reconcile. The substance is
  already recorded in `notes.md`.

## Reconciliation Outcome

Reconcile pass, 2026-07-24. All 11 findings terminal (`verified`) at entry; no
finding disposition was mutated. Every brief item is resolved.

### Direct edits applied

- **`design.md` §10 (F-2)** — three edits plus the section heading.
  - The EVD-001 matrix's `funcall` / `apply` / `eval` rows now read
    *(load-order-contingent)*, and a new paragraph beneath the table states that
    those rows describe a function cell whose occupant load order decides — the
    matrix was measured with `satan-broker.el` loaded last, and PHASE-02's first
    edit (`(require 'satan-run)` in `satan-broker.el`) put the leaf first and
    flipped them. The first three rows are unconditional under either order,
    which is what the **latent** verdict rests on.
  - *"Both explanations on record are nonetheless wrong"* → **incomplete**, with
    both bullets restated: the ADR bullet now says byte-compilation is real but
    not operative (the `compiler-macro` property inlines interpreted callers too,
    **C5**); the R1 bullet now says load order is not the variable **for
    syntactic call sites** but *is* the variable for `funcall` / `apply` / `eval`,
    R1's error being over-generalisation of a true result.
  - Section heading *"…every recorded reason is wrong"* → *"…incomplete"*, so the
    heading does not contradict the paragraph beneath it.
  - The **Reconcile debt** paragraph is marked discharged and cites [[REV-001]].
- **Selector registry (F-7)** — `doctrine slice selector rm SL-013
  satan/test/satan-context-test.el`. `doctrine slice conformance SL-013` re-run:
  **`undelivered (0)`**, 22 conformant. No `design.md` §5.4 mirror edit was owed
  or made — §5.4's impact table never listed the file, so removing the selector
  makes registry and design agree. The 12 `undeclared` paths remain and are F-8,
  disposed `aligned` (systemic `.doctrine/` registry scope, not slice drift).

### REVs completed

- **[[REV-001]]** (`reconcile-sl-013`) — **done**. One row: `modify ADR-018`
  (primary), surfaced-for-manual at apply and landed by hand under the
  authored-truth honour model. Covers **F-1** (major) and F-2's governance half.
  ADR-018's Context, fifth bullet: the falsified mechanism (byte-compiled callers
  inlining before the clobber) is replaced by the operative one — `cl-defstruct`
  accessors are `cl-defsubst`s installing a `compiler-macro` property `defun`
  does not remove, applied at macroexpansion, so every syntactic call site
  inlines to the slot read **interpreted and byte-compiled alike** — and carries
  F-2's refinement that the non-syntactic forms reach whichever definition load
  order left in the function cell, so the escape hatch was never stable and only
  the rename made the symbol single-meaning. Before/after excerpts, scope guard
  and rationale in `revision-001.md`.
  - **Scope guard held**: a Context observation only. No ADR-018 Decision
    (D1–D8), consequence or verification criterion moved; no ADR-017 §3 authority
    item changed owner.
  - **Canon note**: the imported-corpus freeze governs id *resolution* for
    imported prose, not mutability. ADR-018 was authored and accepted in this
    repo, so it resolves locally and a local REV is the correct mechanism. This
    is the first governance amendment here since the 2026-07-22 import.

### Not written, by design

- **F-9** — no `plan.toml` edit. PHASE-01 VA-1's loose noun is real, but plan
  criteria are immutable-append and off-surface for reconcile; the substance is
  recorded in `notes.md`. Disposed `aligned`; nothing owed.
- **F-3 → [[IMP-018]]**, **F-11 → [[CHR-002]]** — follow-up work already
  captured; no reconcile write.
- **F-4, F-5, F-6** — fixed in-audit, source only; no artefact change.
- **F-8, F-10** — disposed `aligned`; nothing owed.

### Not re-audited

No new discovery was performed (D9). No new gap was found while locating edit
points, and no target had drifted since the audit. RV-003's cache remains stale
on the three files the audit repaired — an optimisation signal, not a gate, and
no further findings were raised, so it was not re-primed.

Reconcile pass complete — handoff to `/close`.
