# IMP-017: Structural duplicate-body check: detect renamed clones the symbol-keyed lint cannot see

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Origin

SL-013 lands `tools/elisp-duplicate-definitions.el` as ADR-018 **VT-2**: a
standing lint forbidding a symbol being defined twice in `satan/*.el`. RV-002
**F-2** established the bound on what that proves.

The lint is keyed on the **symbol**. SL-013's own subject matter divides as:

- **4** same-name duplications — `cl-defstruct satan-run`, `satan-runs-dir`,
  `satan-hippocampus-dir`, `satan-broker--spawn-running`. The lint catches these.
- **7** same-body/different-prefix forks — `satan-broker--mint-run-id`,
  `--iso-time-format`, `--prepare`, `--failed-suffix`,
  `--date-bucket-for-run-id`, `satan-broker-run-dir-for-id`, `--tool-ctx`. The
  lint is **blind** to all seven, because each wears a different name.

So VT-2 establishes *single-definition*, not *single-implementation* — and the
larger half of the duplication that motivated the slice is the half it cannot
see. SL-013 records the limitation (design §2.1, §7 D3, §9) rather than widening
its own scope.

## What would close it

A canonical-body hash across the tree — mechanising the comparison SL-013's
design §2.2 performed by hand:

1. Read each top-level `defun` / `defsubst` / `defmacro` / `defconst` /
   `defcustom` / `cl-defstruct` as a sexp.
2. Canonicalise: elide docstrings, strip the module prefix from the defined
   symbol and from self-references, normalise whitespace and comments.
3. Hash. Two definitions with different names and the same canonical hash are a
   fork; report both sites.

Open sub-questions: the false-positive rate on genuinely-similar-but-distinct
small predicates; whether prefix-stripping is a principled normalisation or one
tuned to this tree; whether a size floor is needed to suppress trivial
one-liners.

## Why it matters beyond elisp

ADR-018 **D4.2** migrates a policy / registry **data** table. Its Consequences
already warn that D4.2 "must land as a cutover, not an addition" and name the
`satan-run.el` clone as proof this project fails that way by default. A
duplicated table will look exactly like these seven renamed forks — the shape
this lint cannot detect. Whoever plans D4.2 must know VT-2 does not cover it.

Relates to SL-013 design **OQ-3**: whether this generalises, or is superseded by
a Rust-side check once the tables move, is deliberately not foreclosed here.
