# Collapse the satan-run / satan-broker run-context duplication

## Context

`satan-run.el` and `satan-broker.el` each declare their own `cl-defstruct
satan-run`, their own `satan-runs-dir` and `satan-hippocampus-dir` defcustoms,
and their own forked `mint-id` / `prepare` / `dir-for-id` / `tool-ctx`. The
clone exists because `satan-mcp.el` needed run identity without pulling in
context/percept, and copying was cheaper than extracting. `satan-mcp.el` is the
only module that requires `satan-run`.

ADR-018 D4.1 sequences this as **step 1** of the extraction programme, and
POL-001 records it as a *precondition, not an extraction*: same language, low
risk, and it rehearses the single-owner discipline before any authority item
migrates. ADR-018 VT-2 is already written as the acceptance test.

**The hazard — settled at design as latent.** `satan-run.el:27`'s struct
generates the accessor `satan-run-prepare`; `satan-run.el:77` then defines
`(defun satan-run-prepare (mode) …)` over that same symbol, clobbering its
function cell. `satan-broker.el` reads the slot at three sites (`:284`, `:406`,
`:449`). A call that resolves to the defun silently returns a freshly minted
run_id with an unfrozen `time_now` — no error, wrong value.

Design settled this empirically (**EVD-001**, design §10): `cl-defstruct`
accessors are `cl-defsubst`s that install a **`compiler-macro` property**, which
`defun` does not remove. Emacs applies compiler-macros at macroexpansion, which
happens on load — so every *syntactic* call site inlines to the slot read,
interpreted **and** compiled. All four in-tree call sites are syntactic, and no
`funcall` / `apply` / `#'satan-run-prepare` exists anywhere. **Verdict: latent;
the rename does not need to lead the phase order.**

Both explanations previously on record are wrong, and each implied a false
safety condition: ADR-018's Context credits byte-compilation (interpreted
callers inline too), and this slice's original R1 credited load order (both
orders inline identically). Correcting them is reconcile debt against ADR-018.
The residual hazard is one `(mapcar #'satan-run-prepare …)`, `advice-add`, or
`cl-letf` away.

`satan-run.el` has no test file.

## Scope & Objectives

Collapse to one owner of run identity and run context.

- **One `cl-defstruct satan-run`** in the tree. One `satan-runs-dir`, one
  `satan-hippocampus-dir`.
- **One implementation each** of run-id minting, run-ctx preparation,
  `dir-for-id`, and `tool-ctx` — currently forked across
  `satan-run.el:38/77/66/98` and `satan-broker.el:119/129/191/270`.
- **Rename the colliding defun** `satan-run-prepare` → `satan-run-new-ctx`
  (ADR-018 D4.1 names the target).
- **Discharge ADR-018 VT-2** — exactly one definition of the struct and of each
  defcustom, and no symbol defined both as a struct accessor and as a `defun`.
  **Revised (design D3):** this bullet previously read "land VT-2 as a standing
  lint". VT-2 asserts a *property of the tree* and merely notes it is
  "enforceable as a lint check" — the same feasibility clause VT-3 writes as
  "Grep-able". The lint was this slice's reading, not the ADR's obligation, and
  it is withdrawn: cost above a phase (accessor derivation against four shapes
  the tree never exercises), benefit below one (the class has recurred three
  times at zero realised cost, and the check would see 4 of 11 duplications).
  VT-2 is discharged instead by the phase exit greps, which name the actual
  symbols. Standing enforcement and the structural check that would cover the
  seven renamed forks are [[IMP-017]].
- **Establish which module owns the seam** so `satan-mcp.el` gets run identity
  without inheriting context/percept. That constraint is what produced the
  clone; a collapse that reinstates the coupling has not solved it.
  **Answered (design D1 / DEC-001): `satan-run.el` owns it, staying a leaf on
  `cl-lib` / `subr-x` / `satan-custom`.**
- **Move the run-directory layout cluster to the same owner** (design D2) —
  `locate-run-dir`, `list-run-dirs`, `run-dirs-for-date` and their three private
  helpers. Not duplicated, so strictly beyond the four forked items, but it is
  the payload five modules currently reach through soft-dependency guards, and
  moving it **dissolves two genuine require cycles** (`satan-budget` and
  `satan-observer` cannot require `satan-broker`, which requires them).
- **Fold in four defects design surfaced** (design D5), each either covered by
  the objectives above or caught by a phase exit grep: a third
  `satan-hippocampus-dir` in `satan-tools-hippocampus.el` (F1); `satan-context.el`
  using `satan-run-*` with no require (F3); `satan-broker--spawn-running` defined
  with a value in two modules (F4); `satan-mcp--mint-session` hand-rolling a
  4-key run-ctx instead of the canonical 10-key constructor (F5).
- **Retire the DEC-8 soft-coupling in both directions** (design D6, from the
  adversarial pass). Mutual exclusion is a *two*-flag protocol and each module
  reaches into the other: MCP reads the broker's `spawn-running`, and the broker
  reads `satan-mcp--session-active` behind a `boundp` guard at `:739`. Both flags
  move to the leaf; the guard goes. Not forced by VT-2 — `session-active` is
  defined once — but moving one and not the other would retire half a coupling
  and call the rehearsal complete.
