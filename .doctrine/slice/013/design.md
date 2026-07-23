# Design SL-013: Collapse the satan-run / satan-broker run-context duplication

<!-- Reference forms (.doctrine/glossary.md § reference forms): entity ids padded
     (SL-020, REQ-059, ADR-004); doc-local refs bare — OQ-1 (§6), D1 (§7),
     R1 (§10), Q1. -->

## 1. Design Problem

`satan-run.el` and `satan-broker.el` each declare their own `cl-defstruct
satan-run`, their own `satan-runs-dir` and `satan-hippocampus-dir` defcustoms,
and their own forked `mint-id` / `prepare` / `dir-for-id` / `tool-ctx`. ADR-018
D4.1 sequences collapsing this as **step 1** of the extraction programme;
POL-001 records it as a *precondition, not an extraction* — the in-language
rehearsal of single-owner discipline before any authority item migrates.

The design must settle three things the scope deliberately left open: whether
the `satan-run-prepare` accessor/defun collision is live (R1), which module owns
the collapsed seam (Q1), and what standing lint makes the collision
un-reintroducible (ADR-018 VT-2).

## 2. Current State

### 2.1 The duplication, measured

A tree-wide sexp scan of `satan/*.el` for duplicate top-level definitions
returns **six** hits, and only four are real:

| Symbol | Kind | Files | Real? |
|---|---|---|---|
| `satan-run` | `cl-defstruct` | `satan-run.el:27`, `satan-broker.el:80` | yes |
| `satan-runs-dir` | `defcustom` | `satan-run.el:15`, `satan-broker.el:44` | yes |
| `satan-hippocampus-dir` | `defcustom` | `satan-run.el:20`, `satan-broker.el:49`, **`satan-tools-hippocampus.el:22`** | yes (**F1**) |
| `satan-broker--spawn-running` | `defvar` *with value* | `satan-broker.el:42`, `satan-mcp.el:26` | yes (**F4**) |
| `satan-runs-dir` | `defvar` valueless | `satan-observer.el:49`, `satan-context.el:21` | no — forward declarations |
| `satan-memory-store--current-run-id` | `defvar` valueless | `satan-mcp.el:23`, `satan-broker.el:37` | no — forward declarations |

The forked **function and constant** bodies pair `satan-run.el`
`:38/47/52/55/66/77/98` against `satan-broker.el` `:119/126/153/159/191/129/270`
— seven each, of which two (`--iso-time-format`, `--failed-suffix`) are
`defconst`s, not functions.

They are absent from the table above because **every fork wears a different
name**. That is the shape of this tree's duplication: four same-name collisions
and seven same-body/different-prefix forks, eleven in all. A symbol-keyed scan
sees the first four and none of the last seven — a bound that constrains what
VT-2 can prove (**D3**, §9).

### 2.2 The clones are structurally identical

A canonicalising sexp comparison (docstrings elided, prefixes normalised) shows
**all seven cloned bodies and both 18-slot struct definitions are identical**.
The only differences are docstrings — and they do **not** run consistently in
the broker's favour, which R3 and R5 must not assume:

| Item | Richer side |
|---|---|
| `--prepare`, `--failed-suffix`, `--date-bucket-for-run-id`, `run-dir-for-id`, `--tool-ctx` | **broker** — `satan-broker--tool-ctx` carries the `:audit` / `satan-intervention-create` contract that `satan-run-tool-ctx` omits |
| `--mint-run-id` | **`satan-run.el`** — `satan-broker--mint-run-id:119` has **no docstring at all** |
| `--iso-time-format` | neither — one sentence each, but the broker's reads *"the broker stamps"*, which is false of a leaf |
| `cl-defstruct satan-run` | mixed — `satan-run.el:27` holds the struct docstring, `satan-broker.el:80` holds a four-line comment on the `prepare` slot and no docstring |
| `satan-runs-dir`, `satan-hippocampus-dir` | neither — **byte-identical**, docstrings included |

Consequence: the broker side of the collapse is **pure deletion with no
behaviour change**, and R2's "refactor without a net" risk is much smaller than
scoped. The corollary obligation is that deletion must **preserve the union of
the docstrings in both directions** — each pair diffed on its own merits. A
mechanical "keep the broker's" would delete the only docstring
`satan-run-mint-id` has.

### 2.3 The seam is under real pressure

`satan-broker.el` `require`s `satan-budget` (`:18`) and `satan-observer`
(`:29`), so neither module can `require` the broker back. Both reach broker
functions through cycle-breakers:

- `satan-budget.el:13` — `declare-function satan-broker-run-dirs-for-date`
- `satan-observer.el:47` — `declare-function satan-broker-locate-run-dir`,
  plus an in-function `(require 'satan-broker)` at `:59`
- `satan-tools-atsatan.el:35-38` — "Broker is soft", `declare-function` + an
  `fboundp` guard at `:539`
- `satan-intervention-mark.el:23-27` — "Broker dependency is soft"
- `satan-attribute-listener.el:31` — `declare-function`

Five modules want run-directory resolution without the broker's 20 requires.
**That is the same pressure that produced the `satan-run` clone**, still
unrelieved, paid for in guards instead of a leaf.

### 2.4 Baseline

`just db-setup` then `just test`: **1018 tests, 1005 as expected, 0 unexpected,
13 skipped**. Every skip is a corpus-integration or DB `skip-unless`. `satan-run.el`
has no test file (R2).

## 3. Forces & Constraints

