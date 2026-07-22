# SATAN code review — refactor recommendations before attributes lands

> **Note (2026-05-23):** Themes extracted into [`docs/satan/refactor/`](docs/satan/refactor/plan.md) as living per-theme briefs. This file preserved as the frozen point-in-time review.

## 1. Executive summary

The downstream work tranche is `docs/satan/attributes.brief.md` — an 8-attribute metabolic layer in which Shame mechanically remembers wrongness and depends on observing negative outcomes of prior interventions. The current codebase has no first-class intervention record, a positive-only outcome observer, and a 157-LOC pre-spawn pipeline that accretes a new step every phase. Landing attributes on top of the current shape would encode lifecycle, audit timing, and error policy into an already-overloaded `broker--spawn` and an 859-LOC observer module whose name "intervention" today refers to a transcript-derived candidate, not a declared record. The themes below clear that path before attributes begins.

Eight prioritized themes (the per-theme worksheet is `review/THEMES.md`):

- **T1** — Split the outcome observer into a thin coordinator + a pure classifier module. Mechanical. *Quality-of-life; small.*
- **T1.5** — Outcome-semantics design contract (lifecycle, candidate verdicts, manual `:harmful` only in v1) — *defines the vocabulary T7 must encode.*
- **T7** — Audit-event types for interventions + a Postgres query projection rebuildable from the audit log. Adds per-handler intervention recording; migrates observer read-path. *Hard blocker for attributes.*
- **T2** — Extract the pre-spawn chain from `broker--spawn` into a declarative step list. One behaviour-neutral PR. *Avoids accreting the attribute-update step into the existing smear.*
- **T3** — Capsule render registry, narrow: sections ordered/named/registerable with byte-identical output. *Optional but cheap; gates whether attribute bars enter the capsule via a clean register-call or yet another nested edit.*
- **T6** — Split the 2337-LOC `test/dl-satan-test.el` monolith into per-module test files. *Independent of attributes; mechanical; lifts a long-standing maintenance burden the attribute test suite would worsen.*
- **T4** — Collapse the tool/mode-allowlist duality (drop documentary-only `:modes` field). *Quick win.*
- **T8** — Externalise the pi-adapter's API-key list to a shared spec. *Quick win.*

Dropped after verification: patch-agent 8-file split (load-bearing); `defcustom` scatter (no real finding); governance-tool-drift (scout miscounted).

**What works well, leave alone:** the memory substrate's grammar/canon/evidence/store linear chain (the reference pattern for the codebase); the dual-validator JSONL protocol with shared fixtures; the patch-agent's containment boundary; the audit substrate's append-only writer + 6-predicate verifier.

## 2. Methodology

A scout (researcher tier, prior session) wrote 14 evidence files under `review/`. I (architect tier) closed two gaps the scout had self-flagged in `review/03-SIZE.md` (macros + nesting depth) and `review/04-DUPLICATION.md` (thinking-out-loud paragraphs + a speculative function-body comparison), independently re-read the canonical orientation docs (`AGENTS.md`, `docs/satan/governance.md`, `docs/satan/architecture.md`, `docs/satan/protocol.md`, the memory + patch design docs, and the downstream attributes brief), drafted 10 candidate themes to `review/THEMES.draft.md`, then spawned five parallel read-only investigator sub-agents to verify load-bearing claims:

- **A** — every caller of the 8 pre-spawn helpers (confirmed: only `broker--spawn`).
- **C** — every caller of `memory-store-mark` (5 callsites in 3 files; observer dominates).
- **D** — every render-* / format-* function in `satan/dl-satan*.el` (26 functions across 11 files; framing headers in `~/notes/satan/system/framing.txt`).
- **G** — whether any handler today writes a structured intervention record with `expected_outcome` / `outcome_window_minutes` (no — verified across 5 user-facing handlers; the only "intervention" concept is transcript-filtering after the fact).
- **H** — what the 2337-LOC `test/dl-satan-test.el` monolith actually covers (134 tests across 18 modules).

