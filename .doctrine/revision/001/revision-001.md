# REV REV-001 — reconcile SL-013

Revision (ADR-013) — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

SL-013's reconciliation audit ([[RV-003]]) raised one `major` finding against
governance rather than against the implementation.

**[[RV-003]] F-1 (major) — ADR-018's Context asserts a mechanism EVD-001
falsified.** The fifth Context bullet ("POL-001 trigger 1 has fired…") records
the `satan-run-prepare` accessor/`defun` collision as **latent**, and credits
that latency to byte-compiled callers having inlined `(aref run-ctx 18)` before
the clobber. The verdict is right; the mechanism is wrong, and it is wrong in a
load-bearing direction: byte-compilation as the stated cause implies that an
interpreted tree is exposed. SATAN's tests run **interpreted** (SL-013 design
**C5**), so a future reader could reason from the ADR's own wording back into
the hazard it was written to record.

The operative mechanism, recorded in full as SL-013 **EVD-001** and re-verified
under Emacs 31.0.90 during [[RV-002]]: `cl-defstruct` accessors are
`cl-defsubst`s, which install an inliner on the symbol's **`compiler-macro`
property**, and `defun` does not remove it. Emacs applies compiler-macros at
macroexpansion — i.e. as each top-level form loads — so every *syntactic* call
site inlines to the slot read, **interpreted and byte-compiled alike**.

**[[RV-003]] F-2 (minor) — the correction must carry the load-order refinement.**
EVD-001's `funcall` / `apply` / `eval` rows are not unconditional: they describe
whichever definition load order left in the symbol's **function cell**. SL-013
PHASE-02's first edit (adding `(require 'satan-run)` to `satan-broker.el`) put
the leaf first in load order, the broker's own `cl-defstruct` re-installed the
accessor over the `defun`, and those rows flipped — turning the suite red. The
escape hatch was never a stable property of the symbol; only the PHASE-02 rename
made the symbol single-meaning. The amended Context must say so, otherwise it
replaces one false safety condition with another.

F-2's per-slice half — the same qualification against SL-013 `design.md` §10 —
was landed by direct edit in the same reconcile pass, not by this REV.

Sources: SL-013 `design.md` §10 (EVD-001 call-form matrix and the paragraph
beneath it); SL-013 `notes.md`, 2026-07-24 PHASE-02, *"EVD-001 refined — the
`funcall` row is load-order-contingent"*.

## Change rows

### C1 — `modify` ADR-018 (primary)

Prose-body edit to the **Context** section, fifth bullet ("POL-001 trigger 1 has
fired, and the copy-instead-of-extract failure has already happened once"). The
bullet's first half — the clone census (`cl-defstruct satan-run`, the two
`defcustom`s, the forked `mint-id` / `prepare` / `dir-for-id` / `tool-ctx`, and
the `satan-run.el:27` / `:77` collision itself) — is accurate and unchanged.
Only the sentence stating *why* the collision is latent is replaced.

**Before** (`adr-018.md`, from *"Verified"* to the end of the bullet):

> `(defun satan-run-prepare (mode) ...)` over the top of it. Verified
> empirically: the collision is currently **latent** — cl-defstruct accessors
> inline at load time, so existing callers compiled to `(aref run-ctx 18)`
> before the clobber — but a direct `(satan-run-prepare run-struct)` silently
> returns a freshly minted `run_id` with an unfrozen `time_now` instead of the
> frozen prepare plist, with no error. Its disarming depends on load order and
> on slot index 18 matching across two independent struct definitions.

**After:**

> `(defun satan-run-prepare (mode) ...)` over the top of it. Verified
> empirically (SL-013 EVD-001, design §10): the collision is currently
> **latent**, but not for the reason first recorded here. `cl-defstruct`
> accessors are `cl-defsubst`s, which install an inliner on the symbol's
> **`compiler-macro` property** that `defun` does not remove; Emacs applies
> compiler-macros at macroexpansion — i.e. as each top-level form loads — so
> every *syntactic* call site inlines to the slot read, **interpreted and
> byte-compiled alike**. Byte-compilation is not the operative mechanism, and
> this project runs its tests interpreted. The non-syntactic forms —
> `(funcall 'satan-run-prepare …)`, `apply`, `eval` — reach whichever
> definition load order left in the **function cell**, and reaching the `defun`
> silently returns a freshly minted `run_id` with an unfrozen `time_now`
> instead of the frozen prepare plist, with no error. That escape hatch was
> never stable: SL-013 PHASE-02's first edit added a `require` and flipped it.
> Only the rename made the symbol single-meaning; the residual fragility was
> slot index 18 matching across two independent struct definitions.

**Scope guard.** This amends a Context observation only. No **Decision** (D1–D8),
consequence or verification criterion of ADR-018 moves, and no ADR-017 §3
authority item changes owner. The bullet's role in the ADR — evidence that
POL-001 trigger 1 fired and that copy-instead-of-extract already happened — is
unchanged and, with the sharper mechanism, better supported.

**Canon note.** The project's governance corpus was imported from `.emacs.d` on
2026-07-22 and is *frozen for SATAN*: that rule governs **id resolution** for
imported prose, not mutability. ADR-018 was authored and accepted in this repo
(`.doctrine/adr/018/`), so it resolves locally and a local REV is the correct
mechanism. This is the first governance amendment in this repo since the import.