- **Collapse `satan-hippocampus-dir` to one declaration carrying both roles**
  (design D7). The jail's read-write scratch directory and the hippocampus corpus
  are one concept with two docstrings; the survivor must say so, or the next
  reader re-splits it.
- Suites green throughout; `just check` clean at every phase boundary.

## Non-Goals

- **No extraction and no authority migration.** This is ADR-018's in-language
  rehearsal. Nothing moves out of elisp, nothing changes owner in the ADR-017
  §3 ledger — that ledger is D4.2's artifact and does not exist yet.
- **The broker's spawn/filter/sentinel/finalize body** (~980 lines) — ADR-018
  D4.4 sequences it last, and it is out of scope except where a call site must
  change to follow the collapsed owner.
- **No behavioural change to run identity.** Run-id format, date bucketing,
  the `.FAILED` suffix, and the frozen `:time_now` / `:run_id` / `:start_time`
  contract all survive unchanged. This is a topology fix.
- **`satan-mcp.el`'s session model** beyond the require, the F5 constructor
  switch, and whatever call sites the rename touches.
- **`satan-context.el`'s `satan-run-perceive` / `-enrich` / `-assemble-context`**
  (design F2). They share the `satan-run-*` prefix but collide with nothing and
  belong to the run-ctx pipeline; renaming them is cosmetic churn.

## Risks, assumptions, open questions

- **R1 — ANSWERED: latent.** Settled empirically at design (EVD-001, design
  §10). Not a bug fix; the rename does not lead. The mechanism is the accessor's
  surviving `compiler-macro` property, not byte-compilation and not load order —
  so both prior explanations were wrong, and correcting ADR-018's Context is
  reconcile debt.
- **R2 — DOWNGRADED.** `satan-run.el` is still untested, but a canonicalising
  sexp comparison proved all seven cloned bodies and both 18-slot structs
  identical modulo docstrings. The broker side is pure deletion, so its existing
  coverage *is* the characterisation suite; P1 retargets it into
  `satan-run-test.el` before anything moves.
- **R3 — CLOSED on evidence.** All three defcustom declarations carry identical
  default expressions, and `defcustom` sets a default only when unbound — so
  collapsing changes **no value**, and a keeper's `custom-set-variables` binds
  the shared symbol either way. Only the docstring surface changes — and for
  both defcustoms the two declarations are **byte-identical, docstrings
  included** (design §2.2), so nothing is at stake there.
- **R5 — NEW: docstring loss.** Real, but not uniform: the broker is the richer
  side for five of the cloned bodies and `satan-run.el` is richer for
  `mint-run-id`, whose broker copy has no docstring at all (design §2.2).
  Deletion must preserve the union **in both directions**; a mechanical "keep
  the broker's" would delete the only docstring `satan-run-mint-id` has. A
  reviewer must diff docstrings pair by pair, not just symbol lists.
- **R6 — NEW: a missed rename site.** Mitigated by tests running interpreted —
  every miss is a void-function/void-variable at load — plus the zero-hit greps
  in P2's and P3's exit criteria.
- **R7 — NEW: the leaf acquires a dependency**, breaking the property that
  preserves the MCP constraint. The moved functions are **not** pure path
  arithmetic — they enumerate and stat directories — but every primitive they
  use is C-core or `cl-lib`, so they add no `require`. Asserted as design I3, a
  dependency invariant checked against the require block, not a claim about the
  code's character.
- **Q1 — ANSWERED: `satan-run.el`.** Mostly deletion, not extraction — the
  broker sheds ~190 lines.
- **A1 — FALSIFIED.** `satan-tools-hippocampus.el:22` declares a third
  `satan-hippocampus-dir`; the scoping grep missed it. Replaced by F1 and by
  P2's exit criterion (b), which counts declarations across `satan/*.el` rather
  than grepping the two modules the slice happened to be looking at.

## Verification / closure intent

- **ADR-018 VT-2 holds of the tree at the phase gates.** Its three clauses map
  onto P2's exit criteria (design §9): exactly one `cl-defstruct satan-run` and
  one declaration of each defcustom across `satan/*.el`, and no symbol both a
  struct accessor and a `defun`. Measured, not enforced — no standing check is
  built (design D3); recurrence guarding is [[IMP-017]].
- **`satan-run-prepare` no longer exists as a defun**; `satan-run-new-ctx` does.
  Asserted via `documentation` / `funcall`, never a syntactic call — a syntactic
  call inlines the accessor and would pass either way, which is the trap that
  hid R1.
- **Both require cycles are gone**: `satan-budget.el` and `satan-observer.el`
  contain no reference to `satan-broker`.
- Full suite green, `just check` clean, **no new skips** against the recorded
  baseline of 1018 tests / 0 unexpected / 13 skipped.
- Design records a verdict on R1 with evidence either way. **Done — latent.**