I consulted GPT-5.5 three times for blind-spot checks. First pass forced (a) T1 to shrink from a 3-way split to a 2-way file split because the third file's promised "intervention" abstraction conflated transcript-derived candidates with declared records; (b) T7 to reframe with append-only audit events as source of truth and Postgres as a rebuildable projection, restoring governance compliance; (c) the addition of a new theme T1.5 because negative-outcome classification is design work (lifecycle / confidence / evidence handles / `:harmful` reservation), not a refactor. Second pass refined the sequencing (T1.5a design contract *before* T7's audit shapes; T1.5b classifier implementation *after* T7), narrowed T2 from per-step PRs to one behaviour-neutral PR with an explicit data-dependency abort condition, and surfaced that bundling T3 with first-time attribute UX would mix registry invention with rendering UX that affects model self-perception. Third pass identified ten further gaps now folded into the relevant themes and §6: projection-rebuild contract + idempotency requirements in T7; clock/window + manual-marking contract in T1.5a; sentinel/post-tool failure policy in T7; an attribute-control-loop-damping anti-recommendation; backfill policy, A3-determinism test-boundary, model-visibility, and rollback-switch open questions.

**What's still uncertain.** The exact set of evidence handles the negative classifier needs (T1.5a deliverable). The `:harmful` automation policy (T1.5a recommends manual-only v1; user-decidable). Whether `transcript.jsonl` retention becomes a v1 blocker once the Postgres projection is the only persistent record. Three items also surface as open questions in §6.

## 3. Themes

Each theme below carries impact / effort / risk / reversibility per architect brief §1.5.3. The per-theme worksheet at `review/THEMES.md` carries the full migration sketches and considered-and-rejected sections; this document captures the essentials for the user-facing read.

### Theme T1: Split the outcome observer (mechanical refactor)

**Impact:** Med. **Effort:** S. **Risk:** Low. **Reversibility:** Easy.

