# Review RV-020 — reconciliation of SL-020

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

**Subject and mode.** Conformance-mode reconciliation audit of **SL-020**
(`notes_read` / `notes_grep`) — both phases `completed`, VH-1 exercised live by
the user against the host's real `~/notes`. Judged against the locked design
(`design.md`, materialised revision 31, run `dr-01a0d771`), the two-phase plan
(`plan.toml`), and the governance the slice cites: POL-001 (the notes corpus is
the client's seat), ADR-017 (the trust boundary as protocol; read-only tools add
no authority row). Self-audit: raiser and responder are the same agent (`--as`),
so read this as the author attacking his own work, not as independent assurance.

**Surface reviewed.** The committed mechanism on `main` (`0e9093f` tip; slice
commits `124c268`, `1d122dc`, `21a50d8`, `2d0d64f`, `5d67b78`), the mind corpus
at `/workspace/satan-corpus` (descriptions `1d122dc`, prompt `5d67b78`), and the
slice's own artefacts. The parent tree is the only surface — the slice was not
dispatched, so there is no candidate interaction branch. The working tree is
*not* clean: it additionally carries the user's uncommitted `:budget-tokens`
bumps in `satan/satan-mode.el` (`300000` → `340000`/`400000`), plus `flake.nix`
and `.doctrine/doctrine.toml`. F-8 dispositions that divergence; nothing here is
attributed to it.

**Invariants the slice is held to.**

