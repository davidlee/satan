# Notes SL-002: Remove bough integration

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## 2026-07-18 — Design inquisition

- Completed source-backed design review as RV-001: 8 terminal findings
  (3 blocker, 5 major); verdict is unsound to lock pending design
  reconciliation. The RV synthesis owns the detailed evidence and sentencing.
- Review cache/selector conformance remains unavailable because SL-002 declares
  no selectors; this is recorded as RV-001 F-8.
- Review-ledger and slice-note changes are uncommitted. No product source or
  accused design file was modified, and no code verification gate was run
  because this was a review-only task.

## 2026-07-22 — Plan authored

- Six phases (`plan.toml`); sequencing rationale in `plan.md`. Two orderings
  are forced, not stylistic: evidence (PHASE-02) precedes the tool-file
  deletion (PHASE-03) because `satan-memory-evidence.el:41` requires
  `satan-tools-bough`; and the tool surface is atomic because
  `satan-mode-check-tool-references` only passes with the tool unregistered
  *and* absent from every mode list.
- Boundary pins go first (PHASE-01), green-before / green-after. The risk here
  is not that removal breaks — it is that removal quietly takes preserved
  substrate with it and nothing notices, because bough data is dormant.

### Resurrection path

- **Pre-removal SHA: `74f82e057c823da344eb7f95e6a7ef5e5c337fc8`** (`74f82e0`,
  "governance: accept ADR-017 + ADR-018, amend POL-001 seat lists"). This is
  the last commit with the bough integration fully intact.
- Plus the SL-001 `design.md` §2/§10 ledger, retained as the authoritative seam
  map (slice §Context).

## 2026-07-22 — PHASE-01 complete (boundary pins)

Ten new pins, all green **with bough present**; no production file touched.
Suite: 1045 tests, 0 unexpected, 16 skipped (was 1035/0/16).

| Pin | File | Pins |
|---|---|---|
| `sync-admits-caller-supplied-bough-handle` | `satan-pattern-test.el` | fresh-introduction surface 1 — pattern sync admits a grammatical `bough_*` |
| `outcome-payload-forwards-bough-cue-handles` | `satan-attribute-test.el` | attribute outcome forwarding copies handles verbatim |
| `replace-admits-caller-supplied-bough-cue` | `satan-tools-motive-test.el` | fresh-introduction surface 2 — `motive_replace` |
| `historical-bough-trace-readable-all-paths` | `satan-memory-store-test.el` | RN-1 — all three preserved read paths in one test |
| `mark-admits-caller-supplied-bough-handle` | `satan-memory-store-test.el` | fresh-introduction surface 3 — `memory-store-mark` |
| `rank-mixed-bough-motive-fires-on-non-bough-overlap` | `satan-observer-test.el` | RN-2 (a) |
| `rank-bough-only-motive-dormant-without-bough-percept` | `satan-observer-test.el` | RN-2 (b) negative half |
| `rank-bough-only-motive-fires-on-historical-percept` | `satan-observer-test.el` | RN-2/RN-7 (b) positive half — the case round 0 got wrong |
| `bough-only-cue-stays-admittable` | `satan-motive-test.el` | D4 — preserved vocabulary |
| `audit-records-explicit-bough-cue-handles-verbatim` | `satan-broker-test.el` | fresh-introduction surface 5 — broker tool-call audit |

Surface 4 (`intervention-create` audit + projection) was already pinned at
`satan-intervention-test.el:410`; it and the other §2.D PRESERVE/ADD sites
(`satan-audit-intervention-test.el`, `satan-tools-atsatan-test.el:318/407/455`,
`satan-memory-grammar-test.el:74`, the counter-memory writer) now carry an
in-file `PRESERVED-BOUNDARY PIN — SL-002` comment naming why the bough token is
there. That is EX-3: a later pruning pass must not be able to mistake them for
integration residue.

Two small findings:

- The `satan_patterns` table stores cue handles as `cue_handles_json` (jsonb),
  not a `text[]` — the pin queries via `jsonb_array_elements_text`.