**Current shape.** `dl-satan-observer.el` (`satan/dl-satan-observer.el`, 859 LOC, 33 defuns) spans Broker + Output + State per `review/10-LAYER-MAP.md` and mixes five concerns: defcustoms (`observer.el:45-95`), intervention scanning + dedup (`observer.el:144,791,814,831`), classification (`observer.el:474,569`), persistence (`observer.el:614,666` — three of the codebase's five `memory-store-mark` callers), and broker integration (`observer.el:721`).

**Why it hurts.** Attributes adds negative-outcome classification and Shame delta logic; bolted onto the current file they land in 859 LOC of mixed-verb context. Tests live in the test monolith.

**Target shape.** Two files. Keep the intervention-scanning helpers in `observer.el` until T7 deletes them; do not relocate-then-delete. Extract only the pure classifier (`classify`, `classify-for-motives`, predicate registry) into a new `dl-satan-observer-classify.el` (~350 LOC). Earlier draft had a three-file split; GPT-5.5 push-back: extracting a "intervention" module whose contents are transcript-scraping conflates two different domain objects (the candidate-from-audit vs. the declared-record). Keep T1 honest.

**Migration sketch.** One PR: extract classifier + predicate registry into `observer-classify.el`; observer.el requires it; existing tests in `test/dl-satan-observer-test.el` unchanged.

**Considered and rejected.**
- Three-way split (observer / intervention / classify) now — conflates pre-T7 candidate-from-transcript with post-T7 declared-record.
- Move classify into `dl-satan-memory-canon.el` because classifiers are pure — wrong layer; entangles memory with observer.
- Honest interim name (`observer-transcript.el`) — helpers get deleted by T7 anyway; no point.

**First concrete step.** PR that creates `satan/dl-satan-observer-classify.el`, moves `classify` + `classify-for-motives` + the `--predicates` registry, adds `(require 'dl-satan-observer-classify)` to observer.el. Confirm `test/dl-satan-observer-test.el` is green.

**Open questions.** Does the classifier return pure verdicts and let the coordinator route persistence, or does it know about the persistence path? (Recommendation: former.)

---

### Theme T1.5: Outcome-semantics design contract + negative classifier

**Impact:** High. **Effort:** L (design + implementation). **Risk:** M. **Reversibility:** Hard (lifecycle persisted in audit events).

**Current shape.** Today's positive classifier emits one verdict shape `(:verdict "positive" :predicate :Pn)` or `(:verdict "none" :reason :kw)`. Four positive predicates check for "intervention's motive saw worked-count increment". No confidence model; no maturity reasoning beyond a binary 30-minute `--mature-p` gate.

**Why it hurts.** Attributes brief names five negative classes (`worked|neutral|ignored|contradicted|harmful|unknown`); each feeds Shame deltas in §3.3. Positive classifiers can be permissive because false positives mostly inflate confidence. Negative classification feeds Shame, so **false negatives and false positives both have behavioural consequences** — a noisy classifier produces a noisy Shame signal, biasing every downstream attribute Shame caps (Cruelty, Doubt).

Concretely:
- "Ignored" vs. "not yet attended to" is a temporal model problem, not a predicate problem.
- "Contradicted" needs the intervention's `expected_outcome` (a counterfactual) + evidence the user did the suspected behaviour + evidence an artifact emerged.
- "Harmful" needs causal reasoning that the codebase does not have.

Dropping these as new enum values into `observer-classify.el` understates the design.

**Target shape.** Split into a *design contract* (T1.5a, no code) and an *implementation* (T1.5b, code).

T1.5a's deliverable is `docs/satan/attributes/outcome-semantics.md` defining: lifecycle states (`:pending|:mature|:stale`), candidate-verdict shape (`:classification :confidence :evidence :maturity :next-revisit-at`), required evidence handles per classification kind, confidence vocabulary (small/medium/high matching attributes.brief §3.3), manual marking semantics for `:harmful` (interactive command + `@satan-intervention-harmful` notes directive), and **an explicit list of what is NOT inferable in v1** (causal harm; contradiction without expected-counterfactual evidence; fine-grained ignored-vs-pending discrimination beyond the maturity window).

The contract must also pin down:
- **Clock + window semantics.** Which clock the maturity gate uses (recommend the broker's `:time_now` frozen at `--prepare`, mirroring A3 byte-identical-rerun). Late-evidence behaviour (does evidence arriving after `:stale` cutoff trigger a revision, or get dropped?). Whether `intervention.outcome_revised` is allowed at all.
- **Manual-marking workflow contract.** Who writes the manual `:harmful` event (interactive command + notes-side `@satan-intervention-harmful` directive both ultimately go through the same `intervention.outcome_classified` writer with `:source :manual`). Where the manual evidence lives (a freeform string + a pointer to the notes file + line that triggered the mark). How revisions of manual marks are audited (every revision emits a new `outcome_revised` event; the projection's `satan_intervention_outcomes` row reflects the latest).

T1.5b's implementation lands in `observer-classify.el` (already extracted by T1): verdict-shape extension, `classify-negative` returning `:ignored`/`:contradicted` only, `:harmful` rejected at API level (manual override only), `:neutral` and `:unknown` returned by the maturity coordinator.

**Migration sketch.**
- T1.5a (before T7): one PR, a design document. No code.
- T1.5b (after T7's substrate exists): one PR per step — verdict shape, negative predicates, lifecycle coordinator, human override path (interactive command + notes directive).

**Considered and rejected.**
- Single-enum verdict (just 4 more strings) — loses confidence + evidence + maturity; produces noisy Shame.
- Automatic `:harmful` in v1 — needs causal reasoning the codebase doesn't have; false-positive Shame is worse than missing-Shame.
- Skip `:unknown` / `:neutral` — removes the conservative-default escape hatch.

**First concrete step.** Write `docs/satan/attributes/outcome-semantics.md` with the lifecycle + candidate-verdict + evidence-handle + non-inferables sections. Do *not* implement; the contract feeds T7's audit event schema.

**Open questions.** Confidence as continuous float or `:low|:medium|:high` enum? (Match attributes.brief: enum.) `:next-revisit-at` computed as `intervention.created_at + outcome_window_minutes`, with a 24h `:stale` cutoff? Where do user-supplied `:harmful` classifications enter the data flow?

---

### Theme T7: First-class intervention records (BLOCKER for attributes)

**Impact:** High. **Effort:** L. **Risk:** M. **Reversibility:** Medium.

**Current shape.** No first-class intervention record exists. The five user-facing tool handlers (`inbox_append`, `notify_send`, `proposal_stage`, `patch_job_create`, `sway_border_set`) write nothing beyond what the broker captures centrally in `actions.json` (raw action plists, no `expected_outcome` / `outcome_window_minutes` / `friction_level`). Observer reads "interventions" by filtering `actions.json` after the fact (`observer.el:144` + `observer.el:791`).

attributes.brief §3.1 mandates an intervention record at action-time with the full metadata schema (§5 SQL). attributes.brief §3.2 mandates outcome classification (`worked|neutral|ignored|contradicted|harmful|unknown`). Today's actions.json shape carries none of those.

**Why it hurts.** Without intervention records, Shame is ungrounded; negative outcomes can't be observed deterministically. attributes.brief §3.4 counter-memory ("SATAN suspected X, but the user produced Y") requires links the current shape can't carry. **Blocking for attributes.**

**Target shape (per GPT-5.5: append-only audit events as source of truth, Postgres as rebuildable projection).**

- Audit gains three event kinds, written to `transcript.jsonl` at the appropriate phase:
  - `intervention.created` — handler-side, at tool-call time. Carries stable id + full metadata.
  - `intervention.outcome_classified` — observer-side, when maturity gate fires.
  - `intervention.outcome_revised` — corner case where a later run updates a prior classification.
- `memory/migrations/0006_interventions.sql` — `satan_interventions` + `satan_intervention_outcomes` tables. **Projection only**, rebuildable from the audit events (a rebuild CLI mirrors `dl-satan-memory-renormalize`).
- `dl-satan-intervention.el` — write API (emits audit event + inserts projection row in one transaction) and read API.
- Each of the 5 handlers writes through this single API; intervention-id surfaces in `tool_result`.
- Observer's `applied-interventions-in-run` deletes; the read path moves to SQL against the projection.

The memory-substrate's Postgres-as-source-of-truth precedent (for traces) is **not** invoked. Per GPT-5.5: memory joins are an internal retrieval optimization; intervention/outcome records are governance-relevant behavioural history and warrant the audit-first shape.

**Migration sketch.** Five small PRs: audit event types + validator + protocol-doc update; migration + rebuild CLI; write API + one handler; remaining handlers; observer read-path swap.

**Design points the migration must answer (NOT optional).**
- **Projection rebuild contract.** The rebuild CLI must be deterministic + idempotent: rebuilding the projection from a fixture audit log twice yields identical rows. Drift between projection and audit log must be detectable (an ert that diff-checks projection rows against a reconstructed-from-audit view). Without a tested rebuild path, "rebuildable projection" is just a claim.
- **Event identity + idempotency.** `intervention.created` and `intervention.outcome_classified` need stable IDs (recommend `format-time-string "%Y%m%dT%H%M%S" + run-id + 6-hex-random`, matching run-id convention). Replaying an audit log must not produce duplicate projection rows. Handler-side write API is responsible for ensuring the (audit-emit + projection-insert) pair is one transaction; on crash, both either land or both roll back.
- **Sentinel / post-tool failure policy.** Today's `actions.json` is only finalised at audit-close. The intervention write happens at tool-call time. Question: if the handler's intervention write succeeds but the broker's subsequent audit-record (`broker.el:400`) fails, what is canonical? Recommendation: the handler-emitted `intervention.created` audit event is the ground truth; the `:action-applied` audit record (which links by `intervention_id`) is the cross-reference. They are two events, separately validated, separately re-readable on rebuild.
- **Outcome revision semantics.** `intervention.outcome_revised` exists for the corner case where a later run updates a prior classification (e.g. `ignored → worked` after a delayed artifact). Whether revisions are allowed at all is a T1.5a decision; if allowed, the projection's `satan_intervention_outcomes` carries the latest by `observed_at` while the audit log keeps every revision.

**Considered and rejected.**
- Postgres-as-source-of-truth with audit "secondary" (earlier draft) — governance regression; dual-writer drift.
- Pure flat-file (one JSONL stream or one directory per intervention) — viable but loses SQL query convenience for the maturity-window lookup.
- Extend `actions.json` — per-run, append-only; no cross-run query; no rebuild story.
- Stuff intervention rows into `satan_memory.traces` — different lifecycle.

**First concrete step.** PR that adds the three audit event types to the validator + fixtures + `docs/satan/protocol.md`. No callers yet. The T1.5a design contract must already exist (or be drafted as part of the same review cycle) so the audit event shape encodes the right vocabulary.

**Open questions.** Should rebuild-from-audit run on every migration, or only on operator demand? Intervention-id exposure to the model in `tool_result` — yes/no? Audit-log retention policy once Postgres projection is the only durable record.

---

### Theme T2: Extract the pre-spawn pipeline (narrow)

**Impact:** High. **Effort:** L. **Risk:** M. **Reversibility:** Medium.

**Current shape.** `dl-satan-broker--spawn` (`broker.el:638`, 157 LOC, the largest function in the codebase) hand-threads a `prepare` plist through 6 sequential pre-spawn steps via a 6-level nested `plist-put` accumulator. Inline comments name "Phase 1.1+1.2", "Phase 2.1+2.2", "Phase 3.3", "Phase 5.8" — the chain has accreted four times. Per-step error policy is encoded ad-hoc by writing or not writing a `condition-case` at the callsite (2 of 6 are wrapped; the other 4 propagate raw).

Sub-agent A confirmed only the broker calls the six pre-spawn helpers.

**Why it hurts.** Adding attributes' per-run `attribute-update` step becomes the 7th nested plist-put. GPT-5.5: *"you are not merely 'adding a seventh nested plist-put'; you are encoding lifecycle, error policy, and audit timing into the old shape, then asking a later refactor to preserve behaviour nobody designed cleanly."*

**Target shape.** A declarative step list in a new `dl-satan-pre-spawn.el`. Each step carries `:name`, `:fn`, `:error :tolerate|:raise`. A runner folds the list over the accumulating `prepare` plist applying the policy. `broker--spawn` shrinks from 157 LOC to ~30. Adding attribute-update = adding one list entry.

**Scope discipline.** Extract pre-spawn only. Do not extend to sentinel / post-tool-call flow.

**Migration sketch.** One behaviour-neutral PR: extract + cut over together (GPT-5.5: per-step PRs stretch the risk window across the broker's hot path). A possible second PR makes data-dependencies explicit as `:takes`/`:puts` slots **if and only if** the extraction surfaces hidden ones.

**Abort condition.** T2 is only worth merging if the extracted form makes data dependencies and tolerated failures clearer than today. If it merely shortens the function, defer.

**Considered and rejected.**
- Hook-based dispatch — loses determinism + ordering control; A3 byte-identical-rerun invariant becomes harder to test.
- `cl-generic` per-step — over-engineered for 6 steps.
- Extract only the plist-put chaining into a helper — doesn't address accretion.
- Leave `broker--spawn` alone, add attribute-update inline — defers the cost into a future bigger refactor.

**First concrete step.** PR that defines `dl-satan-pre-spawn-steps` + `pre-spawn-run` in `satan/dl-satan-pre-spawn.el`, replaces the 157-LOC inline chain in `broker--spawn` with the runner call. A3 determinism test must remain green.

**Open questions.** `defvar` or `defcustom` for the step list? (Recommend `defvar`; tests `let`-rebind.) Does the runner need conditional steps (`:when`)? Today no — every mode runs every step.

---

### Theme T3: Capsule render registry (narrow)

**Impact:** Med. **Effort:** S–M. **Risk:** Low (narrow scope). **Reversibility:** Easy.

**Current shape.** 26 render-* / format-* functions across 11 files (sub-agent D). 5 broker-side assemblers in `context.el` (now/today/sources/recent-runs/prompt); per-module `render-block` in `percept.el`, `resonance.el`, `motive.el`, `sensor-alerts.el`. Block headers live in `~/notes/satan/system/framing.txt` (8 keys; text-first ethos preserved). `--render-prompt` reads framing + calls each block's render-fn in a fixed sequence inside its body.

**Why it hurts.** Adding attribute bars = write `dl-satan-attributes-render-block` + add framing key + require + a line in `--render-prompt`. Three touch points, no automatic test that the block was registered. Future blocks (Pressure, Brooding state, Metamorphosis triggers per attributes.brief §4) repeat the pattern. GPT-5.5: *"Attribute presentation is not just rendering; it becomes part of how the model perceives itself and how the user audits state."*

**Target shape (narrow).** A capsule registry in `dl-satan-capsule.el`. `dl-satan-capsule-register` takes `:order`, `:framing-key`, `:render-fn`. `--render-prompt` becomes a fold over the registry. Adding attribute-bars = one register call.

**Migration sketch — pick ONE path.**
- **Path A (narrow registry before attributes).** PR 1: define registry + register helper, no callers. PR 2: register every existing block via the new API. Golden-file test asserts byte-identical output across all modes.
- **Path B (skip the registry).** Land attribute bars via the existing 11-file pattern. Defer the registry until rendering pain is real.

**Recommendation: Path A.** Cheap, byte-identical, gives attribute bars a clean register-call. Flips to Path B if PR 2's golden-file test surfaces existing render-order surprises that imply implicit invariants.

**Do NOT bundle T3 with first-time attribute UX in one PR.** Mixes registry invention with the model-perception-relevant rendering of the bars themselves.

**Considered and rejected.**
- Promote `framing.txt` to a full dispatch registry — text-first is great for headers, bad for function dispatch.
- Re-aggregate all renderers into `context.el` — re-creates a god file.
- Hook-based — loses ordering guarantees.

**First concrete step.** PR 1 (data + helpers, no callers). PR 2 only if the golden-file test confirms byte-identical output.

**Open questions.** Should the registry enforce framing-key presence at register-time, or fail gracefully at render-time? (Recommend register-time per protocol.md fail-loud ethos.)

---

### Theme T6: Split the test monolith

**Impact:** Med. **Effort:** M (mechanical but tedious). **Risk:** Low. **Reversibility:** Trivial.

**Current shape.** `test/dl-satan-test.el` is 2337 LOC containing 134 ert-deftests covering 18 modules (sub-agent H). Already well-sectioned by source-module name prefix. Memory substrate is the working alternative: 8 dedicated per-module test files totalling ~119 tests (`review/08-TESTABILITY.md`).

**Why it hurts.** Finding tests for a module requires searching by name prefix inside a 2337-line file; running a module's tests means running all 134; adding attribute-related tests (state, intervention records, outcome classifications, Shame deltas, capsule rendering — easily 30+ new tests) would push the monolith past 3000 LOC.

**Target shape.** Per-module test files mirroring the memory substrate pattern. Roughly 12–15 new files: `test/dl-satan-jsonl-test.el`, `test/dl-satan-block-test.el`, etc. Some closely-related sections (broker prepare + utilities + manifest) collapse into one file.

**Migration sketch.** One PR per module. Lift the section, drop into a new file with `(require 'dl-satan-MODULE)` + helpers, confirm green. Start small (jsonl, 6 tests) to prove the pattern; finish with the large sections (context, broker, tools registry).

**Considered and rejected.**
- Section the monolith with markers without splitting files — kicks the can.
- Split by responsibility (handler / dispatch / budget / audit) — doesn't align with module boundaries.

**First concrete step.** PR that extracts `dl-satan-jsonl-test.el` from `test/dl-satan-test.el` L44–112. Confirm both old + new files run green.

**Open questions.** Cross-module tests (`dl-satan-broker/refuses-spawn-when-budget-exceeded` exercises both broker and budget) — file by assertion subject (broker) with a comment, or by setup (budget)? Recommendation: assertion subject.

---

### Theme T4: Quick win — collapse tool/mode-allowlist duality

**Impact:** Low. **Effort:** S. **Risk:** Low.

**Current shape.** Three places to know about tool→mode mapping:
1. `dl-satan-mode.el` mode-spec `:tools` list — authoritative; broker consults it.
2. `dl-satan-tools-atsatan.el` calls `dl-satan-tick-register` at load time to dynamically add `patch_job_*` to the tick-agent mode.
3. Each tool spec carries a `:modes` field — per `docs/satan/patch/handover.md`, *documentary only; the broker does not consult it*.

**Target shape.** Delete the `:modes` field from tool specs. Add a load-time consistency check that asserts every tool referenced in a mode spec exists in the registry.

**First concrete step.** PR that greps every tool spec for `:modes`, confirms no runtime consumer, deletes the field, adds the consistency check.

---

### Theme T8: Quick win — externalise pi-adapter API-key list

**Impact:** Low. **Effort:** S. **Risk:** Low.

**Current shape.** `dl-satan-patch-adapter-pi-api-key-vars` is a hardcoded 7-element list in elisp; the pi binary (built by Nix flake) must accept the same env var names. No shared spec (`review/12-HARNESS-BOUNDARY.md` §items-from-one-side).

**Target shape.** Either a shared `satan/protocol/api-key-vars.json` consumed by both sides, or a short README in `docs/satan/patch/adapter-pi.md` documenting the contract and the discipline.

**First concrete step.** Either PR (extract to JSON) or doc PR. User-decidable; the JSON path is mechanically cleaner.

## 4. Quick wins

Independent, mergeable any time, no ordering constraint:

- **T4** — delete `:modes` from tool specs; add load-time consistency check. ~1 PR.
- **T8** — externalise pi-adapter API-key list. ~1 PR.
- **scout-deliverables tidy** (already applied in this review): `review/03-SIZE.md` and `review/04-DUPLICATION.md` had stubbed sections + thinking-out-loud paragraphs; corrected. Function-LOC table in `03-SIZE.md` was inflated (claimed `normalize-hints` 296 LOC; actual 69 LOC; the scout's counter mis-handled top-level macro calls) — replaced with a paren-balanced count.

## 5. Anti-recommendations

Patterns the scout flagged or that I considered, but which should be left alone.

1. **Don't merge the patch-agent's 8-file split.** Architect brief §2.4 explicitly named this as a hypothesis. Verification (`review/02-DEPENDENCIES.md` + `docs/satan/patch/brief.md` §17) shows the split aligns with distinct responsibilities (adapter / store / worktree / runner / classifier / inbox / listener / prompt) each with phase plans. Load-bearing.
2. **Don't build a `dl-satan-memory-writer.el` facade.** Sub-agent C: 5 `memory-store-mark` callers across 3 files. Below the threshold where a facade pays for itself; call shapes are heterogeneous.
3. **Don't consolidate the `defcustom` surface.** Scout 99-QUESTIONS Q12 flagged 30+ files with defcustoms; no real problem (max 8 per file; all per-module). The scattered shape is correct.
4. **Don't make tool-spec `:modes` authoritative.** T4 alternative; would invert the established mode-centred ethos.
5. **Don't introduce a `satan/perceptual/` subdirectory.** Scout 99-QUESTIONS Q1 hints at this. Flat namespace per `docs/emacs/naming.md` matches the rest of `satan/`. A subdirectory would create the only nested structure in `satan/` and not pay for itself.
6. **Don't extend `actions.json` with intervention fields.** Per-run append-only files can't satisfy cross-run query needs; no rebuild story.
7. **Don't split `tank.el`.** Scout 06-COHESION suggested this. Tank is `M-x my/satan-tank`'s buffer-rendering surface, well-contained, no attributes-driven growth pressure.
8. **Don't automate `:harmful` classification in v1.** T1.5a recommendation: needs causal reasoning the codebase doesn't have; false-positive Shame is worse than missing Shame. Reserve for manual marking + a notes-side `@satan-harmful` directive.
9. **Don't let attributes self-amplify from weak evidence.** When attribute deltas come from low-confidence classifications, the control loop risks runaway feedback (Shame ↑ → Doubt ↑ → more abstention → fewer interventions → fewer outcomes → no signal to cap Shame). attributes.brief §6 already says "do not start with elaborate formulas; use small deltas and caps", but the architecture should bake in: (a) explicit per-attribute decay over time, (b) caps tied to confidence levels (small/medium/high deltas only fire on small/medium/high-confidence classifications respectively), (c) a "review threshold" that surfaces an inbox item when an attribute crosses a configurable bound without a clear cause. The brief leans on the model's good judgement; the architecture should not depend on it.

## 6. Open questions for the user

Decisions only the user can make.

1. **Sequence approval.** Recommended landing order:

   ```
   T4 / T8 / T6 (quick wins + test split, parallel to everything; T6 can begin any time)
   → T1            (observer file-split)
   → T1.5a         (outcome semantics design contract — doc only)
   → narrow T2     (extract pre-spawn chain; one behaviour-neutral PR)
   → T7            (audit event types + projection + handler wiring + observer read-path)
   → [attributes core tranche]
   → T1.5b         (negative classifier implementation)
   → T3 path A     (narrow registry, byte-identical output, only if rendering pain is real)
   ```

   Approve as-is, or push any theme earlier / later?

2. **`:harmful` classification policy.** T1.5a recommends manual-only in v1 (interactive command + `@satan-intervention-harmful` notes directive). Acceptable, or push for automatic-but-low-confidence?

3. **`transcript.jsonl` retention policy.** Once T7 lands, the audit log is canonical for intervention outcomes. If old transcripts are rotated or pruned, the Postgres projection is the only durable record. v1 blocker, or v2 question?

4. **T2 + T3 abort conditions.** T2 PR 1 only merges if extraction makes data dependencies + error policies clearer than today. T3 Path A only proceeds if PR 2's golden-file test confirms byte-identical output. Both have explicit rollback paths in `review/THEMES.md`. Accept the abort conditions, or push for hard commitments?

5. **T8 path.** JSON spec file vs. short adapter-pi README. Mechanically cleaner is the JSON; cheaper is the doc. User-decidable.

6. **Backfill policy for historical interventions.** When T7 lands, the pre-T7 corpus of `actions.json` records exists but lacks the new metadata (no `expected_outcome`, no `outcome_window_minutes`). Three options: (a) no backfill — the projection starts empty, observer can only score interventions created after T7. (b) Best-effort synthetic `intervention.created` events generated from historical `actions.json` with defaults filled in (e.g. `outcome_window_minutes: 30` for everything). (c) A migration boundary date — interventions before date X are unobservable; the projection rebuild ignores them. (Recommendation: option (a) — clean break, no synthetic data.)

7. **Determinism test boundary.** A3 byte-identical-rerun is a contracted invariant (`test/dl-satan-resonance-test.el:317,342` and similar). T7 intentionally breaks it for the runs that produce `intervention.created` events (each carries a freshly minted id; reruns produce different ids). State which themes preserve A3 (T1, T2, T3, T4, T8) and which intentionally break it (T7 for new event types; T1.5b for new classifier outputs). Without explicit acknowledgement the determinism tests will fail on T7's first PR.

8. **Model visibility policy.** T7 surfaces `intervention_id` in `tool_result`. Decide what else the model may reference: just the id (model can later say "the intervention I emitted earlier"), or full outcome state once classified (model can later say "the intervention I emitted earlier was contradicted"). The latter is more useful but leaks the audit-layer's internal state into the prompt API. Recommendation: id-only in v1, outcome-state on explicit `intervention_status` tool call rather than via tool_result.

9. **Rollback / disable switches.** Each of T7 + the attributes tranche needs a way to turn off recording/projection-reads/attribute-updates without corrupting the audit log. Define defcustoms: `dl-satan-intervention-recording-enabled` (defaults t; if nil, audit events still write but projection inserts skip), `dl-satan-attribute-updates-enabled` (defaults t; if nil, deltas are computed and audit-logged but not applied to the live attribute state). The disable switches should be set-able for tests and operator escape hatches; the audit log remains the always-on truth.

10. **Should the refactor plan be tracked as a separate `docs/satan/refactor/plan.md`** alongside `docs/satan/perceptual-design.md` and `docs/satan/patch/handover.md`? (Recommend yes, but that's a follow-up PR after this review lands, not part of the review itself.)
