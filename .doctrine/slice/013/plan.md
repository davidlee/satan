# Implementation Plan SL-013: Collapse the satan-run / satan-broker run-context duplication

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Cite entities by padded id (SL-020, REQ-059); phases as PHASE-01,
     criteria as EN-1/EX-1/VT-1/VA-1/VH-1. See .doctrine/glossary.md § reference forms. -->

## Overview

Three phases, taken straight from design §5.4: characterise, collapse, move.
The plan adds nothing to the design's shape — it makes the exit criteria
executable and closes the phase seam the design left implicit (see **PHASE-02
EX-6** below).

The slice is mostly **deletion**. `satan-broker.el` sheds ~190 lines and
`satan-run.el` gains ~120; nothing new is designed, no behaviour changes
(**C2**), and no tooling is built (**D3**). The risk is therefore not "will the
new code be right" but "will a fork survive the collapse unnoticed" — which is
why every phase exits on a zero-hit grep over its own deleted set rather than on
a green suite.

## Sequencing & Rationale

### Why characterisation leads, and why the rename does not

R1 is settled as **latent** (EVD-001, design §10): `cl-defstruct` accessors are
`cl-defsubst`s that install a `compiler-macro` property which `defun` does not
remove, so every syntactic call site inlines to the slot read — interpreted and
compiled alike. All four in-tree call sites are syntactic, and no `funcall` /
`apply` / `#'satan-run-prepare` exists. Nothing is broken today, so the rename
need not lead. The phase order rests on that verdict, which RV-002 reproduced
independently under Emacs 31.0.90 rather than taking on trust.

What *does* need to lead is coverage. `satan-run.el` has no test file. Design
§2.2 proved the clones byte-identical modulo docstrings, which is what
downgraded R2 — the broker side of the collapse is pure deletion, so the
broker's existing tests *are* the characterisation suite. But that argument
**expires the moment PHASE-02 begins**, because after the collapse those tests
exercise the survivor through the deleted names. PHASE-01 retargets the coverage
onto `satan-run.el` while the equivalence still holds.

### The trap PHASE-01 has to step around

PHASE-01 must characterise the ten-key run_ctx constructor, still named
`satan-run-prepare` at that point — the same symbol as the struct accessor. A
syntactic `(satan-run-prepare mode)` in the new test would **inline the
accessor** and pass against the wrong function. That is precisely the mechanism
that hid R1 behind two false explanations for as long as it did.

So PHASE-01 **EX-2** requires `(funcall 'satan-run-prepare mode)`. After
PHASE-02's rename, `satan-run-new-ctx` is unambiguous and the test can call it
syntactically. This is the one place the phase order costs anything, and it
costs one `funcall`.

### The PHASE-02 / PHASE-03 seam — the design's implicit step

Design §5.2 lists `satan-broker--failed-suffix` and
`satan-broker--date-bucket-for-run-id` in the **deletion** table (PHASE-02),
while §5.4 keeps the layout cluster in the broker until **PHASE-03**. But
`satan-broker-locate-run-dir` closes over both, and
`satan-broker--run-id-from-leaf` over `--failed-suffix`. Deleting the constants
in PHASE-02 without repointing the cluster's bodies is a load-time break.

The resolution is cheap and does not disturb the design: PHASE-02 adds
`(require 'satan-run)` to the broker anyway, so the cluster repoints to
`satan-run--failed-suffix` / `satan-run--date-bucket` in place, and PHASE-03
moves already-correct bodies. **PHASE-02 EX-6** and **VA-5** make that explicit
rather than leaving it to be found at the point of failure. (§5.4's PHASE-03
grep re-lists both names — harmless redundancy, since they are gone one phase
earlier.)

### Why both DEC-8 flags move together

F4 reads like a one-line deletion — remove `satan-mcp.el:26`'s duplicate
`defvar`. It is not. MCP cannot `require` the broker without destroying **C1**,
the constraint that produced the clone in the first place, and a valueless
forward declaration leaves the variable *unbound* — so `satan-mcp.el:165`
becomes a void-variable crash in every image that loads MCP without the broker,
which is exactly what `satan-mcp-test.el` does. The deletion is safe only as the
tail of the move to the leaf, so F4 and F7 are one operation in PHASE-03 (design
§5.3). **PHASE-03 VA-4** exercises that failure mode directly rather than
trusting the argument.