- The notes root is the user's and read-only to SATAN; no write path exists, and
  no read escapes the root (DEC-029; SL-015's three-roots rule).
- *Read broadly, write narrowly*: `risk = read`, no capability, **no new row in
  the ADR-017 §3 authority ledger** (verified: the ledger file is untouched since
  SL-017).
- Register-and-describe is one atomic act — a missing description breaks the
  manifest build *and* MCP startup, and the `interactive` union makes that
  unavoidable (DEC-031).
- The mode `:tools` allowlist is the authority for reachability; a registered
  tool is not reachable until allowlisted.
- **CON-001**: every registered tool is classified in the harness tier ladder;
  the drop sets are cumulative, so an unclassified tool survives every tier.
- **DEC-030**: an unavailable or failing probe is an error, never a silent empty
  result; a wrong-but-readable answer is worse than an error (SL-015).
- `design.md` §2's refusal table is **authoritative**; §4's resolver is its
  decomposition and must realise the same set.
- The four doc mirrors restate the registries and are treated by later readers as
  the system's tool inventory.
- Conformance evidence is only evidence if the **boundary registry** behind it is
  truthful — `doctrine slice conformance` is the mechanical half of this audit.

**Where the bodies are likely buried.**

1. **The registry itself.** F-2's species in the conformance half: a boundary row
   that covers nothing makes the pass *accidentally* true. Checked first.
2. **Claims the toolchain contradicts.** RV-019's five `major` findings were all
   one species — a design sentence the code or the binary refutes. The remaining
   un-executed claim is the rg long-line contract (§3), which the suite cannot
   reach because it stubs `call-process`.
3. **Enumerations missed.** RV-019 F-14..F-16 found three; a fifth surface would
   be the same class.
4. **What the model actually sees.** The descriptions are the model-facing
   contract; a falsy flag rendered on the wire as something else is a
   wrong-but-readable answer even when the code is right.
5. **Phase-boundary integrity.** T9 (the user-directed defect fix) landed in
   PHASE-02 but edited PHASE-01's selectors, and it changed the output shape of a
   pre-existing tool — both facts sit outside anything the plan's EX list covers.

**Out of scope.** The `docs_*` → `project_docs_*` rename (non-goal, own slice);
pagination (QUE-002, knowingly deferred on the user's steer); the pre-existing
staleness in `docs/resilience-design.md` §2.2/§3 (`bough_read`,
`notes_at_satan_intervention_done`) and the `satan-tools-atsatan.el` File-map
sentence — all falsified before this slice began and left deliberately.

## Synthesis

**Judgement: the work conforms, and the audit found the design's edge rather
than the code's.** Two phases, eight of eight design-target selectors delivered,
zero undelivered, zero undeclared *code* paths, and the full check reproduces
green at audit (`SATAN_TEST_ALLOW_NO_DB=1 just check` → PASS 1152/1330, 178
skipped, lint clean, harness 54 OK). `doctrine check gate` behaves here as it
does for every slice in this dev shell: its individual checks report
`{"ok":true}` and the recipe then fails at `_require-test-dbs` — no Postgres on
127.0.0.1:54322 (phase sheet C4; CHR-002's subject) — while with
`SATAN_TEST_ALLOW_NO_DB=1` the whole gate passes. Recorded rather than
dispositioned: environmental and pre-existing, not a SL-020 divergence.
Governance holds: both tools are `risk = read` with no capability, no row was
added to the ADR-017 §3 authority ledger (the file has no commit since SL-017),
the notes root has no write path, and CON-001 is satisfied by the harness ladder
in the same commit as the registrations (EX-2's "same commit" framing).

Checked and clean, so they are not findings: the ten-row refusal table against
the resolver (§2 authoritative, §4 its decomposition — including the symlink
whose truename escapes the root, the only test that exercises containment); the
DEC-030 exit classification (rg 1 is a clean empty result, rg ≥ 2 and an absent
binary are errors); the argv's globs derived from the extension defconst rather
than restated, with no per-file cap; the four doc mirrors; the `ruminate` prompt;
the corpus descriptions; IT-011's two-way diff (13 names before and after, with
neither new tool in it — the 15 → 13 reading in the phase sheet is right once
the baseline is PHASE-01's post-registration tree, not the pre-slice tip); and
DEC-033's one-way guarantee as stated.

The nine findings are three kinds.

1. **Two real defects, both fixed at audit, both cheap** (F-1, F-7). F-1 is the
   audit's own evidence problem: PHASE-01's boundary row was a no-op range, so
   the conformance pass was *accidentally* true — it survived only because the
   PHASE-02 defect fix re-touched PHASE-01's two selectors. Re-recorded as
   `217ecee..ac6de17`, tiling with PHASE-02. F-7 is the slice's own honesty flag
   arriving wrong on the wire: a bare `nil` `:truncated` renders as `{}` under
   this serialiser, so the *complete* case — every whole body, every complete
   match list — was the ambiguous one. Now `t`/`:false` per the codebase's own
   convention (`satan-tools-content.el:265,338`), verified on the real
   serialiser path and landed as `5dca87c`. The keeper chose the local fix over
   deferral to ISS-033.
2. **Three prose claims an artefact of the slice contradicts** (F-2, F-3, F-4) —
   RV-019's species, one generation on. F-2 has the most teeth: `--max-columns
   200` shows the line's *first* 200 columns whatever the match position, and
   `--max-columns-preview` changes only the omission marker, so the design's
   claim that the reader sees both the phrase and the continuation is false for
   exactly the long-line case the bound exists for. The mechanism is right — the
   marker is the tell and `path:line` stays actionable — so the defect is the
   sentence, not the argv. F-3 records that the design stopped being a complete
   account of the shipped contract when `2d0d64f` changed a *pre-existing* tool's
   output shape (`./journal/x.org` → `journal/x.org`); the fix is correct and
   live-verified, but §4/§6 never say it happened. F-4 is a stale count that
   contradicts its own section's table.
3. **Four considered non-issues, dispositioned so they are not re-derived**
   (F-5, F-6, F-8, F-9): the 11 undeclared paths are harvest records and slice
   bookkeeping, not code; `notes_grep`'s `:truncated` deliberately tracks the
   50-match hard cap and not a caller-set `limit`, exactly as `notes_recent`
   does; the tree is not clean because the keeper's uncommitted budget bumps sit
   beside the slice's commits; and an aborted `doctrine backlog new` left a
   placeholder ISS-031 that cannot be deleted.

**Standing risks and accepted tradeoffs.**

- **F-2's loss is permanent and accepted.** A `notes_grep` hit on a very long
  line may not contain its own query. It is not worth an unbounded line to fix,
  and the hit remains followable; the contract must simply stop promising
  otherwise. This is now a prose obligation for `/reconcile`.
- **The phase boundary is bent, deliberately.** A user-directed defect fix landed
  under PHASE-02 and edited PHASE-01's selectors, and it changed a pre-existing
  tool's behaviour that PHASE-01's EX-7 declared unchanged. The plan's criteria
  are immutable-append and off-surface, so no plan edit is proposed; conformance
  is slice-level and reads 8/8 either way. Recorded here so the next reader of
  `plan.toml` knows the boundary is not the whole story.
- **The wire layer's `nil` → `{}` remains system-wide.** Fixed for the two flags
  because that cost two fields and three assertions. An empty `:matches` still
  renders as `{}` (a list, not a flag, and not fixable locally without changing
  the elisp-side type), so the decision stays with **ISS-033** and its family
  (ISS-027, IMP-015).
- **The audit's own fix lies outside every recorded boundary**, by construction:
  the phases end at `c9af6e0` and `5dca87c` follows it, so `slice conformance`
  will not see it. Expected for an audit fix, and stated so it is not later read
  as a registry gap.
- **VH-1 survives the fix, and the reason is worth stating.** The live
  verification preceded `5dca87c`; the fix changes the *representation* of
  `:truncated` (`nil` → `:false`), not the key set or the semantics the verifier
  exercised, so the round-trip evidence and the plist-keys check still stand.
  The post-fix behaviour is covered by the suite (28/28 notes tests, full check
  green), not by a second live pass.
- **An audit is not independence.** This pass was self-conducted, as RV-019 was.
  What independence it has comes from the checks being mechanical — the
  serialiser, the rg binary, git ranges, the test suite — rather than from a
  second reader.

## Reconciliation Brief

Written for `/reconcile`. Every item below is a non-aligned finding routed to a
surface that writer actually touches. There is nothing to route through REV.

### Per-slice (direct edit)

- **`design.md` §2 — the `notes_read` result example** (F-7). The plist example
  writes `:truncated nil`. The shipped contract is `t` / `:false`, because the
  wire layer renders an elisp `nil` as `{}` while the codebase's false marker is
  `:false` (`satan-jsonl-send` sets `:false-object :false`; `content_read` emits
  `:truncated_results :false` for the same semantic). Update the example and add
  one sentence naming the reason, so the next tool does not repeat it.
- **`design.md` §3 — the `notes_grep` result example and the `--max-columns`
  paragraph** (F-7, F-2). Same `:truncated` correction in the example. Then
  correct the paragraph that claims the preview lets "a reader see both the
  phrase and the fact that the line continues": rg prints the line's first 200
  columns and the omission marker, so the phrase is present only when it falls
  inside that window. Keep the mechanism, drop the promise.
- **`design.md` §4 and §6 — the fd output contract** (F-3). Record what
  `2d0d64f` introduced: `--absolute-path` in the fd argv plus `--relativize`, so
  `notes_recent`'s `:path` is root-relative (`./journal/x.org` →
  `journal/x.org`). Note in §6 that this is a post-design, user-directed
  correction to a pre-existing tool, made after live verification found the
  `notes_recent` → `notes_read` round trip broken.
- **`design.md` §6 — the selector sentence** (F-4). "the five mechanism paths" →
  the eight recorded design-target selectors (six mechanism paths plus
  `docs/governance.md` and `docs/resilience-design.md`), matching the
  code-impact table in the same section.
- **`~/satan-corpus/tools/notes_read.md`** (mind repo, direct edit) (F-7).
  "`:truncated` — non-nil when the body was cut off" is elisp-framed; state the
  wire values — `true` when the body was cut off, `false` when the whole body
  came back.
- **`~/satan-corpus/tools/notes_grep.md`** (mind repo, direct edit) (F-7, F-2).
  Same `:truncated` correction. And correct the `:text` sentence: a line longer
  than 200 columns is cut there and ends with rg's own marker
  `[... omitted end of long line]`, so the phrase is in the text only when it
  falls within the first 200 columns — the marker, not the phrase, is the
  guarantee.

Commit the two corpus files in `~/satan-corpus` (a separate repo, currently
carrying unrelated in-flight changes — stage only these two paths).

### Governance/spec (REV)

- **None.** No ADR, policy, standard, spec or requirement is falsified by this
  slice: the ADR-017 §3 authority ledger is untouched, POL-001's seat list is
  unchanged, and no requirement is affected (the slice carries no `[requirements]`
  links).

## Reconciliation Outcome

Reconcile pass, 2026-09-25. Input: the `## Reconciliation Brief` above. RV-020
carries 9 terminal findings — 2 `fix-now` discharged at audit, 3 `verified`
routed here, 2 `aligned`, 2 `tolerated`. No finding remained `open`, `disputed`
or `follow-up`.

No REV was needed, and inspection confirmed it rather than assuming it: the
brief's governance/spec section is empty because nothing at that altitude is
falsified. The ADR-017 §3 authority ledger has no commit since SL-017, POL-001's
seat list is unchanged (the mechanism stayed in the client), and SL-020 carries
no `[requirements]` links, so no requirement changed status.

### Direct edits applied

- **`design.md` §2** — the `notes_read` result example now reads `:truncated
  :false`, and the truncation section gains the reason: `satan-jsonl-send`
  serialises with `:null-object :null`, under which a bare elisp `nil` reaches the
  model as `{}`; the false value is the codebase's own marker `:false`, the same
  choice `content_read` makes for `:truncated_results`. (RV-020 F-7)
- **`design.md` §3** — same correction in the `notes_grep` example (F-7), and the
  `--max-columns` paragraph no longer claims the reader sees the matching phrase:
  the cut is taken from the start of the line, so a match beyond column 200 is
  absent from `:text`. The marker, not the phrase, is what the bound guarantees,
  and `:path`/`:line` keep every hit followable. (RV-020 F-2)
- **`design.md` §4** — new subsection `## The fd output contract (post-design,
  user-directed)`, recording `--absolute-path` plus `--relativize`, the
  round-trip break they repaired, and the fact that this changed a *pre-existing*
  tool's behaviour beyond what PHASE-01's EX-7 stated. (RV-020 F-3)
- **`design.md` §6** — the code-impact row for `satan-tools-notes.el` now names
  the fd argv change (F-3), and the selector sentence says six mechanism paths
  plus the two doc mirrors of §5, eight in all (F-4).
- **`~/satan-corpus/tools/notes_read.md`** — `:truncated` stated as the wire
  values `true` / `false`. (RV-020 F-7)
- **`~/satan-corpus/tools/notes_grep.md`** — same for `:truncated`, and the
  `:text` bullet corrected: a line longer than 200 columns is cut from its start,
  so a phrase sitting past column 200 is not in the text at all; the marker is the
  guarantee, and `notes_read` can still open the hit. (RV-020 F-7, F-2)

`slice-020.md` needed no change: its scope, affected surface, non-goals, risks and
verification basis all still describe what shipped, and the two audit-fixed
defects fell inside the surface it declares.

### REVs completed

None. The governance/spec section of the brief is empty — see the check above.

### Discharged at audit (recorded for completeness)

- RV-020 F-1 (`fix-now`) — PHASE-01's boundary row re-recorded as
  `217ecee..ac6de17`, so conformance reads a real delta for both phases.
- RV-020 F-7's code half (`fix-now`) — `5dca87c` emits `t` / `:false`; this pass
  wrote the matching prose.

### Withdrawn / tolerated (no writes)

- RV-020 F-5, F-6 (`aligned`) — the 11 undeclared conformance paths are harvest
  records and slice bookkeeping, and `notes_grep`'s `:truncated` deliberately
  tracks the 50-match hard cap rather than a caller-set `limit`.
- RV-020 F-8, F-9 (`tolerated`) — the keeper's uncommitted `:budget-tokens` bumps
  and the stranded placeholder ISS-031 stay out of this slice's commits; rationale
  lives in the finding dispositions.

### Escalation

None. No item needed the `reconcile → design` back-edge: every divergence was
expressible as a prose correction to an existing artefact, and the one genuine
design departure — F-7's `nil` → `:false` — was put to the keeper, who directed
the local fix rather than deferral to ISS-033.

Handoff to `/close`. Carried forward for it: the close-out commit must be
path-scoped (the tree holds the keeper's uncommitted budget bumps, `flake.nix`,
`.doctrine/doctrine.toml` and an untracked ISS-031 placeholder), and the two
corpus description edits are committed in `~/satan-corpus`, separately from that
tree's other in-flight work.
