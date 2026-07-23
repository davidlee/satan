# Notes SL-013: Collapse the satan-run / satan-broker run-context duplication

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## 2026-07-23 — design locked, plan authored, slice ready

Design → inquisition (RV-002) → penances → lint cut → plan. No source file has
been touched; every commit so far is `.doctrine/`.

### Traps carried forward into implementation

- **Never call `satan-run-prepare` syntactically to test the constructor.** The
  struct accessor of that name installs a `compiler-macro` property that `defun`
  does not remove, so a syntactic call inlines to the slot read — interpreted
  *and* compiled. Only `funcall` / `apply` / `eval` reach the defun. This is
  EVD-001, and it is what hid R1 behind two false explanations (ADR-018's
  Context credits byte-compilation, the original R1 credited load order; both
  wrong). PHASE-01 EX-2 encodes it.
- **PHASE-02 must repoint the layout cluster before PHASE-03 moves it.**
  `satan-broker-locate-run-dir` and `--run-id-from-leaf` close over
  `satan-broker--failed-suffix` / `--date-bucket-for-run-id`, which PHASE-02
  deletes. See PHASE-02 EX-6.
- **F4 is not a one-line deletion.** Removing `satan-mcp.el:26`'s duplicate
  `defvar` before the flag reaches the leaf leaves `satan-mcp.el:165` reading an
  unbound variable in any image that loads MCP without the broker — which
  `satan-mcp-test.el` does. F4 and F7 are one operation, PHASE-03.
- **The docstring union runs in both directions.** The broker is the richer side
  for five bodies; `satan-run.el` is richer for `mint-id`, whose broker copy has
  no docstring at all. PHASE-02 EX-7.
- **`(defvar x)` with no value is a declaration, not a definition** (I4). Any
  duplicate-counting must encode this or legitimate cycle-breakers read as
  duplicates.

### Debt this slice creates or inherits

- **Reconcile debt against ADR-018.** Its Context states the wrong mechanism for
  the accessor/defun collision. A REV at reconcile, not a hand-edit of an
  accepted ADR.
- **IMP-017** carries the withdrawn standing check: both halves (same-symbol and
  same-body/different-name), the canonical-body-hash sketch, absorbed OQ-2 and
  OQ-3, and the cost bar a future attempt must clear.
- **RV-002 F-2 re-based, not falsified.** Its remedy — "record the limitation,
  backlog the structural check" — still holds, but the limitation is now
  recorded against the phase gates rather than against a lint that no longer
  exists. Not re-opened; noted so audit does not read it as drift.

### Historical numbering

Design §10's adversarial pass and the RV-002 record were written against a
five-phase table. The lint cut collapsed it to three (P2→P1, P3→P2, P4→P3),
free because no `plan.toml` existed yet. §10 carries a note; AR-4 and AR-6 are
marked MOOT with their transferable content retained.