### What the gates are for

RV-002 **F-1** was a blocker: AR-3's standard — a phase may not pass its own gate
with its work undone — had been applied to one phase and no other. The collapse
phase's original exit was satisfiable with nine of its ten deletions still
standing, and the characterisation phase's was the bare word "Green". A green
suite **cannot** detect a surviving clone, because §2.2 proves the clones are
identical.

Hence the VA rows demand per-symbol reporting, not a summarised verdict. The
`EX-` ids in `plan.toml` are immutable once authored, and a vacuous exit
criterion becomes the standard the phase is recorded as having met.

### ADR-018 VT-2

VT-2 asserts a property of the tree and notes in passing that it is "enforceable
as a lint check" — the same feasibility clause VT-3 writes as "Grep-able". This
slice discharges it by **measurement at the phase gates**, not by building a
standing check (design **D3**): PHASE-02 **EX-2** and **EX-3** assert its three
clauses, symbol by symbol, at the moment the risk is live, and PHASE-03 **VA-5**
re-runs the count against the final tree. Standing enforcement — and the
structural body-hash check that would catch the seven *renamed* forks a
symbol-keyed check cannot see (RV-002 **F-2**) — is deferred to **IMP-017**, with
the cost bar recorded there.

### Verification modes

Most criteria here are absence assertions: a deleted symbol, a dissolved cycle,
a removed guard. The structured VT mandate is presence-only, so the greps are
**VA** rows and the VT rows assert what must *exist* afterwards — the leaf owning
each moved symbol, and each former reacher carrying a hard `(require 'satan-run)`.
Read together they bracket the change from both sides.

## Notes

- **Baseline** (design §2.4, PHASE-01 EN-2): 1018 tests / 1005 as expected /
  0 unexpected / 13 skipped. Every skip is a corpus-integration or DB
  `skip-unless`. "No new skips" is a real criterion here — a `require` that
  fails silently converts a passing test into a skip.
- **Tests run interpreted** (`emacs --batch`, never byte-compiled), which is the
  mitigation for R6: a missed rename site is a void-function or void-variable at
  load, not a silent fallthrough.
- **I4** — a valueless `(defvar x)` is a declaration, never a definition. The
  counting in PHASE-02 VA-2 must encode this, or legitimate cycle-breakers read
  as duplicates.
- **R5 is not uniform.** The broker is the richer docstring side for five of the
  cloned bodies; `satan-run.el` is richer for `mint-id`, whose broker copy has no
  docstring at all. PHASE-02 EX-7 requires the union in *both* directions.
- **The exit greps reach further than the design's code-impact table did.** A
  tree-wide census at plan time found the old names in three files the table did
  not list — `satan-percept.el:14`, `satan-audit.el:26` and
  `satan-percept-test.el:50` all name `satan-broker--prepare` in prose as the
  allocator of the run_ctx plist. Comments, not code, but PHASE-02's EX-1 grep is
  over the tree and will hit them, which is the point of writing it that way.
  The design's §5.4 table and the `design-target` selectors were completed
  accordingly. The same census confirms the remaining sites — `cl-letf` /
  `symbol-function` stubs in three test files, and `satan-budget-test.el`'s
  `(require 'satan-broker)`, held only for `run-dirs-for-date` — were already
  declared.
- **PHASE-02 is the large one** and its intra-phase order is not free. Recommended
  sequence for the phase sheet: (1) add `(require 'satan-run)` to satan-broker.el;
  (2) rename the defun to `satan-run-new-ctx` in the leaf and repoint
  `satan-run-tool-ctx`'s own call; (3) delete the broker's struct and defcustoms;
  (4) delete the six cloned bodies one at a time, repointing call sites as each
  goes, with the two constants last so EX-6's repointing of the surviving layout
  cluster is deliberate rather than forced; (5) F1, F3, F5, F6. Load-time
  breakage is the feedback signal throughout — tests run interpreted, so a missed
  site is a void-function at load, not a silent pass.
- Out of scope throughout: the broker's ~980-line spawn/filter/sentinel/finalize
  body (ADR-018 D4.4 sequences it last), any extraction, and any change to the
  ADR-017 §3 authority ledger — which does not exist yet.
