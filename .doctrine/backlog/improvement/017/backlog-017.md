# IMP-017: Standing duplicate-definition check for satan/*.el, incl. renamed clones (ADR-018 VT-2 recurrence guard)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Origin

SL-013 collapses the `satan-run.el` / `satan-broker.el` duplication and
discharges ADR-018 **VT-2** by measurement — its phase exit criteria grep the
actual symbols, and the tree is clean when they pass. It deliberately builds
**no standing check**; SL-013 design **D3** carries the cost/benefit. This item
holds the whole deferred question: whether `satan/*.el` should have a standing
duplicate-definition guard, and if so what shape.

## Two halves, and only one is the obvious one

**Same-symbol duplication.** A symbol defined twice — `cl-defstruct satan-run`,
`satan-runs-dir`, `satan-hippocampus-dir`, `satan-broker--spawn-running` in the
pre-SL-013 tree. Cheap to detect from a source parse. This is what VT-2's
"enforceable as a lint check" note gestures at.

**Same-body, different name.** Seven of SL-013's eleven duplications were this:
`satan-broker--mint-run-id`, `--iso-time-format`, `--prepare`,
`--failed-suffix`, `--date-bucket-for-run-id`, `satan-broker-run-dir-for-id`,
`--tool-ctx` — each byte-identical in body to a `satan-run.el` counterpart
under a different prefix. Invisible to any symbol-keyed check (RV-002 **F-2**),
and the more expensive half: two copies drift in docstrings and one gets fixed.

A check that does only the first half certifies a tree that still violates the
principle. That asymmetry is the reason this is one item and not two.

## Sketch — the structural half

Mechanising the comparison SL-013 design §2.2 ran by hand:

1. Read each top-level `defun` / `defsubst` / `defmacro` / `defconst` /
   `defcustom` / `cl-defstruct` as a sexp.
2. Canonicalise: elide docstrings, strip the module prefix from the defined
   symbol and from self-references, normalise whitespace and comments.
3. Hash. Different names, same canonical hash ⇒ a fork; report both sites.

Open sub-questions:

- False-positive rate on genuinely-similar-but-distinct small predicates; a size
  floor may be needed to suppress trivial one-liners.
- Whether prefix-stripping is a principled normalisation or one tuned to this
  tree.
- **From SL-013 OQ-2:** `:include` inheritance in `cl-defstruct` accessor
  derivation — implement, or document the limitation. Unused in this tree today.
- Scope stays `satan/*.el`, non-recursive, excluding `satan/test/` where files
  legitimately shadow helpers (SL-013 AR-6). A check widened to `**` gets noisy,
  then gets weakened.

## The cost bar it has to clear

SL-013 declined to build the symbol-keyed half on these numbers, and this item
inherits them:

- The class has recurred **three** times in this tree and cost **nothing** each
  time — every instance was latent or benign (SL-013 R1 §10, F1, F3, F4).
- `cl-defstruct` accessor derivation has four shapes (options list,
  `:conc-name`, docstring-after-name, `(slot default)` specs) that **this tree
  never exercises**, so fixtures are the only thing between the check and
  accidental correctness.

So the trigger for doing this work is not "duplication is bad in principle".
It is a *live* recurrence that costs something, or the D4.2 need below.

## Why D4.2 may supply that trigger

**From SL-013 OQ-3.** ADR-018 D4.2 migrates the policy / tool-registry table to
the daemon, and its Consequences already warn:

> "D4.2 must land as a cutover, not an addition. The `satan-run.el` clone is
> proof this project fails that way by default; a duplicated policy table would
> be materially worse than a duplicated struct."

A duplicated *table* is a renamed fork, or it is not elisp at all. Either way a
symbol-keyed elisp lint does not see it. Whoever plans D4.2 must know VT-2 does
not cover it, and should decide there whether the check that matters is the
structural one above or a Rust-side equivalent spanning both languages. Not
foreclosed here.
