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

**The live hazard.** `satan-run.el:27`'s struct generates the accessor
`satan-run-prepare`; `satan-run.el:77` then defines `(defun satan-run-prepare
(mode) …)` over that same symbol. `satan-broker.el` reads the slot at three
sites (`:284`, `:406`, `:449`). A call that resolves to the defun instead of
the accessor silently returns a freshly minted run_id with an unfrozen
`time_now` — no error, wrong value.

Two independent accidents currently disarm it: the two structs declare
identical slot lists in identical order (18 slots, `prepare` last), so the slot
index agrees; and byte-compiled callers inline the accessor before the clobber
can land. **Neither is a guarantee.** `satan-broker.el` does not require
`satan-run`, so whether the defun wins depends on whether `satan-mcp.el` has
loaded — i.e. on load order. And this project's tests run interpreted
(`emacs --batch`, never byte-compiled), where accessors resolve through the
symbol rather than inlining. Whether the hazard is reachable in the interpreted
path is the first thing `/design` must settle; the scope here does not assume
an answer.

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
- **`satan-mcp.el`'s session model** beyond the require and whatever call sites
  the rename touches.

## Risks, assumptions, open questions

- **R1 — the interpreted path may make the collision live, not latent.** If so
  the slice is a bug fix under a refactor's name, and the phase order should
  put the rename first. Design must test this rather than inherit the prior
  audit's "latent" verdict, which reasoned from byte-compiled inlining.
- **R2 — `satan-run.el` is untested.** Any collapse is a refactor without a net
  on that half; characterisation tests likely precede the move.
- **R3 — defcustom collapse is user-visible.** If the keeper has customised
  `satan-runs-dir` or `satan-hippocampus-dir`, removing one definition changes
  which declaration a saved custom value binds against.
- **Q1 — which module ends up owning the struct?** `satan-run.el` is the
  smaller, dependency-light leaf and the natural owner; `satan-broker.el` holds
  every real caller. Design decides; the answer determines whether this is
  mostly deletion or mostly extraction.
- **A1 — assumed**: no third module declares a `satan-run` struct or these
  defcustoms. Verified by grep at scoping; the new lint makes it standing.

## Verification / closure intent

- **ADR-018 VT-2 passes as a lint** in `just lint`, and fails on a deliberately
  re-introduced duplicate.
- **`satan-run-prepare` no longer exists as a defun**; `satan-run-new-ctx` does.
- Full suite green, `just check` clean, no new skips.
- Design records a verdict on R1 with evidence either way.
