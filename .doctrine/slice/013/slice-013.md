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
- **Land ADR-018 VT-2 as a standing lint**, beside `bin/elisp-locate-paren-error`
  and wired into `just lint`: exactly one definition of the struct and of each
  defcustom, and no symbol defined both as a struct accessor and as a `defun`.
  The generic form is the point — this class of collision must not be
  re-introducible, in this pair or any other.
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
  the objectives above or flagged by the new lint: a third
  `satan-hippocampus-dir` in `satan-tools-hippocampus.el` (F1); `satan-context.el`
  using `satan-run-*` with no require (F3); `satan-broker--spawn-running` defined
  with a value in two modules (F4); `satan-mcp--mint-session` hand-rolling a
  4-key run-ctx instead of the canonical 10-key constructor (F5).
- **Retire the DEC-8 soft-coupling in both directions** (design D6, from the
  adversarial pass). Mutual exclusion is a *two*-flag protocol and each module
  reaches into the other: MCP reads the broker's `spawn-running`, and the broker
  reads `satan-mcp--session-active` behind a `boundp` guard at `:739`. Both flags
  move to the leaf; the guard goes. Not forced by the lint — `session-active` is
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
  coverage *is* the characterisation suite; P2 retargets it into
  `satan-run-test.el` before anything moves.
- **R3 — CLOSED on evidence.** All three defcustom declarations carry identical
  default expressions, and `defcustom` sets a default only when unbound — so
  collapsing changes **no value**, and a keeper's `custom-set-variables` binds
  the shared symbol either way. Only the docstring surface changes; the
  surviving declaration must keep the union (the broker's docstrings are the
  richer ones and are the copies being deleted).
- **R5 — NEW: docstring loss.** The deleted copies are the better-documented
  ones. A reviewer must diff docstrings, not just symbol lists.
- **R6 — NEW: a missed rename site.** Mitigated by tests running interpreted —
  every miss is a void-function/void-variable at load — plus a zero-hit grep as
  P4's exit criterion.
- **R7 — NEW: the leaf acquires a dependency**, breaking the property that
  preserves the MCP constraint. The moved functions are pure path arithmetic and
  add no `require`; asserted as design I3 and checked by inspection.
- **Q1 — ANSWERED: `satan-run.el`.** Mostly deletion, not extraction — the
  broker sheds ~190 lines.
- **A1 — FALSIFIED.** `satan-tools-hippocampus.el:22` declares a third
  `satan-hippocampus-dir`; the scoping grep missed it. Replaced by the lint,
  which makes the property standing rather than grep-verified.

## Verification / closure intent

- **ADR-018 VT-2 passes as a lint** in `just lint`, and fails on a deliberately
  re-introduced duplicate — struct, defcustom, valued `defvar`, and
  accessor/defun collision — while **passing** on a valueless `(defvar x)`
  forward declaration.
- **`satan-run-prepare` no longer exists as a defun**; `satan-run-new-ctx` does.
  Asserted via `documentation` / `funcall`, never a syntactic call — a syntactic
  call inlines the accessor and would pass either way, which is the trap that
  hid R1.
- **Both require cycles are gone**: `satan-budget.el` and `satan-observer.el`
  contain no reference to `satan-broker`.
- Full suite green, `just check` clean, **no new skips** against the recorded
  baseline of 1018 tests / 0 unexpected / 13 skipped.
- Design records a verdict on R1 with evidence either way. **Done — latent.**