- **C1 — `satan-mcp.el` needs run identity WITHOUT context/percept.** This
  constraint produced the clone. A collapse that reinstates the coupling has
  not solved the problem. It binds the ownership decision absolutely.
- **C2 — no behavioural change to run identity** (slice non-goal). Run-id
  format, date bucketing, the `.FAILED` suffix, and the frozen
  `:time_now` / `:run_id` / `:start_time` contract all survive.
- **C3 — no extraction, no authority migration** (ADR-018 D4.1, POL-001). The
  ADR-017 §3 ledger is D4.2's artifact and does not exist yet.
- **C4 — `just check` clean at every phase boundary** (slice closure intent).
  This constrains where the new lint may be wired in.
- **C5 — tests run interpreted** (`emacs --batch`, never byte-compiled).
- **C6 — the broker's spawn/filter/sentinel/finalize body (~980 lines) is out of
  scope** (ADR-018 D4.4) except where a call site follows the collapsed owner.

## 4. Guiding Principles

- **One owner, named.** The point of the rehearsal is that each item has exactly
  one definition site, and that this is *mechanically checkable* — not merely
  true today.
- **The generic form is the point.** The lint must forbid the *class* of
  collision, in any pair, not this pair by name.
- **Relieve the pressure, don't route around it.** Cycle-breaker scaffolding is
  a symptom; the fix is a leaf that everyone may depend on.
- **Deletion over migration.** Where the clones are identical, prefer removing
  code to moving it.

## 5. Proposed Design

### 5.1 System Model

`satan-run.el` becomes the **sole owner** of run identity, run-directory layout,
and run-lifecycle state (**DEC-001**), remaining a leaf on `cl-lib` / `subr-x` /
`satan-custom` — which is what preserves **C1**.

```
                       satan-custom.el
                             ▲
                       satan-run.el ...................... the leaf
                       ┌──────────────────────────────┐
                       │ identity                     │
                       │   satan-runs-dir             │
                       │   satan-hippocampus-dir      │
                       │   cl-defstruct satan-run     │
                       │   satan-run-mint-id          │
                       │   satan-run--iso-time-format │
                       │   satan-run-new-ctx   (was the colliding defun)
                       │   satan-run-tool-ctx         │
                       │ layout — already here        │
                       │   satan-run--failed-suffix   │
                       │   satan-run--date-bucket     │
                       │   satan-run-dir-for-id       │
                       │ layout — moved from satan-broker.el
                       │   satan-run--bucket-name-p   │
                       │   satan-run--legacy-run-name-p
                       │   satan-run--id-from-leaf    │
                       │   satan-run-locate-dir       │
                       │   satan-run-list-dirs        │
                       │   satan-run-dirs-for-date    │
                       │ lifecycle state  (DEC-8, both flags)
                       │   satan-run--spawn-running   │
                       │   satan-run--session-active  │
                       └──────────────────────────────┘
                             ▲
      ┌──────────┬───────────┼───────────┬──────────────┬─────────────┐
 satan-broker  satan-mcp  satan-context  satan-budget  satan-observer  …
  (−190 lines) (C1 intact)   (F3 fixed)   (cycle gone)  (cycle gone)
```

Nothing can cycle through a leaf, so every dependant may hard-`require` it. Both
existing require cycles dissolve as a consequence, not as a separate effort.

### 5.2 Interfaces & Contracts

Renames (the `run` in the prefix makes the old infix redundant):

