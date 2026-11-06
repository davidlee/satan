# `docs/` ledger — what is worth reading, what replaced it, and what will mislead you

Companion to RFC-021, but repo-wide: it covers all 61 `.md` files under `docs/`, not
just the attribute layer. Written for an agent that has to choose its reading before
touching code, and has limited context to spend.

**Provenance.** Surveyed 2026-11-06 against `main` at `6307a36`; the cheap fixes were applied
the same day and are recorded in §9, whose verification commands — not this prose — are the
current truth about them. Method: per-file frontmatter
and headings, full read of the short and structural docs, targeted greps against the code
for the claims that decide a verdict (registered tool names, `satan-attribute-render.el`,
`satan-observer-classify.el`, `protocol/fixtures.json`, doc-path references in `.el`), and
the doctrine corpus (`doctrine spec show SPEC-001..004`, `adr list`, `policy list`,
`rfc list`, `backlog list`). Rows marked `~` are judged from structure and grep, not a full
read.

**Verdict vocabulary** — one per file, chosen so you can act without re-deriving it:

| Code | Meaning | What you do |
|---|---|---|
| **LIVE** | Accurate today. | Read it; act on it. |
| **DELEGATED** | A doctrine entity or the code explicitly points at this file for its subject. | It is authority for that subject; keep it current. |
| **REFERENCE** | Right shape, stale detail. | Read for orientation; verify any specific claim before citing. |
| **HISTORICAL** | Record of a transition that finished. | Do not act on it or cite it as current. Its rationale may still be worth a look. |
| **SUPERSEDED** | Something else now owns the claim. | Go to the successor; keep this only as the record. |
| **STALE** | Its claims are false today. | Do not read it as background; it will teach you the wrong system. |
| **LOCAL** | Operator's private briefs, gitignored (`*.local.*`). | Not part of the repo; never cite; do not read unless asked. |

---

## 1. The frontmatter is not a verdict

Every doc carries `metadata.status`, and it is unreliable enough that treating it as
truth is a trap. Four examples, all verified:

- `architecture.md` says `status: canon` — and genuinely is current (it names ADR-017,
  SL-002, SL-034, malebolge). So the field can be right.
- `patch/brief.md` says `status: canon` — but the elisp patch runner it specifies was
  removed by SL-023; SPEC-004 owns the subject now. The field is wrong.
- `at-satan/design.md` says `status: draft` — but `notes_at_satan_scan` / `notes_at_satan_done`
  are registered tools (`satan-tools-atsatan.el:608,616,624`) and `tick-agent` runs. The
  subject shipped; the field never moved.
- `memory/design.md` says `status: canon` with 81 references to `dl-satan-*` / `.emacs.d` /
  `bough`. Canon by label, partially obsolete by content.

And `updated_at` / `verified_at` were unusable in 11 files, which carried the literal
`03398479` — a directory-inode artifact from the docs reshape, in a field whose own
documentation reads `<7-char SHA>`. Those two keys are now gone from those files, and
git answers instead (§9 R1).

**Consequence:** the verdict column below is derived from content and code, not from
metadata. Fix the metadata only after fixing the content (see §7).

---

## 2. Read order per task

The minimum a competent agent should read, and nothing else until it needs more.

| If your task is… | Read, in order | Do not read |
|---|---|---|
| Orient on the whole system | `doctrine spec show SPEC-002`, then `docs/architecture.md` | `governance.md` §Modes/§Tools, `docs/review/` |
| Work on the wire protocol / harness | `docs/protocol.md` (DELEGATED), `doctrine spec show SPEC-003`, `protocol/fixtures.json` | `docs/review/12-HARNESS-BOUNDARY.md` |
| Work on attributes / the daemon | `docs/attributes/design-contract.md`, `docs/attributes/wiring-status.md`, `doctrine show RFC-021` | `docs/attributes.brief.md`, `docs/refactor/T-attr-*.md` |
| Work on outcome classification | `docs/attributes/outcome-semantics.md`, `docs/observer-classify.md` | `docs/review/07-CORRECTNESS-SNIFFS.md` |
| Work on the memory substrate | `docs/memory/design.md` §0–§2 (grammar), then the code | `docs/memory/handover.md` (2026-07-12 state) |
| Work on the patch runner | `doctrine spec show SPEC-004`, `satan/satan-patch-rpc.el` | the entire `docs/patch/` tree |
| Work on `@satan` / `tick-agent` | `docs/at-satan/design.md` §Overview–§Claim lifecycle, `satan-tools-atsatan.el` | its §Implementation guide (already done) |
| Understand what data reaches the model | `docs/data-collection.md` (REFERENCE), `doctrine show ISS-065` | `docs/governance.md` §Modes |
| Understand *why* a decision was made | the matching doctrine entity first, then `docs/` for the period prose | `docs/review/CODE_REVIEW*.md` as authority |

