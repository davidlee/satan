# 03-SIZE.md — Size/shape census

## Files > 400 LOC

| LOC | File | Notes |
|---|---|---|
| 859 | `dl-satan-observer.el` | Largest file; 33 defuns; perceptual-layer Phase 5 |
| 797 | `dl-satan-broker.el` | 35 defuns; orchestration hub |
| 626 | `dl-satan-motive.el` | 22 defuns; motive file reader/renderer |
| 570 | `dl-satan-memory-canon.el` | 14 defuns + 7 `defrule` macro calls; canonicalizer + rules |
| 560 | `dl-satan-memory-evidence.el` | 25 defuns; evidence-window assembly |
| 554 | `dl-satan-tank.el` | 28 defuns; observation tank |
| 526 | `dl-satan-context.el` | 25 defuns; bundle assembly |
| 496 | `dl-satan-memory-migrate.el` | 22 defuns; migration runner |

**8 files** above the 400-LOC threshold. 2 files (`observer.el`, `broker.el`) exceed 700 LOC.

## Functions > 50 LOC

Measured by paren-balanced span over every `(defun|defmacro|defsubst|cl-defun|cl-defmacro)` form in `satan/dl-satan*.el`.

| LOC | File:line | Function |
|---|---|---|
| 157 | `dl-satan-broker.el:638` | `dl-satan-broker--spawn` |
| 76 | `dl-satan-sensor-alerts.el:320` | `dl-satan-sensor-alerts-check` |
| 71 | `dl-satan-memory-evidence.el:487` | `dl-satan-memory-evidence-assemble-with-bounds` |
| 69 | `dl-satan-observer.el:721` | `dl-satan-observer-process` |
| 69 | `dl-satan-memory-canon.el:190` | `dl-satan-memory-canon-normalize-hints` |
| 67 | `dl-satan-patch-inbox.el:12` | `dl-satan-patch-inbox--render-body` |
| 65 | `dl-satan-patch-worktree.el:81` | `dl-satan-patch-worktree-create` |
| 61 | `dl-satan-tools-hippocampus.el:34` | `dl-satan-tools-hippocampus--cross-ref` |
| 61 | `dl-satan-tools-patch.el:87` | `dl-satan-tool/patch-job-create` |
| 61 | `dl-satan-motive.el:174` | `dl-satan-motive--parse-motive` |
| 58 | `dl-satan-patch-adapter-pi.el:168` | `dl-satan-patch-adapter-pi--sentinel` |
| 58 | `dl-satan-memory-store.el:312` | `dl-satan-memory-store-recent` |
| 56 | `dl-satan-patch-adapter-pi.el:253` | `dl-satan-patch-adapter-pi-invoke` |
| 54 | `dl-satan-patch-store.el:177` | `dl-satan-patch-store-insert` |
| 54 | `dl-satan-patch-runner.el:178` | `dl-satan-patch-runner--finish-success-path` |
| 53 | `dl-satan-tank.el:237` | `dl-satan-tank--render-last-run` |
| 52 | `dl-satan-tank.el:402` | `dl-satan-tank--last-run-state` |
| 52 | `dl-satan-motive.el:344` | `dl-satan-motive-render-block` |
| 51 | `dl-satan-observer.el:614` | `dl-satan-observer--persist-positive` |

**19 functions** exceed 50 LOC. The largest is `dl-satan-broker--spawn` at 157 LOC.

(Earlier draft of this file overstated several entries — e.g. `normalize-hints` at 296 LOC and `patch-store--parse-row` at 238 LOC — because the LOC counter treated trailing top-level macro calls as part of the preceding defun. Replaced with a paren-balanced count above.)

## Functions > 6 args

**None found.** All function signatures stay within reasonable parameter counts. `cl-defun` keyword-arg signatures (e.g. `dl-satan-patch-store-insert`) carry many `&key` slots but no positional args.

## Nesting depth (sampled)

No automated elisp-nesting tool in scope. Spot-checked the 4 largest functions in the table above, max nesting depth observed (counting binding/branching forms `let`/`let*`/`if`/`cond`/`when`/`pcase`/`dolist`/`cl-loop`/`lambda`):

| File:line | Function | Observed max depth | Note |
|---|---|---|---|
| `dl-satan-broker.el:638` | `--spawn` | 5 | nested `let*` chain (3 deep) + per-form `let*` body |
| `dl-satan-memory-canon.el:190` | `normalize-hints` | 5 | outer `let` → per-field `let`/`let*` → `cond` → `push` → `list` |
| `dl-satan-memory-store.el:196` | `--build-mark-payload` | 4 | `let` → `vconcat`/`mapcar` → `lambda` → `list` |
| `dl-satan-patch-store.el:157` | `--parse-row` | 4 | `let*` → `cl-loop` → `setq plist-put` → `pcase` |

No function in the top-20 nests > 5 deep on visual inspection. `broker--spawn` is the most pattern-heavy: a 3-level `let*` accumulator using repeated `plist-put` chaining around the run-ctx record.

## Files with > 20 top-level definitions

| Count | File |
|---|---|
| 35 | `dl-satan-broker.el` |
| 33 | `dl-satan-observer.el` |
| 28 | `dl-satan-tank.el` |
| 25 | `dl-satan-memory-evidence.el` |
| 25 | `dl-satan-context.el` |
| 22 | `dl-satan-motive.el` |
| 22 | `dl-satan-memory-migrate.el` |
| 20 | `dl-satan-sensor-alerts.el` |

## Macros / metaprogramming

| Path:line | Form |
|---|---|
| `dl-satan-memory-canon.el:114` | `(defmacro dl-satan-memory-canon-defrule …)` — canonicalization rule registrar; emits a `defun` + side-effect into the rule registry. 7 in-file callers (`defrule` invocations between L264–end). |
| `dl-satan-tank.el:494` | `(define-derived-mode dl-satan-tank-mode special-mode "SatanTank" …)` — major-mode definition. |

No other `defmacro` / `defsubst` / `define-derived-mode` / `define-minor-mode` in `satan/dl-satan*.el`. Total metaprogramming surface: 1 DSL macro + 1 major-mode definition.