- `satan-jsonl-read-file` returns JSON arrays as **lists**, so the broker audit
  pin normalises with `append` before comparing (the arity trap again).

## 2026-07-22 — PHASE-02 complete (evidence layer)

`satan-memory-evidence.el` is at **zero** bough tokens. Suite 1036/0 unexpected
(11 bough tests removed, 2 added).

Removed: the `(require 'satan-tools-bough)`, `--bough-call`, the three read
wrappers, `--bough-tracking`/`--bough-attempts`/`--bough-ok`, `--bough-status`,
the `:bough` sensor_status key, the three evidence fields, the
`satan-memory-evidence-bough-limit` defcustom with its `:bough_limit` opt, the
`:bough_workspace` opt, truncation passes 1/4/5, and the three
`evidence.bough_*` trace-stage wrappers.

Two things the design's touch-set did not name, both forced:

- **`--flatten-tree` went too.** Its only caller was `--bough-active`. Its two
  unit tests went with it.
- **`--shrink-annotations` went too.** Its only caller was pass 4.

Judgement calls worth flagging at audit:

- **`--truncate` keeps its `hard-cap` parameter, now unused** (`_hard-cap`).
  Both surviving passes are target-gated, so nothing reads it. Deleting the
  parameter would change the call signature and leave ISS-001 nowhere to
  attach; the docstring says so explicitly rather than leaving a mystery arg.
- **Pass numbering is frozen, not compacted.** Passes 2 and 3 keep their
  original labels so `:truncated_at` strings stay comparable across the
  removal. The docstring records that 1/4/5 were removed.
- **The new VT-2 test asserts the object stays oversized** once the passes are
  exhausted. That is the honest post-removal behaviour and the thing ISS-001
  exists to fix; asserting a byte bound here would encode a guarantee that has
  never held.

Hard-cap wording surfaces (1) header `:budget_hard_cap_bytes`, (2) the
`budget-hard-cap` defcustom doc and (3) the `--truncate` docstring now say
last-resort / best-effort and name ISS-001. Surfaces (4) and (5) are docs —
PHASE-06.

## 2026-07-22 — PHASE-03 complete (tool surface)

`bough_read` no longer exists. Suite 1015/0 unexpected, 13 skipped (the three
`satan-bough/*` skips left with the test file). Harness: 52 tests OK.

- `satan/satan-tools-bough.el` (361 lines) and
  `satan/test/satan-tools-bough-test.el` (279) deleted.
- `satan-memory.el` require + docstring; `satan-mode.el` 5 specs;
  `satan-tick.el` tick-pulse + tick-agent; `runloop.py` tier-2 entry;
  `test_gptel_harness.py` fixture and its assertion.
- `satan-broker-test.el`: require, two manifest description fixtures, three
  prose comments. Its PHASE-01 audit pin stays.

VT-1 `(satan-mode-check-tool-references)` → nil. VA-4 holds: `satan-mode-test.el`
and `satan-mcp-test.el` are untouched and green.

VT-2's manifest half cannot run here — tool descriptions live under
`satan-tools-descriptions-dir` in `~/notes`, outside the repo, and the
corpus-integration tests `skip-unless` it is present. `satan-mcp-test` green
unmodified is the available evidence; the external `bough_read.md` still needs
the manual cleanup already flagged for close.

## 2026-07-22 — PHASE-04 complete (sensor, tank, persisted state)

Suite 1017/0 unexpected. Eight production modules still hold a bough token, all
PHASE-05's.

**The RN-17 prune was implemented generically, and that was forced.** The design
says "prune the `:streaks.bough_unreachable` + `:causes.bough_unreachable` keys
on state read" — but writing those literals into `satan-sensor-alerts.el` would
put a bough token in a production file and break §9's zero-token gate, whose
allowlist is exactly the grammar artifacts plus the one motive occurrence. The
inquisition did not catch the collision between its own RN-17 remedy and its own
R1 gate.