---

## 3. The ledger

### 3.1 Live

| File | Lines | Verdict | Why | Evidence |
|---|---|---|---|---|
| `docs/architecture.md` | 107 | LIVE | Container-and-layer tour, current with ADR-017/018 and SL-002/034; defers to SPEC-002 for the container graph, which is correct altitude separation | full read |
| `docs/protocol.md` | 229 | **DELEGATED** | SPEC-003 says so in as many words: "docs/protocol.md stays the message catalogue" | `doctrine spec show SPEC-003` responsibilities; `protocol/fixtures.json` exists |
| `docs/attributes/design-contract.md` | 940 | LIVE | `status: merged`, `authority: blocking`; RFC-021 makes the contract win on any disagreement; §16 is the project log | frontmatter; boot governance |
| `docs/attributes/wiring-status.md` | 322 | LIVE | Freshest doc in the tree (2026-10-26); per-attribute wired/dormant/locked, plus structural constraints | frontmatter + headings |
| `docs/attributes/outcome-semantics.md` | 408 | LIVE | `status: merged`, `authority: blocking`; `satan-audit.el:195,213-225` cites it by section for the closed vocabularies | grep of code refs |
| `docs/observer-classify.md` | 49 | **DELEGATED** by code | `satan-observer-classify.el:600` names it as "Full semantics" — the code points readers here | grep |
| `docs/attributes/hippocampus-attribute-signals.md` | 212 | LIVE | `status: contracted` and the contract is implemented: `satan-attribute-build-hippocampus-payload` cites "design-contract §6H.6", source `"hippocampus"` | `satan-attribute.el:94-101` |
| `docs/attributes/capsule-contract.md` | 158 | LIVE-ish | `status: draft` but the subject shipped (`satan-attribute-render.el`, `satan-attribute-snapshot`); treat as the spec of what exists | file exists; RFC-021 §F2 |
| `docs/attributes/patterns_attributes.design_note.md` | 194 | LIVE | Rules out pattern-local attribute vectors — a boundary still honoured (`Scope` is global-only, `types.rs:85-118`) | RFC-021 F-notes |
| `docs/perceptual-design.md` | 940 | REFERENCE→LIVE | v0 shipped (§1.5 status); still the only description of percept/resonance/motive/observer; code refs point at it (`satan-percept.el:3`, `satan-motive.el:3`) | grep + headings |

### 3.2 Reference — read for orientation, verify before citing