| Was | Becomes |
|---|---|
| `satan-run-prepare` *(defun)* | `satan-run-new-ctx` (ADR-018 D4.1 names this) |
| `satan-broker-locate-run-dir` | `satan-run-locate-dir` |
| `satan-broker-list-run-dirs` | `satan-run-list-dirs` |
| `satan-broker-run-dirs-for-date` | `satan-run-dirs-for-date` |
| `satan-broker-run-dir-for-id` | `satan-run-dir-for-id` *(already exists; broker's is deleted)* |
| `satan-broker--run-id-from-leaf` | `satan-run--id-from-leaf` |
| `satan-broker--bucket-name-p` | `satan-run--bucket-name-p` |
| `satan-broker--legacy-run-name-p` | `satan-run--legacy-run-name-p` |
| `satan-broker--spawn-running` | `satan-run--spawn-running` |
| `satan-mcp--session-active` | `satan-run--session-active` *(D6, P4)* |

Deletions — the fork is removed and every call site repoints to the
`satan-run.el` body it was cloned from. This is the set §2.1 counts and the set
**P3**'s exit criterion greps:

| Deleted | Survivor |
|---|---|
| `satan-broker--mint-run-id` | `satan-run-mint-id` |
| `satan-broker--iso-time-format` | `satan-run--iso-time-format` |
| `satan-broker--prepare` | `satan-run-new-ctx` |
| `satan-broker--failed-suffix` | `satan-run--failed-suffix` |
| `satan-broker--date-bucket-for-run-id` | `satan-run--date-bucket` |
| `satan-broker--tool-ctx` | `satan-run-tool-ctx` |
| `satan-broker.el`'s `cl-defstruct satan-run`, `satan-runs-dir`, `satan-hippocampus-dir` | the `satan-run.el` declarations |
| `satan-tools-hippocampus.el:22`'s `satan-hippocampus-dir` (**F1**) | ditto, with D7's union docstring |
| `satan-context.el:21-24`'s three forward declarations (**F3**) | `(require 'satan-run)` |
| `satan-mcp.el:26`'s `satan-broker--spawn-running` (**F4**) | `satan-run--spawn-running` *(P4 — see §5.3)* |

`satan-run-prepare` **must not exist as a defun afterwards**; the struct accessor
of the same name (slot `prepare`) survives and is the only meaning of the symbol.

Signatures are unchanged from the surviving implementations:

```elisp
(satan-run-new-ctx  MODE)                      ; → 10-key run_ctx plist
(satan-run-mint-id  MODE-NAME &optional TIME)  ; → "20260531T221530-interactive-a3f01c"
(satan-run-dir-for-id RUN-ID &optional RUNS-DIR)
(satan-run-locate-dir RUN-ID &optional RUNS-DIR)   ; probes 4 layout candidates
(satan-run-list-dirs  RUNS-DIR)
(satan-run-dirs-for-date RUNS-DIR DATE-PREFIX)
(satan-run-tool-ctx   RUN-CTX)                 ; → tool-ctx plist
```

### 5.3 Data, State & Ownership

The `satan-run` struct keeps all 18 slots in their existing order (`id mode
start-time dir bundle-path process pending-tool-calls tool-calls-done
applied-actions staged-actions rejected-actions failed-actions final status
timeout-timer audit stdout-log-path prepare`). **C2** forbids touching it.

**The layout cluster owns filesystem reads, not merely path arithmetic.**
`satan-run-locate-dir` stats four candidate paths with `file-directory-p`;
`satan-run-list-dirs` enumerates via `directory-files` and stats each entry;
`satan-run-dirs-for-date` filters that enumeration. Moving them makes the leaf a
module that touches the disk, and the design records that rather than eliding
it. It costs no new `require` — every primitive involved (`directory-files`,
`file-directory-p`, `expand-file-name`, `string-match-p`, `cl-find-if`,
`cl-remove-if-not`) is C-core or `cl-lib` — so **I3 holds as a dependency
invariant, not as a purity claim** (**R7**).

**F5 — one constructor for run_ctx.** `satan-mcp--mint-session`
(`satan-mcp.el:169-187`) currently mints a run-id, formats a timestamp, and
hand-rolls a **4-key** prepare plist, where `satan-run-new-ctx` produces the
canonical **10-key** shape (the six v0 placeholders exist so later phases may
`plist-put` without ordering surprises). MCP switches to:

```elisp
(let* ((prepare   (satan-run-new-ctx mode))
       (run-id    (plist-get prepare :run_id))
       (time-now  (plist-get prepare :time_now))
       (start-time (plist-get prepare :start_time))
       (run-dir   (satan-run-dir-for-id run-id)))
  …)