Resolution: `--prune-state` drops any `:causes` key **outside the currently
derivable set** (derived from `--causes`, not transcribed), and drops `:streaks`
wholesale — no cause uses a streak threshold now that the bough one is gone. It
names no retired cause, so it satisfies the gate, and it self-heals for the next
retirement instead of accumulating a list of ghosts. Strictly better than the
literal prune, and smaller.

Consequences worth flagging at audit:

- **`--streak` / `--set-streak` deleted**, not just their caller. The bough
  streak was the only user; `:streaks` is a retired slot.
- **`satan-sensor-alerts-bough-streak-threshold` defcustom gone.** Any user
  customisation of it is now inert — acceptable, it gated a tool that no longer
  exists.
- A `:bough` key surviving in a persisted `sensor_status` is now simply not
  rendered rather than erroring, because `--source-order` no longer names it.
  Pinned by `no-bough-segment-in-sensor-line`.

## 2026-07-22 — PHASE-05 complete (derivation ends)

**Production is at the design's target state.** The only bough tokens left in
`satan/*.el` + `*.sql` are exactly the §9 allowlist: `satan-memory-grammar.el`,
`memory/migrations/0002_grammar_v1.sql`, and the single
`satan-motive--admitted-namespaces` occurrence (D4). No bough handle can be
*derived* anywhere. Suite 1012/0 unexpected.

Removed: the two canon rules, the `:focal_bough_nanoid` hint-norm,
`--predicate-bough-event-match` + its registration + `--motive-bough-nanoids`,
`focal_bough_nanoid` off the shared `hints-shape` (both schemas), and the
in-code prose in `percept`/`resonance`/`db`/`tools-memory`. `satan-motive.el:475`
help string reworded; `:85` untouched.

Beyond the touch-set, all forced:

- **`satan-tools-memory--nanoid-pattern` deleted** — `focal_bough_nanoid` was its
  only consumer.
- **Two canon fixtures pruned** (`rich_window.json`, `minimal_firefox.json`).
  The design flagged fixtures as a class but named neither; `rich_window`'s
  `expected_handles` listed four bough handles the removed rules produced.
- **`satan-memory/bough-isolation` (§9.10 lint) deleted.** It asserted "memory
  code reaches bough only through `bough_read`" — a rule about a tool that no
  longer exists. PHASE-06's zero-token gate subsumes it and is strictly
  stronger: §9.10 forbade four named substrings in six modules; the gate forbids
  the token in all production files. Recorded because deleting a lint always
  looks like weakening one.
- The purity lint's forbidden-symbol list lost its two bough entries — the
  symbols no longer exist, so they were inert.

**Correction to PHASE-01.** My PHASE-01 EX-3 annotation added a comment to
`satan-memory-grammar-test.el`, which breaks §9 R2's "green **unmodified**".
Reverted: the file is byte-identical to the pre-removal SHA again. The design
itself documents why that pin exists, so the comment bought nothing and cost the
no-diff property. `satan-mode-test.el` and `satan-mcp-test.el` are likewise
byte-identical, as are both preserved grammar artifacts.

## 2026-07-22 — PHASE-06 complete (docs, gates, follow-ups)

Suite 1018/0 unexpected (6 gate tests added). Corpus clean.

### The gates (`satan/test/satan-bough-removal-gate-test.el`)

Six standing invariants, not "did the removal happen" checks. **Negative-tested**
— a bough token appended to `satan-tank.el` and a "hard cap is mandatory" line
appended to `satan-percept.el` both turned the suite red, then were reverted. A
gate that cannot fail is worse than no gate.

Two of them guard the *preserved* side, which is the part that will look like
oversight to a future reader: the grammar vocabulary stays whole, and the motive
admitted namespaces keep their bough entries.

`allowlist-entries-all-exist-and-are-used` is deliberately load-bearing in the
other direction: when IMP-016 lands it goes **red**, telling you the allowlist
is now too long. The gate file retires with that item.

