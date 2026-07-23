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

## 2026-07-24 — PHASE-02 complete

Three commits (`1b46bc5`, `5bedf03`, `dcb1d94`). `satan-broker.el` −149 lines;
`satan-run.el` +44. Suite **1027 → 1029, 0 unexpected, 13 skipped**, skip set
identical. All eight EX and six VA discharged; VA-1's control grep returned 27
hits, so the seven zeros are a real search result and not a broken invocation.

### EVD-001 refined — the `funcall` row is load-order-contingent

**T1 alone turned the suite red**, and the reason is worth keeping. Adding
`(require 'satan-run)` to `satan-broker.el` put the leaf *first* in load order,
so `satan-broker.el`'s own `cl-defstruct satan-run` then re-installed the
accessor **over the defun's function cell**. PHASE-01's
`(funcall 'satan-run-prepare …)` began reaching the accessor and
`satan-run/new-ctx-returns-ten-v0-keys` failed.

EVD-001's matrix is unamended for what it claims — every *syntactic* site
inlines to the slot read under either order, which is why the verdict **latent**
stands. But its `funcall` / `eval` rows describe a function cell whose occupant
was decided by load order, and PHASE-02's own first edit flipped it. The escape
hatch was never stable; only the rename made the symbol single-meaning.

This is also the sharper case *against* the design's dismissal of load order.
Design §10 says the original R1 "credited load order (both orders inline
identically)" — true of syntactic calls, and false of `funcall`. Both
explanations were incomplete rather than simply wrong. A line for reconcile
against ADR-018, alongside the byte-compilation correction already on record.

Pinned by `satan-run/prepare-is-the-accessor-not-a-constructor`, which asserts
the property *through* `funcall` — the path that reached the old defun. That
test would have gone red at T1 under the old naming.

### VA-3 deviates from its own letter, deliberately

VA-3 asks for "no `funcall`, `apply`, `#'` or `advice-add` reference to
`satan-run-prepare` … in the tree". Two remain, both in
`satan/test/satan-run-test.el`: a comment recording the historical trap, and the
regression test above. The criterion's *purpose* — no residual caller that could
still reach a defun and get a fresh run-id — is met, and met better with the
test present than absent. Reported rather than quietly satisfied.

### `plan.md`'s intra-phase recipe step (2) is loose

It says to "repoint `satan-run-tool-ctx`'s own call". There is no such call:
`satan-run.el:129` is the *struct accessor* read, as are `satan-broker.el`'s
three. All four were left spelled `satan-run-prepare`, which is what EX-3 is
about. The authored criteria never carried the error.

### A second "the broker stamps" — docstrings that encode their own location

EX-7 names one docstring that must not travel: `--iso-time-format`'s *"the
broker stamps"*. There is a second. `satan-broker--failed-suffix` reads
*"Helpers **in this file** strip the suffix"*, true of the broker and false of
the leaf until PHASE-03 moves the strippers. Adapted to "The layout helpers …"
in transit. Worth generalising at reconcile: the docstring-union obligation is
not only "keep the richer side" but "re-read the richer side from its new home".

### Left alone, on purpose