```

This is safe: `satan-audit-open` (`satan-audit.el:49`) *stores* run-ctx on the
handle and serialises only `manifest` and `bundle`, so the six added nil keys
reach no on-disk artifact. It deletes MCP's separate `mint-id` and
`format-time-string` calls, making `satan-run-new-ctx` the single constructor in
fact and not just in name.

**F4 / F7 — both DEC-8 flags move to the leaf.** Mutual exclusion is a two-flag
protocol, and today each module reaches into the other:

- `satan-broker--spawn-running` is written by the broker (`:769`, `:564`, `:976`)
  and read by MCP (`:165`, `:439`) — which duplicates the `defvar` (**F4**).
- `satan-mcp--session-active` is written by MCP and read by the broker at
  `:739-740`, behind a `(boundp …)` guard (**F7**).

MCP cannot require the broker without destroying **C1**, and a valueless forward
declaration would leave the variable *unbound* — making `satan-mcp.el:165` a
void-variable crash whenever MCP loads without the broker (which
`satan-mcp-test.el` does). Both flags therefore move to the leaf both modules
already require, as `satan-run--spawn-running` and `satan-run--session-active`,
and the `boundp` guard is deleted (**D6**).

**Both flags move in P4, together.** F4's fix is not "delete MCP's duplicate
`defvar`" on its own: MCP cannot `require` the broker (**C1**), so deleting
`satan-mcp.el:26` while the flag still lives in `satan-broker.el` leaves
`satan-mcp.el:165` reading an unbound variable in every image that loads MCP
without the broker — precisely the void-variable crash this paragraph rules out.
The deletion is only safe as the tail of the move to the leaf. F4 and F7 are
therefore one operation, sequenced with the layout cluster in P4, not split
across P3 and P4.

### 5.4 Lifecycle, Operations & Dynamics

Code impact, by path (these become the `design-target` selectors):

| Path | Change |
|---|---|
| `satan/satan-run.el` | Gains the layout cluster + spawn flag; `satan-run-prepare` defun → `satan-run-new-ctx`; absorbs the broker's richer docstrings. ~117 → ~240 lines |
| `satan/satan-broker.el` | `(require 'satan-run)`; deletes struct, 2 defcustoms and 13 cloned/moved definitions; deletes the `boundp` guard at `:739-740` (**D6**); ~47 reference sites repointed. **−~190 lines** |
| `satan/satan-mcp.el` | Drops the duplicate `spawn-running` defvar; `satan-mcp--session-active` → `satan-run--session-active` (**D6**); **F5** switch to `satan-run-new-ctx`; corrects the wrong `:22-23` comment (**F6**) |
| `satan/satan-context.el` | **F3**: `(require 'satan-run)`; deletes the `:21-24` forward declarations. `satan-run-perceive` / `-enrich` / `-assemble-context` keep their names (**F2**, no defect) |
| `satan/satan-tools-hippocampus.el` | **F1**: deletes the third `satan-hippocampus-dir`; requires the leaf |
| `satan/satan-budget.el` | `declare-function` → `(require 'satan-run)`; **cycle dissolved** |
| `satan/satan-observer.el` | `declare-function` + valueless defvar + in-function require → one top-level `(require 'satan-run)`; **cycle dissolved** |
| `satan/satan-tools-atsatan.el` | Soft-dependency comment, `declare-function` and `fboundp` guard deleted |
| `satan/satan-intervention-mark.el` | Soft-dependency comment + `declare-function` deleted |
| `satan/satan-attribute-listener.el` | `declare-function` → require |
| `satan/satan-tank.el` | Call sites repointed |
| `satan/test/satan-run-test.el` | **New.** Receives the retargeted coverage |
| `satan/test/satan-broker-test.el` | ~20 sites updated; broker-specific tests stay |
| `satan/test/satan-mcp-test.el` | `spawn-running` references updated |
| `tools/elisp-duplicate-definitions.el` | **New.** The lint |
| `tools/test/elisp-duplicate-definitions-test.el` | **New.** Fixture-driven tests |
| `bin/elisp-duplicate-definitions` | **New.** Wrapper, matching `bin/elisp-locate-paren-error` |
| `dev/satan-test.el` | `satan-test-suite-dirs` → `("satan/test" "tools/test")` |
| `justfile` | `lint` gains the whole-tree check; `test` gains `-L ./tools` |

**Phase order** (green at every boundary, satisfying **C4**):

| Phase | Objective | Exit |
|---|---|---|
| **P1** | The lint, TDD against fixtures, **not yet pointed at `satan/*.el`**. Includes the harness wiring it depends on: `satan-test-suite-dirs` → `("satan/test" "tools/test")` and `-L ./tools` in `just test` (**AR-4**) | Planted-duplicate fixture fails; clean fixture passes; `just check` clean |
| **P2** | `satan/test/satan-run-test.el` characterisation of the surviving surface | Named surface covered before P3 may move it: `satan-run-mint-id`'s format, `satan-run-dir-for-id`'s bucketed and legacy resolution, `satan-run-new-ctx`'s ten v0 keys, `satan-run-tool-ctx`'s **frozen** `:time_now`, and both defcustom defaults. Suite green, count risen by the new file's assertions |
| **P3** | The collapse: rename `satan-run-prepare` → `satan-run-new-ctx`; delete the broker's struct, both defcustoms and the six cloned bodies; F1 / F3 / F5 / F6 | (a) zero-hit grep over `satan-broker--(mint-run-id\|iso-time-format\|prepare\|tool-ctx\|failed-suffix\|date-bucket-for-run-id)` **and** `satan-broker-run-dir-for-id` — the §5.2 deletion table entire; (b) exactly one `cl-defstruct satan-run`, one `defcustom satan-runs-dir`, one `defcustom satan-hippocampus-dir` in `satan/*.el`; (c) no `defun satan-run-prepare` anywhere, and `satan-mcp--mint-session` contains no `format-time-string` (**F5**); (d) `satan-context.el` forward-declares no `satan-run-*` symbol and requires `satan-run` (**F3**); (e) suite green at baseline |
| **P4** | Move the layout cluster **and both DEC-8 flags** (**F4** / **F7** / **D6**, §5.3); dissolve both cycles; delete the guards | Zero-hit grep over the **full** moved set (**AR-3**): `satan-broker-(locate-run-dir\|list-run-dirs\|run-dirs-for-date\|run-dir-for-id)`, `satan-broker--(failed-suffix\|date-bucket-for-run-id\|bucket-name-p\|legacy-run-name-p\|run-id-from-leaf\|spawn-running)` **and** `satan-mcp--session-active` (**D6**); no `boundp` guard on MCP state in `satan-broker.el`; `satan-budget.el` and `satan-observer.el` contain no `satan-broker` reference; suite green |
| **P5** | Wire the lint into `just lint`; verify VT-2 against the real tree | `just check` clean; the lint fails when a duplicate is deliberately re-introduced and passes when it is removed (**R4**) |

The lint is written red-then-green against **fixtures** in P1, so `just check`
never goes red while the tree still holds its duplicates. The rename does not
lead, because R1 (§10) found the collision latent.

**Every phase exits on a zero-hit grep over its own deleted set, not a sample of
it.** AR-3 established that standard for P4; RV-002 **F-1** found it had not been
carried to P2 or P3 — P3's original exit ("suite green; no `cl-defstruct
satan-run` outside `satan-run.el`") was satisfiable with nine of its ten
deletions still standing, and P2's was the bare word "Green". A green suite
cannot detect a surviving clone, because §2.2 proves the clones are identical
and the lint is deliberately unwired until P5 (**C4**); the two phases that
perform the actual collapse are guarded by nothing but these criteria. They are
what `plan.toml`'s `EX-` ids will carry, and those ids are immutable once
authored.

### 5.5 Invariants, Assumptions & Edge Cases

- **I1** Exactly one `cl-defstruct satan-run`, one `satan-runs-dir`, one
  `satan-hippocampus-dir` in the tree. Enforced by the lint, not by vigilance.
- **I2** No symbol is both a `cl-defstruct`-generated accessor and a
  function-ish definition.
- **I3** `satan-run.el` acquires no dependency beyond `cl-lib` / `subr-x` /
  `satan-custom`. This is **C1** made structural; if it ever fails, the clone
  comes back. It survives the layout move not because the moved code is pure —
  it enumerates and stats directories (§5.3) — but because every primitive it
  uses is C-core or `cl-lib`. Verified by reading the require block, never
  inferred from the code's character.
- **I4** A valueless `(defvar x)` is a *declaration*, never a definition. The
  lint must encode this or it will flag legitimate cycle-breakers.
- **I5** Run-id format, date bucketing, `.FAILED` handling, and the frozen
  `:time_now` / `:run_id` / `:start_time` contract are byte-identical before and
  after (**C2**).

Edge cases the lint must handle: `cl-defstruct` with an options list
(`(cl-defstruct (name (:conc-name …)) …)`), a docstring after the name, and slot
specs given as `(slot default …)` rather than bare symbols. The current tree uses
only the plain form, so these are unexercised by construction — fixtures must
cover them or the lint is only accidentally correct.

## 6. Open Questions & Unknowns

- **OQ-1** Should `satan-run--spawn-running` be public rather than
  private-by-convention? Kept private: `satan-run--iso-time-format` is already
  read cross-module by `satan-mcp.el:170` and `satan-context.el:666`, so the
  convention in this leaf is established. Revisit only if a third reader appears.
- **OQ-2** `:include` inheritance in the lint's accessor derivation — implement,
  or document the limitation explicitly. Unused in this tree today; the answer
  should not be silence.
- **OQ-3** ADR-018 D4.2 will want the same single-owner check over the policy /
  registry tables once they move. Whether this lint generalises to that, or is
  superseded by a Rust-side check, is out of scope here but worth not
  foreclosing. Carried as [[IMP-017]], which also records why the lint this
  slice ships would not cover a duplicated *table* (**D3**).
- **OQ-4 — CLOSED (D6).** `satan-mcp--session-active` moves to the leaf too.
- **OQ-5 — CLOSED (D7).** One concept; collapse with a union docstring.

## 7. Decisions, Rationale & Alternatives

**D1 — `satan-run.el` owns the seam.** *(Answers Q1; recorded as DEC-001.)*
Alternatives: broker ownership, rejected because it reinstates the
context/percept coupling on `satan-mcp.el` that produced the clone (**C1**);
minimal cut leaving the layout cluster in the broker, rejected because it leaves
both require cycles standing.

**D2 — the run-directory layout cluster moves too.** Not duplicated, so strictly
outside the scoped four items — but it is the payload the five soft-dependants
actually want, and moving it dissolves two genuine require cycles. Marginal cost
measured at **27 reference sites across 11 files**, all mechanical single-symbol
renames caught by the compiler, of which ~8 are `declare-function` lines and
comments that get *deleted*. Alternative rejected:
`define-obsolete-function-alias` shims — two names for one thing indefinitely,
and the guards would survive because the aliases still live in the broker, so
the pressure would not actually be relieved.

**D3 — the lint is a general duplicate-definition check, not a targeted one.**
The slice asks for the generic form. Measured: after this slice the tree has
**zero** violations under the general rule, so generality costs nothing. The
narrow reading of VT-2 (struct + defcustom + accessor collision only) would not
have caught **F4** — the same single-owner defect in the same two modules — so it
would certify a tree still violating the principle the lint exists to enforce.

*Its reach is nonetheless bounded, and the bound is on the record (**RV-002
F-2**).* The check is keyed on the **symbol**, so it sees the four same-name
duplications of §2.1 and **none of the seven same-body/different-prefix forks**
in the same tree — the larger half of this slice's own subject matter. The
argument above against the narrow reading applies with equal force to this
result: single-definition is not single-implementation. The check that would
close the gap is structural — a canonical-body hash across the tree, mechanising
the comparison §2.2 ran by hand — and it is **deferred to [[IMP-017]] rather
than smuggled into this slice**, because ADR-018 D4.2 migrates a *data* table whose
duplication will look exactly like these seven forks, and must not inherit a
false account of what VT-2 proved.

**D4 — the lint parses source; it does not load the package.** Forced, not
chosen: after loading, the second definition has already overwritten the first
and the duplication is *invisible* to introspection. This also keeps the lint
free of the package's DB and filesystem side effects, matching
`bin/elisp-locate-paren-error`'s "parses the file as text, it does not load it".

**D6 — both DEC-8 flags move to the leaf.** *(Closes OQ-4 / F7 / AR-1.)*
`satan-mcp--session-active` becomes `satan-run--session-active` beside
`satan-run--spawn-running`, and the `(boundp 'satan-mcp--session-active)` guard at
`satan-broker.el:739-740` is deleted. Not forced by the lint — `session-active`
is defined only once — but DEC-8 is a single protocol with two flags, and
relocating one while the other stays behind a `boundp` guard would retire half a
soft-coupling and call the single-owner rehearsal complete. Cost: one defvar, one
deleted guard, a few test references.

**D7 — the two `satan-hippocampus-dir` declarations are one concept.**
*(Closes OQ-5 / AR-2.)* The jail's read-write scratch directory **is** where
SATAN's self-curated memory lives: `satan-run-tool-ctx` hands this exact variable
to handlers as `:hippocampus-dir`, and `satan-tools-hippocampus.el` is the
handler that writes there. They collapse to one declaration whose docstring
states **both** roles — otherwise the next reader sees a docstring describing
only one of them and "fixes" the omission by re-splitting the defcustom.

**D5 — F1, F3, F4, F5 are absorbed; F2 is not.** The absorbed four are each
either a defect the collapse's own objective covers, or one the new lint would
flag — leaving them would force the lint to be weakened. **F2**
(`satan-context.el` owning `satan-run-perceive` / `-enrich` /
`-assemble-context`) has no defect behind it: those three genuinely belong to the
run-ctx pipeline, none collides with a struct accessor, and renaming would be
cosmetic churn across a module the slice's non-goals never contemplated.

## 8. Risks & Mitigations

| | Risk | Mitigation |
|---|---|---|
| **R1** | *Answered — see §10.* The collision is latent | Rename still lands (P3); the lint (I2) makes recurrence detectable |
| **R2** | `satan-run.el` untested; collapse is a refactor without a net | Downgraded by §2.2: the clones are **provably identical**, so the broker's existing coverage *is* the characterisation suite. P2 retargets it into `satan-run-test.el` before P3 moves anything |
| **R3** | Defcustom collapse is user-visible | **Closed on evidence.** All three declarations carry identical default expressions, and `defcustom` sets a default only when unbound — so collapsing changes no value. A keeper's `custom-set-variables` binds the shared symbol either way. The broker's two copies are **byte-identical to the leaf's, docstrings included** (§2.2), so their deletion changes nothing whatever; the only docstring decision genuinely in play is `satan-tools-hippocampus.el`'s third declaration, which **D7**'s union docstring settles |
| **R4** | The lint is written to fit a tree already known to pass, proving nothing | P1 builds it against fixtures *before* the tree is clean; P5 verifies by deliberately re-introducing a duplicate |
| **R5** | Docstring loss — the deleted copy is sometimes the better one | Explicit obligation in §2.2, **in both directions**. The broker's copy is richer for five of seven bodies, but `satan-broker--mint-run-id` has none at all, so a mechanical "keep the broker's" would delete the only docstring `satan-run-mint-id` has. The reviewer diffs each pair, not symbol lists |
| **R6** | The 27-site rename silently misses a site | Every miss is a void-function/void-variable at load or test time under **C5**; exit criterion for P4 is a zero-hit grep |
| **R7** | Moving the layout cluster grows the leaf and could pull in a dependency, breaking **I3**/**C1** | No new `require`. The moved functions are **not** pure path arithmetic — they stat and enumerate directories (§5.3) — but every primitive they use is C-core or `cl-lib`. Asserted as I3 and checked by inspecting `satan-run.el`'s require block, not by asserting the code's character |

**A1 — falsified.** The slice assumed no third module declared these; the tree
scan found `satan-tools-hippocampus.el:22` (**F1**). The assumption is replaced
by the lint, which makes the property standing rather than grep-verified.

## 9. Quality Engineering & Validation

**ADR-018 VT-2** — the lint, as a standing check in `just lint`:

- `VT` passes over `satan/*.el` after P4.
- `VT` fails on a fixture with a second `cl-defstruct` of the same name.
- `VT` fails on a fixture with a second `defcustom` of the same name.
- `VT` fails on a fixture with a second **valued** `defvar` of the same name
  (the **F4** class).
- `VT` **passes** on a fixture combining a valueless `(defvar x)` declaration
  with a single real definition elsewhere (the **I4** false-positive guard).
- `VT` fails on a fixture where a `defun` shadows a generated struct accessor
  (the **I2** / R1 class), including under an explicit `:conc-name`.

**What VT-2 does not establish (RV-002 F-2).** The lint proves
*single-definition*, not *single-implementation*. Being keyed on the symbol it
cannot see a clone that has been renamed — the form seven of this tree's eleven
duplications actually took (§2.1). After P5 the tree is clean and the check is
honest about its own reach; it does not license the claim that this class of
duplication has been made un-reintroducible in general, and no `VT` above is
worded to imply otherwise. The structural form of the check is backlogged as
[[IMP-017]], related to ADR-018 D4.2 (**D3**).

**Collapse:**

- `VT` `satan-run-prepare` is not `fboundp` as a defun; `satan-run-new-ctx` is.
  Given EVD-001, this is asserted via `(documentation 'satan-run-prepare)` /
  `funcall`, **not** a syntactic call — a syntactic call would inline the
  accessor and pass either way, which is precisely the trap that hid R1.
- `VT` `satan-run-tool-ctx` returns the run's **frozen** `:time_now`, not a fresh
  one — the observable the collision would have corrupted.
- `VT` `satan-run-new-ctx` returns all ten v0 keys, and MCP's session prepare
  plist now matches that shape (**F5**).
- `VT` run-id format, date bucketing and `.FAILED` resolution unchanged
  (retargeted from `satan-broker-test.el:146-156`, `:177`, `:286-300`).
- `VT` DEC-8 mutual exclusion still holds from both directions (**D6**): MCP
  refuses a session while `satan-run--spawn-running` is t, and the broker refuses
  a scheduled run while `satan-run--session-active` is t — retargeted from
  `satan-mcp-test.el:462-489` and `satan-broker-test.el:1039-1116`.
- `VT` the surviving `satan-hippocampus-dir` docstring names **both** roles —
  jail scratch and hippocampus corpus (**D7**). Verified by review, not by test.
- `VA` every surviving definition carries the **better** of the two docstrings,
  diffed pairwise (§2.2) rather than by a blanket rule. In particular
  `satan-run-mint-id` still has one, the leaf's `satan-run--iso-time-format`
  docstring is not replaced by the broker's broker-specific wording, and the
  struct keeps both its own docstring and the broker's `prepare`-slot comment
  (**R5**).
- `VA` `satan-budget.el` and `satan-observer.el` contain no reference to
  `satan-broker`; `satan-broker.el` contains no `boundp` guard on MCP state.
- `VA` `satan-run.el`'s require block is exactly `cl-lib`, `subr-x`,
  `satan-custom` (**I3**).

**Regression gate:** full suite green against the recorded baseline of **1018
tests / 0 unexpected / 13 skipped**, with **no new skips** — the skip count is
part of the gate because every skip here is a `skip-unless` that a fresh
checkout would silently satisfy by omission.

## 10. Review Notes

### R1 — settled with evidence: latent, and every recorded reason is wrong

Recorded in full as **EVD-001**. `satan-run.el:27`'s struct generates the
accessor `satan-run-prepare`; `:77`'s defun overwrites its **function cell** —
confirmed, `(documentation 'satan-run-prepare)` returns the defun's docstring
after load. But `cl-defstruct` accessors are `cl-defsubst`s, which also install
an inliner on the symbol's **`compiler-macro` property**, and `defun` does not
remove it. Emacs applies compiler-macros during macroexpansion, which happens as
each top-level form loads — so every *syntactic* call site inlines to the slot
read.

| Call form | Resolves to |
|---|---|
| `(satan-run-prepare s)` — syntactic, interpreted | accessor |
| interpreted `(lambda (x) (satan-run-prepare x))` | accessor |
| `(byte-compile (lambda (x) (satan-run-prepare x)))` | accessor |
| `(funcall 'satan-run-prepare s)` | **defun** — fresh `run_id` |
| `(apply #'satan-run-prepare (list s))` | **defun** |
| `(eval '(satan-run-prepare s) env)` | **defun** |

All four in-tree call sites (`satan-run.el:103`, `satan-broker.el:284/406/449`)
are syntactic, and no `funcall` / `apply` / `#'satan-run-prepare` appears
anywhere. **Verdict: latent.** The slice is not a bug fix and the rename does not
need to lead the phase order.

Both explanations on record are nonetheless wrong, and the wrongness matters
because each implies a false safety condition:

- **ADR-018 Context** attributes latency to byte-compiled callers inlining
  before the clobber. But this project runs tests **interpreted** (**C5**), and
  interpreted syntactic callers inline too. The stated mechanism is not the
  operative one.
- **SL-013 R1** hypothesises that reachability turns on load order. Both orders
  (`broker`→`run`, `run`→`broker`) were tested and inline identically. Load order
  is not the variable.

The real hazard is narrower and sharper than "wrong value at three call sites":
it is dormant until someone writes `(mapcar #'satan-run-prepare runs)`, advises
the symbol, or `cl-letf`s it in a test — at which point it silently returns a
freshly minted `run_id` with an unfrozen `time_now`, with no error.

**Reconcile debt.** ADR-018's Context paragraph and SL-013's R1 both assert a
mechanism now known to be false. Governance corrections go through a REV at
reconcile, not a hand-edit from this design.

### Findings raised during design

| | Finding | Disposition |
|---|---|---|
| **F1** | `satan-tools-hippocampus.el:22` declares a third `satan-hippocampus-dir` — **A1 falsified** | Absorbed (D5) |
| **F2** | `satan-context.el` owns `satan-run-perceive` / `-enrich` / `-assemble-context` in the `satan-run-*` namespace | Left alone (D5) |
| **F3** | `satan-context.el:661/666` calls `satan-run-dir-for-id` and reads `satan-run--iso-time-format` with **no require** for either — all four `satan-run-*` symbols are unbound after `(require 'satan-broker)`. Latent void-function, masked because the only live caller path is MCP, and because `satan-context-test.el:688` `cl-letf`s the function | Absorbed (D5) |
| **F4** | `satan-broker--spawn-running` defined **with a value** in both `satan-broker.el:42` and `satan-mcp.el:26`. Benign today (`defvar` sets only when unbound) but a duplicate definition of shared run-lifecycle state in exactly the two modules being collapsed | Absorbed (D5) |
| **F5** | `satan-mcp--mint-session` hand-rolls a 4-key run-ctx instead of the canonical 10-key constructor — a fifth instance of copy-instead-of-share | Absorbed (D5) |
| **F6** | `satan-mcp.el:22`'s comment (on the `:23` defvar) claims `satan-memory-store--current-run-id` is "Declared in satan-run.el"; it is declared in `satan-memory-store.el:27` | Corrected in passing (P3) |

### Adversarial pass

Six attacks on the design above. Two survived and change it.

**AR-1 — F7: DEC-8 is a *two*-flag protocol; §5.3 fixes only one half.**
`satan-broker.el:739-740` reads `satan-mcp--session-active` behind a `(boundp …)`
guard. So the coupling is **bidirectional**: MCP reaches into the broker for
`spawn-running`, and the broker reaches into MCP for `session-active`. Both
variables exist for the same DEC-8 mutual exclusion, and both are reached by the
soft-dependency idiom this slice exists to retire. Moving only `spawn-running`
to the leaf leaves the protocol split across two modules with a `boundp` guard
papering over the seam — and the lint will **not** flag `session-active`, because
it is defined only once. *Not forced by the lint; forced by the principle.*
**Disposition: accepted — D6 moves both flags and deletes the guard, in P4
(§5.3, §5.4).**

**AR-2 — the two `satan-hippocampus-dir` docstrings describe different
concepts.** `satan-run.el:22` says *"Read-write scratch directory inside the
jail"*; `satan-tools-hippocampus.el:24` says *"Directory holding SATAN
hippocampus entries"*. Identical default, `:type` and `:group`, but the design
assumed they are one concept without arguing it. If they are genuinely one — the
jail's writable scratch *is* where SATAN's self-curated memory lives — collapsing
is right and the surviving docstring must state **both** roles, or the next
reader will "fix" the mismatch by re-splitting them. If they are two concepts
that merely coincide today, collapsing silently couples them: changing the jail
scratch path would relocate the hippocampus corpus. **Disposition: accepted — D7 confirms one
concept and requires the surviving docstring to carry both roles.** The evidence
is that `satan-run-tool-ctx` passes this exact variable to handlers as
`:hippocampus-dir`, and `satan-tools-hippocampus.el` is the handler that writes
there.

**AR-3 — P4's exit criterion was too narrow.** It grepped only the four public
`satan-broker-*` names, missing `--failed-suffix`, `--date-bucket-for-run-id`,
`--bucket-name-p`, `--legacy-run-name-p`, `--run-id-from-leaf` and
`--spawn-running`, all of which also move. A phase can pass its own gate with six
moved symbols still referenced. **Corrected in §5.4**: the gate is now a zero-hit
grep over the full moved set. *(RV-002 F-1 later found this correction had been
applied to P4 alone; §5.4 now carries it to P2 and P3 as well.)*

**AR-4 — P1 was not self-sufficient.** The lint's ert tests live in `tools/test/`,
which the runner cannot see until `satan-test-suite-dirs` (`dev/satan-test.el:43`)
gains the directory and `just test` gains `-L ./tools`. Listing those under
"justfile / dev" without assigning them a phase would leave P1 unable to run its
own tests. **Corrected in §5.4**: both belong to P1.

**AR-5 — F5's mode-name type dependency: attacked, holds.** `satan-run-new-ctx`
derives `:mode_name` and the run-id infix from `(plist-get mode :name)`, whereas
MCP currently hardcodes the string `"interactive"`. Were `:name` a symbol, the
switch would silently change both the run-id format and the audit plist's value
type — a **C2** violation. Verified: every registered mode carries a string
`:name` (`ruminate`, `self-edit-mind`, `self-edit-mech`, `motd`, `morning`), and
`satan-mcp-register-interactive-mode` (`satan-mcp.el:96`) registers `:name
"interactive"` explicitly. The switch is value-identical. Worth noting that
`interactive` is registered at *runtime*, not load — `satan-mode-resolve
"interactive"` errors in a bare image — but `satan-mcp--mint-session` already
resolves it on the same path, so no new ordering constraint is introduced.

**AR-6 — lint scope: `satan/*.el`, non-recursive.** This matches the existing
`just lint` loop and deliberately excludes `satan/test/`, where files legitimately
shadow helpers. Stated so the exclusion is a decision on the record rather than
an accident of globbing — and so a future contributor does not "fix" the glob to
`**` and get a noisy lint that then gets weakened.

### RV-002 — external hostile pass, integrated

A formal Inquisition against the design aspect, raised after the lock at
`2b87023`. Six findings, all disposed; the verdict is in RV-002's `## Synthesis`.
The core survived: EVD-001 was **re-run rather than believed** and reproduces
under Emacs 31.0.90, so R1's *latent* verdict stands and the phase order may rest
on it; DEC-001's ownership argument, the D2 cost measurement and nine spot-checked
citations all held. What did not hold was the design's own standards applied
consistently — named there as *rigour deep but narrow-beam*, each finding being a
test the design wrote and then applied at one site only.

| | Sev | Finding | Where integrated |
|---|---|---|---|
| **F-1** | blocker | AR-3's standard reached P4 alone. P3's exit was satisfiable with nine of its ten deletions standing; P2's was the word "Green" | §5.4 phase table and the paragraph beneath it |
| **F-2** | major | The symbol-keyed lint sees 4 of 11 duplications and 0 of the 7 renamed forks — D3's own argument against a narrow VT-2 indicts D3's result | §2.1, §7 D3, §9; harvested as [[IMP-017]] |
| **F-3** | major | AR-1 was accepted and then orphaned — D6 appeared in three sections and no phase row | §5.3 (with the sequencing argument), §5.2, §5.4 P4 |
| **F-4** | minor | §2.2's "the broker's are consistently richer" false for four items and **inverted** for `mint-run-id`; R5 as written would delete the survivor's only docstring | §2.2 table, R3, R5 |
| **F-5** | minor | R7 / I3 rested on "pure path arithmetic" over three functions that enumerate and stat directories. Conclusion sound, mechanism false — §10's own lesson, recommitted | §5.3, §5.5 I3, R7 |
| **F-6** | nit | AR-1's disposition cited D7 for a D6 remedy; §5.1 labelled three survivors as migrants; §2.1 called two `defconst`s functions and `satan-broker--iso-time-format` appeared in no rename table or gate; `dev/satan-test.el:44` → `:43` | §5.1, §5.2 deletion table, §2.1, AR-1, AR-4, F6 |

Only **F-2** was disposed as a limitation on the record rather than a fix; the
other five are corrected above. F-1 gated: its correction had to land before
`/plan`, because `plan.toml`'s `EX-` ids are immutable once authored and a
vacuous exit criterion becomes the standard the phase is recorded as meeting.