### Docs

- **Reconciled in place:** `governance.md` (mode tables, tool catalog, tool
  module table, file map, source-of-truth principle, staged-action list, failure
  modes, open thread 14, status table), `architecture.md`, `data-collection.md`
  (§3.4 deleted; §5.4 cap wording), `perceptual-design.md`, `patch/brief.md`,
  `patch/plan.md`, `INDEX.md`.
- **Banner + targeted correction:** `memory/design.md` (95 refs) and
  `memory/handover.md` (41). Both are canon/living but structurally *historical*
  — a delivery record and a design record. Line-editing every reference would
  falsify the history they exist to carry, so each got a banner drawing the
  boundary (grammar = still true, integration = removed) plus edits to the
  claims that read as standing truth: invariants, tool sections, source tables,
  acceptance criteria. Removed sections are marked `[removed SL-002]` rather
  than deleted.
- **Superseded whole:** `bough-gaps.md` (front-matter flipped to `superseded`),
  `bough-feature-flag-brief.md`.
- **Annotated only:** the seven draft/secondary docs.
- **Untouched, verified:** `attributes/outcome-semantics.md`
  (`authority: blocking` — its bough cue example stays semantically valid under
  the preserved vocabulary) and `docs/review/*` (frozen snapshots). Confirmed by
  diff against the pre-removal SHA.

### Follow-ups

- **ISS-001** body rewritten to the post-removal inventory and retitled — the
  "documented as mandatory" half is now fixed, the "never enforced" half is not.
  Explicitly **not closed**. The `hard-cap` parameter survives on `--truncate`
  as its attachment point.
- **IMP-016** filed for OQ-3, related to SL-002. It names the pins that assert
  the behaviour it will change, as its own checklist.
- **ISS-007** filed during PHASE-01 setup (grammar db-sync tests never run).

### For the close

- **Manual, outside this repo:** delete the `bough_read.md` tool description
  under `satan-tools-descriptions-dir` (`~/notes/satan/tools/`). Nothing in the
  repo can verify this; nothing in the repo depends on it either — the tool is
  unregistered, so no manifest build asks for the file.
- **Resurrection point:** `74f82e057c823da344eb7f95e6a7ef5e5c337fc8` plus the
  SL-001 §2/§10 seam ledger.
- **Historical bough data stays readable and copy-forwardable.** That is the
  design's decision (D4/D1), not an oversight — VH-7 is the keeper accepting it.

## 2026-07-22 — Audit + reconciliation

Suite 1018 tests, 0 unexpected, 13 skipped. Corpus clean.
`verify-vt`: **16 pass, 2 waived, 0 fail**. `reconcile-phases`: nothing to
reconcile. No spec requirements, so requirement reconciliation is vacuous.

### What conformance caught that the phases did not

Four declared design-targets were never touched. Three were real:

- **`satan-percept-test.el` and `satan-resonance-test.el` let-bound
  `satan-bough-program`**, a defcustom PHASE-03 deleted. Elisp lets you bind a
  free variable, so this was silent and meaningless and would have survived
  indefinitely. This is the same class of hazard as the `satan-run-prepare`
  collision: legal, inert, invisible.
- **`satan-resonance/gate-admits-bough-event` built its fixture on rule_id
  `bough.recent_status_change`** — a canon rule PHASE-05 removed. The gate it
  covers is content-agnostic (it asks only whether a rule_id is outside the §S2
  exclude list), so the test asserted real behaviour through an impossible
  fixture. Retargeted at `cwd.artifact`; coverage unchanged, fixture now
  producible.
- **`satan-intervention-mark-test.el`** carries a PRESERVE pin (§2.D) and is now
  annotated as one.

`docs/protocol.md` was declared but is genuinely clean — the §2.C cue-handle
reference it cited no longer exists.

### Corrections to my own plan, made at audit

Three VT mandates were mis-authored:

