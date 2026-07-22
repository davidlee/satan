# EVD-001: cl-defstruct accessor survives a defun clobber via its compiler-macro

## Claim

When a `defun` is written over a symbol that a `cl-defstruct` already generated
as a slot accessor, the accessor keeps winning at **every syntactic call site**
— in interpreted *and* byte-compiled code. The defun is reached only through
**indirect** dispatch.

## Mechanism

`cl-defstruct` defines accessors as `cl-defsubst`s. That installs two things:

1. the accessor lambda in the symbol's **function cell**, and
2. an inliner on the symbol's **`compiler-macro` property**
   (here: `satan-run-prepare--inliner`).

A later `defun` overwrites (1) but leaves (2) intact. Emacs macroexpands
top-level forms as it loads them, and macroexpansion applies compiler-macros —
so `(satan-run-prepare x)` written literally expands to the slot read before the
function cell is ever consulted. Byte- and native-compilation do the same thing,
which is why the compiled path is safe too.

## Measurements

Against `satan/satan-run.el:27` (struct, generates accessor) and
`satan/satan-run.el:77` (defun over the same symbol), loaded after
`satan-broker.el`:

| Call form | Resolves to |
|---|---|
| `(satan-run-prepare s)` — syntactic, interpreted | accessor (frozen plist) |
| interpreted `(lambda (x) (satan-run-prepare x))` | accessor |
| `(byte-compile (lambda (x) (satan-run-prepare x)))` | accessor |
| `(funcall 'satan-run-prepare s)` | **defun** (fresh `run_id`) |
| `(apply #'satan-run-prepare (list s))` | **defun** |
| `(eval '(satan-run-prepare s) env)` | **defun** |

`(documentation 'satan-run-prepare)` returns the *defun's* docstring throughout,
confirming the function cell really is clobbered. Both load orders
(`broker`→`run` and `run`→`broker`) give the same result, so load order is not
the variable.

## Consequences

- The hazard is **narrower and sharper** than "wrong value at three call sites":
  it is dormant until someone writes `(mapcar #'satan-run-prepare runs)`, advises
  the symbol, or `cl-letf`s it — then it silently returns a freshly minted
  `run_id` with an unfrozen `time_now`, with no error.
- Two governance statements are factually wrong and need correcting at
  reconcile: ADR-018's Context attributes the latency to byte-compilation, and
  SL-013 R1 hypothesises load-order dependence.
- A lint cannot detect this class by loading the package — after load the
  duplicate has already overwritten its predecessor and is invisible. Detection
  must be a **source/sexp parse**. See [[SL-013]].
