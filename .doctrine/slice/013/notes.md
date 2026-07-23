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

## 2026-07-23 — PHASE-01 complete

`satan/test/satan-run-test.el` lands with 9 ert tests. Suite 1018 → **1027, 0
unexpected, 13 skipped** (same skip set). Diff touches that one file; nothing
under `satan/*.el`.

### EVD-001 re-verified against the live tree

Probe matrix over the shipped `satan-run.el`, before any change:

| call context | resolves to |
|---|---|
| top-level form in a loaded `.el`, interpreted | ACCESSOR |
| inside a `lambda` / `defun`, interpreted | ACCESSOR |
| byte-compiled caller | ACCESSOR |
| `(eval FORM)` / `emacs --eval` | **DEFUN** |
| `funcall` / `apply` | **DEFUN** |

Loaded source inlines the accessor on **both** eval paths, exactly as design §10
states. The verdict *latent* stands unamended, and `satan-run.el:103` is the
accessor read — confirmed live, `satan-run-tool-ctx` returns the frozen
`:time_now`. Direct evidence: writing PHASE-01's constructor test syntactically
expands to `(aref X 18)` guarded by `cl-struct-satan-run-tags` — slot 18 is
`prepare`. EX-2's `funcall` requirement is load-bearing, not ceremony.

### New trap — `emacs --eval` cannot verify the collision

`emacs --eval` **is** the `eval` escape hatch listed above, so a one-liner probe
reaches the defun no matter what the tree contains: before and after the rename
look identical through it. It cannot verify PHASE-01 EX-2 or PHASE-02 EX-3.
Check through a *loaded file* only. This is why PHASE-02 VA-3 says "in a loaded
image"; the reason is now on record. Cost one false "the design is wrong" reading
during PHASE-01 planning.

### Reconcile debt — VA-1's `.FAILED` clause

PHASE-01 VA-1 asks that "the `.FAILED` / legacy-flat branch of `dir-for-id`" be
exercised. **Neither `satan-run-dir-for-id` nor its broker twin has any `.FAILED`
handling** — the bodies are identical (§2.2) and the second branch is
legacy-flat only. `.FAILED` belongs to the layout cluster
(`--run-id-from-leaf`, `locate-run-dir`), PHASE-03's move. Discharged as the
legacy-flat branch **plus** a test pinning `satan-run--failed-suffix` = `.FAILED`
— a constant with zero consumers today that PHASE-02 EX-6 makes the broker's
surviving cluster depend on. Requirement met, criterion's noun loose. A line at
reconcile, not a gap.

### Incidental

`satan-run-prepare`-the-defun has **no caller in the tree**. The three references
outside `satan-run.el` (`satan-broker.el:284/406/449`) are all syntactic accessor
reads on a run-ctx struct; the broker mints via its own `satan-broker--prepare`.
PHASE-02's F5 gives the constructor its first consumer.

### Historical numbering

Design §10's adversarial pass and the RV-002 record were written against a
five-phase table. The lint cut collapsed it to three (P2→P1, P3→P2, P4→P3),
free because no `plan.toml` existed yet. §10 carries a note; AR-4 and AR-6 are
marked MOOT with their transferable content retained.