- **PHASE-03 VT-1/VT-2 were self-contradictory with their own phase's VA-4.** A
  VT mandate proves a claim by pointing at a test file the slice modified —
  but design §5.6 and VA-4 require `satan-mode-test.el` and `satan-mcp-test.el`
  to stay *unmodified*, so those two could never attribute. They were VA work
  wearing a VT label. Waived, evidence re-carried as appended VA-5/VA-6; ids
  are immutable so the rows stay.
- **PHASE-03 VT-3's `^def test`** could never match: the harness tests are
  methods on a `TestCase`, therefore indented.
- **PHASE-06 VT-2 asked for byte-identity**, which is a one-time audit check
  (done via git, SHA recorded above) and cannot be a standing test — a
  legitimate future grammar edit would break it. Retargeted at the durable
  form: the vocabulary is still declared with its original worlds and weights,
  in both halves.

### Undeclared-but-intended edits

Conformance lists 22 undeclared paths. All are either doctrine/backlog entities
(not source selectors) or the `scope-relevant` docs the design explicitly said
would be "dispositioned at plan" with light annotation (§2.C), plus three the
design named as a class without naming files: the two canon fixtures, and the
new gate test file. `satan-memory-grammar-test.el` appears because PHASE-01
modified it and PHASE-05 reverted it — net zero against the pre-removal SHA.

### Outstanding — blocks close

*(Dispositioned 2026-07-22 — see "VH-7 disposition" below.)*

**VH-7 only.** The keeper must (a) delete `bough_read.md` under
`satan-tools-descriptions-dir` (`~/notes/satan/tools/`) — outside this repo,
unverifiable from here, and depended on by nothing since the tool is
unregistered; and (b) accept that historical bough-attributed data stays
readable and copy-forwardable until IMP-016. Both are decisions, not work.

The slice sits at `reconcile`. Nothing else is pending.

### Census at plan time (2026-07-22)

Live bough token counts, for divergence detection at audit — 67 files. Largest:
`satan-tools-bough.el` 108, `docs/memory/design.md` 95,
`satan-tools-bough-test.el` 93, `satan-memory-evidence.el` 70,
`satan-memory-evidence-test.el` 65. The design's touch-set covers all of them;
two fixture files (`test/canon-fixtures/rich_window.json` 8,
`minimal_firefox.json` 1) are not named as selectors but fall under §2.D
classification — disposition them at PHASE-05.

## 2026-07-22 — VH-7 disposition

Both halves confirmed by the keeper; the slice closes.

- **(a) `bough_read.md` removed** from `satan-tools-descriptions-dir`. Keeper's
  confirmation is the evidence — the file is outside the repo and no in-repo
  check can attest to it.
- **(b) Historical bough-attributed data stays readable and copy-forwardable**
  until IMP-016. Accepted as the design's decision (D4/D1), not a defect.

### VH-7 extended: the model-facing notes corpus

VH-7 as authored named only the tool description file. The audit had treated
`~/notes` as unverifiable from the working environment; it is in fact readable,
though what this environment carries is a two-file skeleton, not the keeper's
corpus. Both files it does carry still advertised bough to the model:

- `satan/tools/satan_boot_context.md` — the `# Percept` block described
  "sensor-derived focus/browser/**bough**/git context". The percept assembler
  now reads focus, browser and git only; the line was stale, not merely
  cosmetic.
- `satan/prompts/interactive.txt` — listed `**bough** — link graph / knowledge
  graph traversal` among the available tool categories, a capability the model
  can no longer invoke.

Both corrected under VH-7 at the keeper's direction. **The corpus this
environment sees is a skeleton — the keeper's real corpus needs the same two
edits, plus a `grep -ri bough ~/notes` sweep for surfaces the skeleton omits.**

This is the class of residue the slice's zero-token gate cannot reach:
`satan-bough-removal-gate-test.el` covers production files in this repo, and
model-facing content lives outside it by design (D4/POL). Nothing standing
guards it. Recorded rather than automated — a gate over a corpus the repo does
not own would fail on every machine that lacks it.