`satan-context.el:265`'s `(boundp 'satan-runs-dir)` guard is now redundant under
the hard require. No criterion asks for it and F2 set the precedent — don't
touch what has no defect behind it. A candidate for PHASE-03 or reconcile.

### Census for PHASE-03, taken at the PHASE-02 boundary

88 hits across 14 files. Three things the design's tables do not say:

- **`satan-broker-run-dir-for-id` is already zero.** PHASE-03's EX-1 lists nine
  names; PHASE-02 discharged that one. Eight are live. Do not read its zero as
  evidence the grep is working — use a *live* name as the control, as PHASE-02's
  VA-1 did (`satan-broker-locate-run-dir` = 27 at that point).
- **`satan-tank.el` is a full convert, and no criterion says so.** Everything it
  takes from the broker — `list-run-dirs` ×2, `locate-run-dir`,
  `--run-id-from-leaf` — is in PHASE-03's moved set, so its
  `(require 'satan-broker)` at `:25` can drop to `(require 'satan-run)` and the
  module stops paying for the broker's 20 requires. §5.4 lists tank as "call
  sites repointed" only, and EX-4 / EX-5 name the two cycles and the three
  soft-dependency reachers but not tank. It is the same pressure §2.3 measures,
  in a sixth module nobody counted. **A scope call for PHASE-03, not a silent
  extra** — take it to `/consult` rather than deciding it inside the phase.
- **Exactly one `boundp` guard on MCP state**, `satan-broker.el:628` — EX-3's
  target, confirmed singular. The other two `boundp`/`fboundp` hits in that file
  (`:67` `my/op-read-env`, `:81` `envrc--export`) are unrelated optional
  externals and must survive.

Reacher inventory, verified: `satan-observer.el` `:47` declare-function + `:59`
in-function require; `satan-budget.el:13` declare-function and
`satan-budget-test.el:12` `(require 'satan-broker)` held only for
`run-dirs-for-date`; `satan-tools-atsatan.el` `:35` comment, `:38`
declare-function, `:539` `fboundp` guard; `satan-intervention-mark.el` `:23`
comment + `:27` declare-function; `satan-attribute-listener.el:31`
declare-function. `cl-letf` stubs of `satan-broker-locate-run-dir` sit in
`satan-{attribute-listener,tools-atsatan,intervention-mark}-test.el`.

## 2026-07-24 — PHASE-03 complete

Six-function layout cluster and both DEC-8 flags moved to `satan-run.el`;
five soft-dependency reachers (`satan-budget`, `satan-observer`,
`satan-tools-atsatan`, `satan-intervention-mark`, `satan-attribute-listener`)
converted to a hard `(require 'satan-run)`; both require cycles
(`satan-budget`, `satan-observer`) dissolved. `satan-mcp.el`'s duplicate
`spawn-running` defvar deleted (F4) as the tail of the flag's move (F7),
per design §5.3's sequencing. `satan-broker.el`'s `(boundp
'satan-mcp--session-active)` guard deleted (D6) — the two unrelated
`fboundp` guards at `:67`/`:81` (`my/op-read-env`, `envrc--export`) survive
untouched.

**DEC-002** — settled via `/consult` during `/phase-plan`, before any code
changed: `satan-tank.el`'s `(require 'satan-broker)` also converts to
`(require 'satan-run)`. Its only three broker references were exactly the
moved functions, so leaving the require standing after the phase would have
been the identical coupling PHASE-03 exists to relieve in five siblings, for
a one-line cost already paid by the forced rename. Recorded as a knowledge
record (`.doctrine/knowledge/decision/002`), encoded in `plan.toml` as
PHASE-03 `EX-8`/`VA-6` (appended, not renumbered — ids are immutable).

All EX/VT/VA discharged: zero-hit grep over all nine moved names
individually (rg, live control `satan-run-locate-dir` = 19 — PHASE-02's
sampling lesson applied, not the already-zero `satan-broker-run-dir-for-id`);
`satan-run.el`'s require block read verbatim, still exactly `cl-lib` /
`subr-x` / `satan-custom` (I3 holds); MCP loaded standalone in a fresh batch
image with `satan-broker` absent (VA-4) — both flags bound; ADR-018 VT-2
recount still exactly one each (VA-5). Suite **1029 → 1030**, 0 unexpected,
13 skipped, same skip set. `just check` clean throughout.

Test-file mechanics, each a direct consequence of the rename rather than a
fresh scope call: `satan-run-test.el` gained four tests for the moved
cluster (including `dirs-for-date`'s first-ever direct unit test — it had
none in `satan-broker-test.el` either); `satan-broker-test.el` lost two
fully-duplicated tests and one retargeted test (coverage relocated, not
duplicated — `failure-streak-counts-trailing-failed` stays, since that
function was never in the moved set) and two now-vestigial requires
(`satan-mcp`, held only for the moved `session-active` flag — n/a, that one
was in `satan-budget-test.el`; corrected: `satan-broker-test.el` dropped
`(require 'satan-mcp)`, `satan-budget-test.el` dropped `(require
'satan-broker)`).

Left alone, on purpose: `satan-observer-test.el:28-31`'s stale
comment/defvar about `satan-runs-dir` predates this phase (PHASE-02 already
moved that defcustom) and names no symbol in PHASE-03's moved set — not this
phase's debt to clean up.

All three of SL-013's phases are now complete. Next: `doctrine slice status
SL-013 audit`, then `/audit`.

## 2026-07-24 — audit (RV-003)

Eleven findings, no blockers, no majors against the implementation. The one
`major` is against **governance**: ADR-018's Context still asserts the falsified
byte-compilation mechanism. Full reasoning in RV-003's `## Synthesis`; the
handoff is its `## Reconciliation Brief`.

### Harvested from the phase sheets (not previously in this file)

- **Lint scale, PHASE-03:** 65/65 files `ok:true`; `bin/elisp-locate-paren-error`
  clean on all 9 touched test files. Worth recording because `just check`'s
  summary line reports tests, not lint breadth.
- **PHASE-03 also removed `satan-attribute-listener-test.el`'s
  `declare-function`** — redundant *and* wrongly annotated after the move. The
  notes' PHASE-03 entry lists the two dropped `require`s but not this third
  deletion.
- **The sheet's STOP conditions earned their keep.** PHASE-03 authored two ("a
  sixth soft-dependency site → `/consult`"; "a fourth entry in `satan-run.el`'s
  require block → `/consult`, do not patch around it"). The first fired and
  produced DEC-002 rather than a silent scope extension. That is the pattern to
  repeat: name the STOP condition in the sheet *before* the phase can trip it.

### What the audit re-ran rather than believed

Every gate independently, from a clean shell. All 15 deleted/renamed names
zero-hit with live controls; ADR-018 VT-2 clauses 1–2 confirmed; **clause 3
widened past the slice's own gate** — checked against all three `cl-defstruct`s
in `satan/*.el` (`satan-run`, `satan-audit-handle`, `satan-mcp-session`), no
accessor/`defun` collision anywhere, which is what makes design F2's "leave
`satan-run-perceive` alone" correct rather than merely convenient. I3 read
verbatim. R5's docstring union diffed pairwise against `1be1f3e`. `just check`
exit 0, 1030/0/13.

### The trap recurred, in a new costume

This audit's first grep sweep piped per-symbol counts through `bc`, which is
absent from this environment; the `|| echo 0` fallback printed **fifteen
spurious zeros** — a perfect pass for a search that never ran. Same failure
class as PHASE-02's `ugrep` incident, different tool. The live-positive-control
mitigation already recorded in
[[mem.pattern.satan.rg-not-ugrep-for-rename-verification]] catches both; the
memory has been generalised from "`ugrep` is the problem" to "any silent
zero-producing link in the pipeline is".

### Repairs taken in-audit (fix-now)

Three, all code-only, zero behaviour change, all residue of the collapsed
duplication. Suite re-run green after.

- **F-4** `satan-context.el:261` — deleted the dead `(boundp 'satan-runs-dir)`
  arm. Under the hard require F3 landed it could never be false. This is the
  sixth module carrying the idiom EX-5 retires; EX-5 enumerated five.
- **F-5** `satan-observer-test.el:28-31` — deleted the stale comment and
  cycle-breaker `(defvar satan-runs-dir)`. PHASE-03 correctly declined it (not in
  its moved set); audit is where it belongs.
- **F-6** `satan-run.el:3-7` — the header still described the pre-collapse module
  ("required by satan-broker and satan-mcp", "extracted from satan-broker.el").
  Rewritten to state DEC-001 ownership and to pin I3 as an invariant to preserve,
  naming C1 as the reason.

### Carried forward

- **[[IMP-018]]** — a **twelfth** instance of the duplication class, found during
  audit: `satan-context--bucket-regexp` / `--list-recent-runs` are a renamed fork
  of `satan-run--bucket-name-p` / `satan-run-list-dirs`, in a module this slice
  gave a hard require. §2.1's symbol-keyed census never reached it, exactly as
  RV-002 F-2 predicted. Not a mechanical repoint (ordering, N-clipping, a
  capture-group regexp), so it needs a design call — hence backlog, not fix-now.
  This is the concrete cost argument [[IMP-017]] previously lacked.
- **[[CHR-002]]** — `doctrine check gate` exits non-zero in this repo: no
  `[verification]` in `doctrine.toml`, no `just gate` recipe. No verification was
  skipped (every phase ran `just check`), but a mandated audit step is broken for
  every future slice here.

### Historical numbering

Design §10's adversarial pass and the RV-002 record were written against a
five-phase table. The lint cut collapsed it to three (P2→P1, P3→P2, P4→P3),
free because no `plan.toml` existed yet. §10 carries a note; AR-4 and AR-6 are
marked MOOT with their transferable content retained.