| File | Lines | Why it is only REFERENCE |
|---|---|---|
| `docs/data-collection.md` | 637 | Best map of what feeds a prompt and what SATAN writes, but `verified_at: 2026-05-23`, pre-extraction, with `.emacs.d` paths. Supersedes nothing and is superseded by nothing; overlaps ISS-065's inventory |
| `docs/memory/design.md` | 1096 | Grammar/canonicalizer/evidence-window design (still the substrate's only design record) but 81 refs to `dl-satan-*` / `.emacs.d` / `bough`; no doctrine spec owns the memory substrate, so this doc *is* the design — drift here is unguarded |
| `docs/resilience-design.md` | 382 | Design note for structured errors + rate-limit degradation; unlanded (no `degrad`/`rate_limit` handling in the broker), and `RSK-001` is still open. It carries its own SL-002 bough caveat |
| `docs/at-satan/design.md` | 990 | The only description of `tick-agent` and the `@satan` claim lifecycle — but `status: draft` on a shipped feature, and its §Implementation guide is spent |
| `docs/at-satan/plan.md` | 394 | Plan for the above; historical by nature, referenced for intent only |
| `docs/governance.md` | 937 | **Split verdict.** §One-sentence summary…§Proposal-first agency and §Operations/gotchas are still the best prose on *why* SATAN works this way. §Modes (:493-519) and §Tools (:520-554) are incomplete: 24 tools documented of 36 registered, and the 12 missing ones (`content_read`, `goad_ask`, `hippocampus_{delete,grep,list,overwrite,read,rename}`, `notes_at_satan_intervention_done`, `satan_final`, `speak`, `vcs_log`) are the whole newer surface. Nothing it documents is wrong — the omission is the drift, plus the mode allowlists (`CHR-014`). 7 `.emacs.d` refs |

### 3.3 Historical — a finished transition's record

| Files | Why historical |
|---|---|
| `docs/review/` — 00-CONTEXT, 01-INVENTORY, 02-DEPENDENCIES, 03-SIZE, 04-DUPLICATION, 05-COUPLING, 06-COHESION, 07-CORRECTNESS-SNIFFS, 08-TESTABILITY, 09-DOC-DRIFT, 10-LAYER-MAP, 11-TOOL-CATALOG, 12-HARNESS-BOUNDARY, 99-QUESTIONS (14) | A 2026-05 pre-extraction scout: `dl-satan-*` symbol names (48–93 stale refs per file), `.emacs.d/satan` paths. Most of what it found has since landed, moved, or died. `09-DOC-DRIFT.md` is itself drifted — it asserts "All listed files exist. No stale entries" about a file map that no longer exists. Value: how the codebase was read before the extraction, and the anti-recommendations |
| `docs/review/THEMES.md`, `CODE_REVIEW.md`, `CODE_REVIEW_PROMPT.ARCHITECT.md`, `CODE_REVIEW_PROMPT.RESEARCHER.md` | The theme set and its rationale. Still-open content: T2 (pre-spawn extraction) and T3 (capsule registry) were never started — see §6 |
| `docs/refactor/` — T1, T1.5, T2, T3, T4, T6, T7, T8, T-attr-1, T-attr-2, plan, extraction-policy (12) | Its own status table is the verdict: merged / merged / not-started / not-started / merged / merged / merged / abandoned / in-progress / done. `plan.md`'s "T-attr-1d ← next, deferred" is stale — `satan-attribute-render.el` exists. `plan.md:3` links `../../CODE_REVIEW.md`, which is a broken path (it lives at `docs/review/CODE_REVIEW.md`). `extraction-policy.md` is SUPERSEDED by POL-001 by its own declaration |
| `docs/patch/` — brief, plan, handover, archive/handover-phase3-mechanism (4) | Describe the elisp patch agent, deleted by SL-023. INDEX declares the supersession; `brief.md` still says `status: canon`, which is the strongest counter-example in §1 |
| `docs/bough-gaps.md`, `docs/bough-feature-flag-brief.md` | Bough removed by SL-002. INDEX marks `bough-gaps` superseded; the feature-flag brief self-declares in prose (`Status: **superseded**`) but has no frontmatter, so status filters will not find it. 21–24 bough/`.emacs.d` refs |
| `docs/attributes.brief.md` | 649 | The origin brief (Brooding + mechanical Shame). Superseded by `attributes/design-contract.md`; no frontmatter at all, so nothing signals its age |
| `docs/epistemics-roadmap.md` | 100 | 2026-06-03 gap analysis of the scientist loop, in frozen-corpus vocabulary (`DE-009`). The live successors are `RFC-016` (earn attention, close the loop) and `ISS-063` (the pattern layer is write-only) |
| `docs/resonance-payload-handover.md` | 146 | Handover of a change shipped 2026-05-30 |
| `docs/memory/handover.md` | 419 | 2026-07-12 state of the substrate; 49 stale refs |
| `docs/follow-ups.md` | 34 | Self-declared `status: superseded` → the backlog. Correctly marked, and a model for how the others should be marked |

### 3.4 Local, untracked

| File | Why |
|---|---|
| `docs/brief.durable.local.md`, `docs/email-brief.local.md`, `docs/brief.broker.local.md` | Gitignored by `.gitignore:41` (`*.local.*`). Operator briefs for other tracks. Not repo canon; never cite them at an agent as project fact |

---

## 4. Supersession map — what is established, and by whom

Only pairs where the successor *says so itself*, or where a doctrine entity or the code
points at the file. Everything else stays a judgement call in §3.

| Doc | Successor | What establishes it |
|---|---|---|
| `refactor/extraction-policy.md` | **POL-001** | The doc's own title and §"→ POL-001" |
| `patch/brief.md`, `patch/plan.md`, `patch/handover.md`, `patch/archive/*` | **SPEC-004** + SL-023 | INDEX "Superseded by the malebolge patch runner (SL-023)"; SPEC-004 owns patch jobs, the socket, ceilings, promotion |
| `bough-gaps.md` | none — record only | INDEX marks it superseded by SL-002's removal; nothing inherits its content |
| `follow-ups.md` | the **backlog** | The doc's own opening line, and the migration list it carries |
| `refactor/T-attr-1*`, `T-attr-2` | **`attributes/design-contract.md`** + `satan-attrd` | Design contract §8/§10.5/§17.4 absorbed the decay and rebuild semantics; the daemon implements them (RFC-021) |
| `review/12-HARNESS-BOUNDARY.md` | **SPEC-003** | SPEC-003's responsibilities cover the spawn contract and jail profile |
| `governance.md` §Modes/§Tools | **SPEC-001** (mode/tool/capability/budget policy artifact) — *in draft* | SPEC-001 responsibility 2. Because SPEC-001 is draft, the transition is pending: today neither the doc nor a spec is trustworthy on the mode table |
| `protocol.md` | none — it **is** the successor | SPEC-003 delegates to it |
| `architecture.md` | none — sibling altitude | SPEC-002 is the C4 context root and explicitly does not restate container mechanism; `architecture.md` is the readable layer tour |

**Not superseded, despite age:** `memory/design.md`, `perceptual-design.md`,
`data-collection.md`. No doctrine entity covers the memory substrate, the perceptual loop
as a whole, or the data-flow inventory. These are load-bearing documents with no
governance behind them — which is why their drift is unguarded and why §6 lists them as
gaps rather than §4 as supersessions.

---

## 5. Drift you will hit

Ids are stable; §9 records what happened to each. `status` is one of `fixed`, `open`,
`open — needs decision`, `withdrawn (claim was wrong)`.

| id | Drift | Where | Status |
|---|---|---|---|
| D1 | Frontmatter dates are a directory inode — `03398479` — in 11 files, so `updated_at` and `verified_at` are meaningless | `docs/` frontmatter | **fixed** (§9 R1) |
| D2 | Code comments point at `docs/satan/`, which no longer exists, so a reader who follows them lands nowhere | 10 sites: `satan-percept.el:3`, `satan-motive.el:3`, `satan-resonance.el:3`, `satan-sensor-alerts.el:3`, `satan-observer-classify.el:600`, `satan-audit.el:195`, `satan-tools-docs.el:4,26`, `test/satan-audit-{intervention,attribute}-test.el:4` | **fixed** (§9 R2) |
| D3 | The orientation points at the half-poisoned doc: `AGENTS.md` says read `governance.md` and `architecture.md` first, while `governance.md` §Modes/§Tools is the part an agent most wants and the part that is incomplete | `AGENTS.md` | **open — needs decision** |
| D4 | Tool table drift: `governance.md` §Tools documents 24 of 36 registered tools. Everything it lists still exists, so read it as a historical subset, not a wrong list. The 12 omissions are the newer surface (`content_read`, `goad_ask`, six `hippocampus_*` verbs, `notes_at_satan_intervention_done`, `satan_final`, `speak`, `vcs_log`) | `governance.md` §Tools | **open** (`CHR-014` holds the mode-allowlist half) |
| D5 | Broken internal link: `../../CODE_REVIEW.md` from inside `docs/refactor/` | `docs/refactor/plan.md:13` | **fixed** (§9 R3) |
| D6 | `INDEX.md` is not an index — it omits 39 of 61 files, describes itself as covering `docs/satan/`, and implied completeness | `docs/INDEX.md` | **open — needs decision** (§7) |
| D7 | `refactor/plan.md` advertises "T-attr-1d ← next, deferred" for a capsule render that already ships as `satan-attribute-render.el` | `docs/refactor/plan.md` | **open** (record only; the doc is historical, and §3 marks the family) |
| D8 | `patch/brief.md` said `status: canon` for a subsystem deleted by SL-023; `patch/plan.md` said `living` | `docs/patch/` | **fixed** (§9 R4) |
| D9 | `at-satan/design.md` says `status: draft` on a shipped tool surface | `docs/at-satan/design.md` | **open — needs decision** (is it draft policy, or shipped-and-undocumented?) |
| D10 | `bough-feature-flag-brief.md` "has no supersession marker" — **wrong**: it opens with a prose `Status: **superseded**` banner. What it lacks is frontmatter, so a `docs_search :status` filter cannot see it | `docs/bough-feature-flag-brief.md` | **withdrawn** — the claim was mine and false (§9 W1) |

## 6. Gaps — subjects with no document

Ranked by how much their absence costs a new agent.

1. **The attribute daemon (`satan-attrd`).** 4.5k lines of Rust, 14 modules, 6 migrations.
   Its only current description is RFC-021 — a mutable working doc — plus a repo whose
   README says "Scaffold only" and whose HANDOVER is dated 2026-05-23. No spec, no contract
   home for the daemon half of the attribute layer (RFC-021 Q3).
2. **The state roots and their retention.** The three roots are described in AGENTS.md and
   in `satan-custom.el`, but nothing states what may be deleted, what is backup-worthy, or
   what "discardable" means for `runs/` — `ISS-065`.
3. **The tick loop.** Modes are in `governance.md` §Modes (drifted); `IMP-063`/`IMP-064`
   exist because there is no account of what a null tick is and what the ledger should say.
4. **The pattern layer.** `ISS-063`: it is written and never read; no doc says what it is for.
5. **The memory substrate has a design doc but no spec** (§4), so grammar drift has no
   authority to contradict it.

---

## 7. Proposed sweep

**Applied** — see §9 for the action and the check that proves it: D1 (frontmatter dates),
D2 (`docs/satan/` refs in code), D5 (broken link), D8 (patch family status).

**Still needs one decision each**
- **`AGENTS.md` orientation** (D3) — currently "read `governance.md` and `architecture.md`
  first". Should be SPEC-002 → `architecture.md` → this ledger → the task row of §2. This is
  the single change that would most reduce an agent's wasted reading, and it edits policy,
  so it is not mine to make.
- **`INDEX.md`** (D6) — replace with ~40 lines: the doctrine entities to read, the `docs/`
  files that are LIVE, and a pointer here. An index that omits two-thirds of its tree is
  worse than no index.
- **`docs/review/` and `docs/refactor/`** — move under `docs/archive/` with a one-line
  header each ("pre-extraction, 2026-07-12; kept for rationale"), *after* lifting the two
  live threads (T2 pre-spawn, T3 capsule registry) into backlog items or explicitly retiring
  them. They exist now only in a tree nobody reads.
- **`governance.md`** — split. Keep philosophy/ownership/ops; delete §Modes/§Tools and point
  at SPEC-001 once it leaves draft, or at the `satan-tool-register` sites meanwhile. `CHR-014`
  then reduces to "delete the tables".
- **`at-satan/design.md`** (D9) — decide whether it is draft policy or a shipped surface's
  documentation, and move the status accordingly.

**Leave alone**
- `architecture.md`, `protocol.md`, the attribute contracts and `wiring-status.md`,
  `perceptual-design.md`, `memory/design.md`, `data-collection.md` — all still doing work.
  Their fix is §6 (give them a spec), not a sweep.

---

## 8. The question this raises

Three of the four largest docs (`memory/design.md`, `perceptual-design.md`,
`at-satan/design.md`) describe subsystems that doctrine has not adopted. Either they get
specs — and drift becomes checkable — or the repo accepts that its design prose about
memory, perception and `@satan` is ungoverned and will silently rot like `docs/satan/` did.

RFC-021 is the same question one layer down, for the attribute layer. That is why this
ledger sits beside it: the answer for `satan-attrd` will be the template for the rest.

---

## 9. Remediation log — what was changed, and how to check it

The rule this section exists to enforce: **a fix is a claim, so it ships with a check.**
Each row is falsifiable by running the block below it, in this repo, with no host access and
no trust in this prose. If a check cannot be written, the "fix" was a preference and belongs
in §7 instead.

Applied 2026-11-06 against `6307a36`. Commits: `git log --oneline -- docs .doctrine/rfc/021/docs-ledger.md`.

| id | Action |
|---|---|
| **R1** (D1) | Removed `updated_at:` / `verified_at:` from the 11 files that carried the inode `03398479`. They are derived data — the field's own documentation reads `updated_at: <7-char SHA>` — and git already owns that answer; a hand-fed derived value is exactly what rotted into a directory inode here. Backfilling the sha was tried first and rejected: it is self-invalidating (any later commit that touches the file changes the truth without touching the field), so the honest repair is deletion and `git log -1 -- <file>`. Absence is safe by design — `satan-tools-docs.el:74-76`, "keys absent in FM are simply missing from the plist". The other 47 files keep their date-form values. |
| **R2** (D2) | Rewrote `docs/satan/X` → `docs/X` in 10 code comments, and rewrote the `satan-tools-docs.el` corpus comment, which still described pre-reshape roots (`docs/satan/`, `docs/emacs/`) when `satan-tools-docs-roots` is `'("docs")`. Comments only — no form, no behaviour. `just lint` green; `bin/elisp-locate-paren-error` returned `{"ok":true}` for all nine touched files. |
| **R3** (D5) | `docs/refactor/plan.md`: `../../CODE_REVIEW.md` → `../review/CODE_REVIEW.md`, label and href. |
| **R4** (D8) | `docs/patch/brief.md` (`canon` → `superseded`) and `docs/patch/plan.md` (`living` → `superseded`), each gaining `superseded_by: SPEC-004`. `handover.md` (`historical`) and `archive/*` (`archive`) already said "not current" in the vocabulary, so they were left alone. |
| **W1** (D10) | Withdrew a claim instead of fixing anything. The ledger said `bough-feature-flag-brief.md` was "the only doc that is both dead and unmarked"; it opens with `Status: **superseded**` in prose. The real gap is narrower — no frontmatter, so a status filter cannot see it — and §3/§5 now say that. Recorded because a ledger that silently rewrites its own errors is no better than the docs it grades. |

### The checks

```sh
# R1 — the 11 files carry neither key, and the inode appears nowhere in the tree.
for f in docs/INDEX.md docs/architecture.md docs/protocol.md docs/memory/design.md \
         docs/memory/handover.md docs/at-satan/design.md docs/at-satan/plan.md \
         docs/patch/brief.md docs/patch/plan.md docs/patch/handover.md \
         docs/patch/archive/handover-phase3-mechanism.md; do
  grep -qE '^  (updated_at|verified_at):' "$f" && echo "STILL THERE: $f"
done
echo "r1 done"
grep -rn 03398479 docs satan | wc -l          # expect 0

# R2 — no code comment points at the pre-reshape path.
grep -rn "docs/satan" satan --include='*.el' | wc -l   # expect 0

# R3 — the refactor index links to a file that exists.
grep -rn '\.\./\.\./CODE_REVIEW' docs | wc -l      # expect 0
test -f docs/review/CODE_REVIEW.md && echo "r3 ok"

# R4 — both patch docs declare supersession and name the successor.
grep -n 'status: superseded' docs/patch/brief.md docs/patch/plan.md
grep -n 'superseded_by: SPEC-004' docs/patch/brief.md docs/patch/plan.md

# W1 — the claim that was withdrawn.
sed -n '3p' docs/bough-feature-flag-brief.md
```

**Not applied, deliberately.** D3 (`AGENTS.md`), D6 (`INDEX.md`), D7 (the `T-attr-1d`
claim), D9 (`at-satan/design.md` status) and the `review/`+`refactor/` archive move are
decisions, not corrections; §7 holds them. D4's tool table is `CHR-014`'s, not this
document's.

**Keeping this honest.** Four habits, in the order they matter:

1. **Check before you fix.** R1 and W1 both began as confident claims: one had the wrong
   mechanism (`03398479` is a *sha* field fed a directory inode, not a date fed nonsense),
   the other was simply false. Reading the code that consumes a field takes a minute and
   changes the repair.
2. **The check goes in the row.** A diff is not evidence six weeks later; a command is.
3. **Fix the verdict, not just the log.** When a fix changes what a reader should do, §3
   changes with it. A log saying "fixed" beside a §3 that still says "stale" is new drift.
4. **Date the survey, not the document.** §3's verdicts are true of `6307a36` plus §9's
   patches — no more. When `docs/` moves again, re-run the checks, then re-date.
