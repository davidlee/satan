# cl-defstruct accessor shadowed by a same-name defun


A `cl-defstruct` accessor is a `cl-defsubst` that installs a `compiler-macro`
property on the symbol. A later `defun` of the same name overwrites the
**function cell** but does **not** remove that property.

Consequences, both of which bit SL-013:

1. **Every syntactic call site inlines to the slot read** — interpreted *and*
   byte-compiled — because Emacs applies compiler-macros at macroexpansion,
   which happens on load. So a `(satan-run-prepare X)` written to test the
   defun silently tests the accessor. Only `funcall` / `apply` / `eval` reach
   the defun.
2. **Which definition wins the function cell depends on load order**, and any
   module that re-declares the same `cl-defstruct` puts the accessor back on
   top. Adding `(require 'satan-run)` to `satan-broker.el` — whose own
   `cl-defstruct satan-run` then loaded second — flipped a passing
   `(funcall 'satan-run-prepare …)` test red with no other change.

So the `funcall` escape hatch is not a stable way to reach a shadowed defun.
The only fix is to not shadow: rename one of them.

Verified 2026-07-24 under Emacs 31.0.90, SL-013 PHASE-02. Probe shape that
actually answers the question — note `-l`, never `--eval`, since `--eval` *is*
the eval escape hatch and reaches the defun regardless of the tree's state:

```sh
emacs --batch -L ./satan -l satan-run -l probe.el
# in probe.el: (documentation 'sym), (funcall 'sym S), and a syntactic (sym S)
```
