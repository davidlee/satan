# THEMES.md — Architect's prioritized refactor themes

Working artifact. The rendered review for the user lives at `CODE_REVIEW.md` at the project root; this file is the per-theme worksheet with full migration detail.

Eight hypotheses (`THEMES.draft.md`) became seven surviving themes after sub-agent verification + a GPT-5.5 push-back round. Two were dropped (H5 patch-agent split — load-bearing; H9 defcustom scatter — no real finding). One was correction-only (H10 governance tool drift — scout's count was wrong; doc lists all 22+ tools). GPT-5.5 surfaced **T1.5** (negative-classifier design) as a theme distinct from T1's mechanical refactor and reframed **T7** around audit-as-source-of-truth.

Themes are ordered by impact ÷ effort with reversibility as tie-breaker. **T7 is a hard blocker for the attributes tranche**; T1 + T1.5 are also load-bearing. T4 and T8 are quick wins. T2 and T3 are forward-looking debts the attributes tranche can survive but that should land soon after (T3 in particular is additive enough to bundle with attributes).

---

## T1: Split the outcome observer (mechanical refactor only)

**Impact:** Med — quality-of-life. The deep work attributes triggers lives in T1.5 (split out per GPT-5.5 review).
**Effort:** S — pure file split.
**Risk:** Low — observer-process runs inside `broker--spawn`; pipeline-test invariants must hold but no semantics change.
**Reversibility:** Easy.

### Current shape
`dl-satan-observer.el` (`satan/dl-satan-observer.el`, 859 LOC, 33 defuns) holds five distinct concerns:

- **Configuration** (`observer.el:45-95`) — `intervention-tools` defcustom, scan window, maturity gate, state-file location.
- **Intervention scanning** (`observer.el:144,791,814,831`) — `--applied-interventions-in-run`, `scan-prior-interventions`, `pending`, `mark-classified`. These read prior-run `transcript.jsonl` files and maintain the persistent dedup table.
- **Classification** (`observer.el:474,569`) — `classify`, `classify-for-motives`. Pure functions over (intervention, motive, baseline) → verdict.
- **Persistence** (`observer.el:614,666`) — `--persist-positive`, `persist-verdict`. Writes `memory_mark` traces via `dl-satan-memory-store-mark` and `dl-satan-motive-touch-footer`. Three of the five `memory-store-mark` callers in the codebase live here.
- **Broker integration** (`observer.el:721`) — `observer-process`, the broker entry. 69 LOC; orchestrates scan → classify → persist over each mature pending intervention.

### Why it hurts
attributes.brief §3.2 adds three new verdict kinds (`ignored`, `contradicted`, `harmful`); §3.3 adds Shame/Doubt/Cruelty delta logic; §6 step 5 adds a "conservative outcome observer with worked/ignored/contradicted/unknown". Bolting these onto the current file lands them in the 859-LOC mixed-verb context where adding a new `classify-negative` requires sharing helpers with `classify-positive` while also touching the persistence and broker-integration sections.

The classifier today only has one verdict kind ("positive"). Adding negatives changes the shape of `classify-for-motives`' return contract. Tests live inside the monolith.

### Target shape
Two files. The earlier draft had a third (`dl-satan-intervention.el`) absorbing the transcript-scanning helpers in preparation for T7; GPT-5.5 pushed back: extracting a module whose *name* promises first-class intervention records but whose *contents* are transcript-scraping conflates two different domain objects (candidate-from-audit vs declared-intervention-record). Keep T1 mechanical; leave scanning in place until T7 replaces the read path.

- **`dl-satan-observer.el`** (~500 LOC, shrunk) — keeps `observer-process` (broker entry), `persist-positive`/`persist-verdict`, **and** the intervention-scanning + dedup helpers (`applied-interventions-in-run`, `scan-prior-interventions`, `pending`, `mark-classified`) until T7's read-path migration lands.
- **`dl-satan-observer-classify.el`** (~350 LOC, **NEW**) — pure classification: `classify`, `classify-for-motives`, the predicate registry. No I/O. No `defcustom`. Attributes brief §3.2 negative classifiers land here, but the *shape* of negative classifiers is T1.5, not T1.

### Migration sketch
1. **PR 1 (file split, behaviour-neutral).** Extract `classify` + `classify-for-motives` + predicate registry into `dl-satan-observer-classify.el`. Add `(require 'dl-satan-observer-classify)` to observer.el. Tests still run; observer-test.el unchanged (helpers re-exported via observer.el if needed).
2. **(Deferred to T7.)** Transcript-scanning helpers stay in `observer.el` until T7 replaces the read path with the SQL projection. At that point those helpers are deleted, not relocated.
3. **(Deferred to T1.5 + attributes PRs.)** Negative classifiers land in `observer-classify.el` per T1.5's design (candidate verdict + confidence + evidence + maturity status, not a one-shot enum).

### Considered and rejected
- **Three-way split now (observer / intervention / classify).** GPT-5.5: "Avoid creating a module whose public name promises first-class interventions while its contents encode legacy audit scraping." Conflates pre-T7 candidate-from-transcript with post-T7 declared-record.
- **Move classify into `dl-satan-memory-canon.el` (since classifiers are pure).** Wrong layer (canon is about handle derivation, not outcome judgement) and would entangle memory with observer.
- **Leave observer.el alone, add `dl-satan-observer-negative.el`.** Doesn't shrink the existing file; doubles the surface; tests still go in the monolith.
- **Honest interim name (`dl-satan-observer-transcript.el`).** Considered; rejected because the helpers are deleted by T7 anyway — no point relocating-then-deleting.

### Open questions
- Does the classifier need to know about the persistence path, or can it return pure verdicts that the coordinator routes? (Probably the latter — clean handoff to attributes.)

---

## T1.5: Negative-outcome classifier design (new theme — surfaced by GPT-5.5)

**Impact:** High — Shame's correctness is entirely upstream of how well negative outcomes are classified. A noisy negative classifier produces a noisy Shame signal, which biases every downstream attribute that Shame caps (Cruelty, Doubt) per attributes.brief §1.
**Effort:** L — design problem, not a refactor. Requires lifecycle / maturity / confidence / evidence-handle vocabulary.
**Risk:** M — the wrong shape lands attributes on shaky ground.
**Reversibility:** Hard — once classification semantics are persisted in `intervention.outcome_classified` audit events, changing them retroactively means a projection-rebuild and a Shame recomputation.

### Why this is a separate theme (not buried inside T1)

Earlier draft said: "T1 PR 3 — add negative classifiers in `observer-classify.el`." GPT-5.5 push-back: *"Positive classification can be permissive because false positives mostly inflate confidence. Negative classification feeds Shame, so false negatives and false positives both have behavioral consequences. … I would split this into T1 and T1.5. T1 is mechanical refactor. T1.5 is outcome semantics: lifecycle states, maturity windows, confidence, evidence handles, reversibility, and escalation rules."*

The new theme exists because **negative classification is design work, not a refactor**.

### Current shape
The existing positive classifier (`observer.el:474` after T1's move to `observer-classify.el`) emits a single-shape verdict:

```text
(:verdict "positive" :predicate :P1)   ; or :P2/:P3/:P4
(:verdict "none" :reason :motive_dormant)  ; or :crosses_midnight / :no_baseline / nil
```

Four positive predicates (P1–P4) test for "intervention's motive saw a worked-count increment". Pure functions; no confidence model; no maturity reasoning beyond the binary `--mature-p` gate (30-minute window).

### Why "drop new verdicts into observer-classify.el" is not enough

attributes.brief §3.2 names five outcome classes for negative observation: `worked | neutral | ignored | contradicted | harmful | unknown`. Each carries weight (attributes.brief §3.3):

- `ignored` → Shame +small/medium, Doubt +small.
- `contradicted` → Shame +medium/high, Suspicion −medium.
- `harmful` → Shame +high, Metamorphosis +medium/high.

GPT-5.5: *"'Ignored' versus 'not yet attended to' is a temporal model problem, not a predicate problem. 'Contradicted' requires an expected counterfactual. 'Harmful' requires evidence thresholds and probably human override or conservative labeling."*

Concretely:
- **Ignored requires temporal reasoning.** A notify fired at 09:00 with a 30-minute outcome window. At 09:31 no artifact. Is it ignored, or did the user not look? attributes.brief §6 says "Do not infer `harmful` casually. Start conservative." That ethos extends to ignored.
- **Contradicted requires a counterfactual.** SATAN suspected drift; user produced artifact from the suspected activity. Detecting this requires (a) the intervention's `expected_outcome` (a counterfactual), (b) evidence that the user did the suspected activity, (c) evidence that an artifact emerged. None of these are derivable from the positive predicates.
- **Harmful requires causal reasoning.** "Intervention interrupted active progress." Detecting this requires (a) the intervention's timing, (b) evidence the user was making progress before, (c) evidence the progress stopped after, (d) ruling out unrelated causes. attributes.brief itself flags this as conservative-only.

### Target shape

The classifier output evolves from a single-shape verdict to a **candidate verdict** with explicit lifecycle:

```text
(:classification :ignored|:worked|:contradicted|:harmful|:neutral|:unknown
 :confidence FLOAT      ; 0.0–1.0
 :evidence              ; list of handle/payload references
   ((:kind <handle>...))
 :maturity              ; :pending | :mature | :stale
 :next-revisit-at ISO)  ; nil if mature/stale
```

Three lifecycle states for a classification:
- `:pending` — outcome window has not elapsed; classifier abstains.
- `:mature` — window elapsed; classification carries the listed confidence.
- `:stale` — too late to classify (e.g. > 24h after window close); recorded as `:unknown`.

`:unknown` and `:neutral` are **first-class safeguards**. Per GPT-5.5: *"Most negative-looking situations should mature through unknown before becoming ignored or contradicted. Harmful should be rare, evidence-heavy, and maybe never fully automatic at first."*

Default escalation rules for v1 (conservative):
- Window elapsed + no artifact + no contradiction evidence → `:ignored` (low confidence by default).
- Window elapsed + contradiction evidence present → `:contradicted` (medium confidence).
- `:harmful` — **not classified automatically in v1.** Reserved for explicit user marking (e.g. via a `my/satan-intervention-mark-harmful` interactive command, or a notes-side `@satan-harmful` directive). Document this as a known v1 conservative posture.
- `:neutral` — explicit "outcome observed, no signal in either direction" (e.g. user dismissed the notification but produced an unrelated artifact).

### Migration sketch — split into design (T1.5a) and implementation (T1.5b)

GPT-5.5 push-back: *"Storage should follow the outcome model. … T1.5a design contract before T7, T1.5b classifier implementation after T7."* The design vocabulary must be settled before T7 freezes audit event shapes, but the classifier implementation should wait until T7's substrate exists (so we don't design against imaginary evidence plumbing).

**T1.5a — design contract (before T7).**
1. **PR 1 (design doc only).** Write `docs/satan/attributes/outcome-semantics.md`: lifecycle states (`:pending|:mature|:stale`), candidate-verdict shape (`:classification :confidence :evidence :maturity :next-revisit-at`), required evidence handles per classification kind, confidence vocabulary (small/medium/high matching attributes.brief §3.3), manual marking semantics for `:harmful` (interactive command + `@satan-intervention-harmful` directive), and an **explicit list of what is NOT inferable in v1** (causal harm, contradiction without expected-counterfactual evidence, ignored vs. not-yet-attended-to discrimination beyond a fixed maturity window). No code changes.

**T1.5b — classifier implementation (after T7 lands).**
2. **PR 2 (verdict shape).** In `observer-classify.el` (extracted in T1), extend the verdict shape to the candidate form. Update positive predicates to emit confidence + evidence per the T1.5a contract.
3. **PR 3 (negative predicates).** Add `classify-negative` returning `:ignored` / `:contradicted` candidates only. `:harmful` rejected at API level. `:neutral` and `:unknown` returned by the maturity coordinator.
4. **PR 4 (lifecycle coordinator).** A `classify-with-lifecycle` wraps positive + negative classifiers, applies the T1.5a-defined maturity gate, returns the lifecycle-bearing candidate.
5. **PR 5 (human override path).** Interactive command + `@satan-intervention-harmful` notes directive that writes a `intervention.outcome_classified` event with `:harmful` classification + manual evidence pointer.

(Attributes' Shame deltas can then land using the conservative-confidence-aware delta table from attributes.brief §3.3.)

### Considered and rejected
- **Single-enum verdict (just add 4 more verdict strings).** GPT-5.5: "The classifier should probably emit something like candidate verdict + confidence + evidence + maturity status, not just a final enum."
- **Automatic `:harmful` classification in v1.** attributes.brief §3.2 + GPT-5.5: requires causal reasoning we don't have; downside (false-positive harm signal driving false Shame) outweighs upside.
- **Skip `:unknown` / `:neutral`.** Removes the conservative-default escape hatch. Pushes classifier into committing to ignored/contradicted when the evidence is thin.

### Open questions
- How does the lifecycle coordinator decide `:next-revisit-at` for `:pending` candidates? (Probably `intervention.outcome_window_minutes` after `intervention.created_at`. Possibly with a `:stale` cutoff at 24h.)
- Should confidence be a continuous float or a small enum (`:low|:medium|:high`)? Continuous loses introspectability; enum loses precision. attributes.brief §3.3 uses qualitative small/medium/high — match that.
- Where do user-supplied `:harmful` classifications live in the data flow? Probably an interactive command writing `intervention.outcome_classified` directly to the audit log, with explicit `:source :manual` in the evidence.

---

## T7: Add first-class intervention records (BLOCKER for attributes)

**Impact:** High — attributes brief §3.1 demands an intervention record with `expected_outcome` + `outcome_window_minutes`; today no such concept exists at handler time.
**Effort:** L — new SQL migration, new elisp module, wiring 5 tool handlers, retrofitting observer-read.
**Risk:** M — touches the broker membrane and adds a new persistence path. But it sits next to an established pattern (the `satan_memory` / `satan_patch` migrations).
**Reversibility:** Medium — once written, intervention records will be load-bearing; rollback means a migration down + handler revert.

### Current shape
Today the "intervention" concept exists only as **derived data read from prior-run transcripts** (verified via sub-agent G):

- `dl-satan-observer-intervention-tools` (`observer.el:45`) — defcustom listing tool names whose `:action-applied` records count as interventions.
- `dl-satan-observer--applied-interventions-in-run` (`observer.el:144`) — reads `actions.json` from prior runs and filters by tool name.
- `dl-satan-observer-scan-prior-interventions` (`observer.el:791`) — walks the 24h window of runs.
- `dl-satan-observer-mark-classified` (`observer.el:831`) — writes a dedup entry to `~/.local/state/satan/observer.json`.

Audit writes happen centrally (`broker.el:400` calls `dl-satan-audit-record` for `:action-applied/:action-staged/:action-rejected/:action-failed`). The five user-facing tool handlers (`inbox`, `notify`, `org` proposal_stage, `patch` patch_job_create, `sway`) write **no structured intervention record** themselves (verified) — only the broker's audit append captures their effects, and only as raw action plists with no `expected_outcome` or `outcome_window`.

### Why it hurts
- attributes.brief §3.1 mandates an intervention record at action-time with: `intervention_id`, `expected_outcome`, `outcome_window_minutes`, `friction_level`, `related_motive_id`, `related_trace_ids`, `cue_handles`. Today's `actions.json` shape carries none of those.
- attributes.brief §3.2 mandates outcome classification (`worked|neutral|ignored|contradicted|harmful`). Today's `applied-interventions-in-run` returns raw tool calls — no way to attach expected vs actual.
- attributes.brief §3.3 (Shame deltas) and §3.4 (counter-memory) both depend on the intervention table being present and queryable.
- The current observer-state-file (`~/.local/state/satan/observer.json`) is a per-tick dedup table, not a record store; growing it to hold attributes-grade data would re-implement a poor man's database next to the existing `satan_memory` Postgres database.

### Target shape (revised per GPT-5.5 push-back)

Earlier draft made Postgres the source of truth for intervention outcomes with `actions.json` as "secondary audit substrate". GPT-5.5: *"if Postgres becomes the observer source of truth and flat files become 'secondary audit substrate,' then SATAN's text-first guarantee has effectively moved from invariant to best-effort observability. The dangerous part is not just storage format; it is the dual-writer split."*

Revised model: **append-only audit events are source of truth; Postgres is a query projection rebuildable from the audit log.** Governance compliance preserved.

- **Audit gains intervention event kinds** (canonical, append-only). Three new `transcript.jsonl` record kinds (handled by `dl-satan-audit.el`):
  - `intervention.created` — written at handler time with stable id + full metadata (`expected_outcome`, `outcome_window_minutes`, `friction_level`, `cue_handles`, `related_motive_id`).
  - `intervention.outcome_classified` — written by observer when maturity gate fires (`classification`, `confidence`, `evidence`, `maturity_status`).
  - `intervention.outcome_revised` — for the corner case where a later run updates a previous classification (e.g. "ignored" → "worked" after late artifact).
- **`memory/migrations/0006_interventions.sql`** — `satan_interventions` + `satan_intervention_outcomes` tables. **Projection only**, rebuildable from `intervention.*` audit events. Migration includes a rebuild CLI (`dl-satan-intervention-rebuild-projection` mirrors `dl-satan-memory-renormalize`).
- **`dl-satan-intervention.el`** — write API (handler-side: `record-intervention :run-id :tool :expected-outcome :outcome-window-minutes :cue-handles :friction-level → intervention-id`; emits the audit event and inserts the projection row in the same transaction). Read API (observer-side: `pending-interventions`, `outcomes-for`).
- Each of the 5 tool handlers (notify_send, inbox_append, proposal_stage, patch_job_create, sway_border_set) writes an intervention record through this single API; the intervention-id surfaces in `tool_result` so the model can reference it.
- Observer's `applied-interventions-in-run` (which lives in `observer.el` until this theme lands — see T1) deletes; observer reads via `dl-satan-intervention-pending-interventions`.

The memory-substrate precedent (Postgres as source-of-truth for `traces`) is **not invoked** to justify this: per GPT-5.5, memory joins are an internal retrieval optimization; intervention/outcome records are governance-relevant behavioural history and warrant the audit-as-source-of-truth shape.

### Migration sketch
1. **PR 1 (audit event types).** Add `intervention.created` / `intervention.outcome_classified` / `intervention.outcome_revised` to the audit JSONL schema. Update `dl-satan-audit.el` validator + fixtures + the protocol doc. No callers yet.
2. **PR 2 (projection migration).** Add `0006_interventions.sql` with the two tables. Migration runner picks it up. Add the rebuild-from-audit CLI. Verify rebuild is idempotent against a fixture audit log.
3. **PR 3 (write API + one handler).** Create `dl-satan-intervention.el` with `record-intervention` (emits audit event + inserts projection row in one transaction). Wire `notify_send`. ert: assert the audit event exists AND the projection row exists.
4. **PR 4 (remaining handlers).** Wire `inbox_append`, `proposal_stage`, `patch_job_create`, `sway_border_set`. One PR per handler with its own ert.
5. **PR 5 (observer read-path migration).** Replace `applied-interventions-in-run` with `dl-satan-intervention-pending-interventions`. Existing dedup table (`~/.local/state/satan/observer.json`) deprecates — replaced by the projection's classification status column.
6. **(Then attributes can land §3.2 negative observer + §3.3 Shame deltas. See T1.5 for the classifier design that has to happen first.)**

### Considered and rejected
- **Earlier proposal: Postgres as source of truth, audit as "secondary".** GPT-5.5: governance regression; dual-writer drift becomes architecturally meaningful. Replaced with audit-as-source-of-truth + projection.
- **Pure flat-file (one JSONL stream for all intervention events; or one directory per intervention).** Considered after GPT-5.5 surfaced it. Viable for current volumes but loses the SQL query convenience for observer's "pending interventions whose window is mature" lookup. The projection split lets us keep flat-file canonicality AND keep observer queries fast.
- **Extend `actions.json` with the new fields.** Per-run, append-only; observer needs cross-run queries; no rebuild story.
- **Build a `dl-satan-memory-writer.el` facade unifying the 5 `memory-store-mark` callers first.** Premature abstraction (sub-agent C: 5 callers; below threshold). Heterogeneous call shapes.
- **Stuff intervention rows into `satan_memory.traces`.** Wrong shape — traces have `:kind/:handles/:payload`; interventions need `:expected_outcome/:outcome_window_minutes/:friction_level`. Different lifecycles.

### Open questions
- Should the rebuild CLI run on every migration, or only on operator demand? (Recommend on-demand, like `dl-satan-memory-renormalize`.)
- Intervention-id exposure to the model in `tool_result` — yes/no? attributes.brief is silent. Lean yes; lets the model reference "I notified about X earlier".
- How does the projection handle audit-log retention if `transcript.jsonl` files are rotated/pruned? The projection becomes the only record. Probably fine for v1; document as a "retention is a v2 question".

---

## T2: Extract the pre-spawn pipeline from `broker--spawn`

**Impact:** High — pre-spawn is the centre of every run and is accreting phase-by-phase. Attributes work adds an attribute-update step that needs to fit somewhere.
**Effort:** L — broker is load-bearing; A3 byte-identical-rerun determinism is contracted in tests.
**Risk:** M — touching `broker--spawn` risks every mode. Mitigated by sub-agent A's confirmation that only the broker calls these helpers.
**Reversibility:** Medium — refactor preserves the same step sequence, just extracts the runner.

### Current shape
`dl-satan-broker--spawn` (`broker.el:638`, 157 LOC — the largest function in the codebase) hand-threads a `prepare` plist through six sequential pre-spawn steps:

```
observer-process → percept-build → percept-persist → resonance-derive
  → motive-read → sensor-alerts-check → (then audit-open → make-process)
```

The accumulator pattern is a 6-level nested `plist-put` (`broker.el:696-706`). Inline comments name the steps "Phase 1.1+1.2", "Phase 2.1+2.2", "Phase 3.3", "Phase 5.8" — the chain has been added to four separate times.

Sub-agent A verified the broker is the only caller of all six pre-spawn helpers (`broker.el:676,679,680,681,682,691`). `motive-read` has one additional caller (the tool handler at `tools-motive.el:55`); `audit-open` has a second broker call site (`broker.el:590` for budget-exceeded-with-empty-bundle).

### Why it hurts
- Adding attributes' `attribute-update` step (attributes.brief §6 step 3) becomes the seventh accreted plist-put in the chain.
- Per-step error policy is inconsistent: `observer-process` and `sensor-alerts-check` are wrapped in `condition-case`; the others let errors propagate. The intent is clear (memory-substrate problems shouldn't fail the tick; data-shape problems should) but the policy is encoded by writing or not writing the condition-case at each call site.
- Testing the pipeline in isolation requires invoking `broker--spawn` end-to-end (or mocking everything). `broker--prepare` is tested in isolation (test/dl-satan-test.el:875-897) but the post-prepare/pre-make-process chain is not.

### Target shape
A declarative step list in a new `dl-satan-pre-spawn.el`:

```text
(defconst dl-satan-pre-spawn-steps
  '((:name observer        :fn dl-satan-observer-process    :error :tolerate)
    (:name percept         :fn dl-satan-percept-build       :error :raise)
    (:name percept-persist :fn dl-satan-percept-persist     :error :raise)
    (:name resonance       :fn dl-satan-resonance-derive    :error :raise)
    (:name motive          :fn dl-satan-motive-read         :error :raise)
    (:name sensor-alerts   :fn dl-satan-sensor-alerts-check :error :tolerate)))
```

Plus a runner that folds the list over the accumulating `prepare` plist applying each `:error` policy declaratively. `broker--spawn` becomes:

```text
(let ((prepare (dl-satan-pre-spawn-run dl-satan-pre-spawn-steps prepare-base)))
  ...rest of spawn...)
```

Adding the attribute-update step = adding one entry to the list.

### Migration sketch

**One behaviour-neutral PR, not per-step.** Earlier draft said "one step at a time". GPT-5.5 push-back: *"'one step at a time' sounds safer but actually stretches the risk window across the broker's hot path."*

1. **PR 1 (extract + cut over in one motion).** Define `dl-satan-pre-spawn-steps` + `pre-spawn-run` in `dl-satan-pre-spawn.el`. Replace the 157-LOC inline chain in `broker--spawn` with the runner call. The runner exists; the chain is preserved byte-for-byte; the broker shrinks; tests assert the resulting `prepare` plist is identical to the pre-refactor shape on the existing test fixtures.
2. **PR 2 (data-dependency audit, if needed).** GPT-5.5 blind spot: *"a declarative list can hide data dependencies. If step 4 quietly assumes fields from step 2, a list of names and functions is less honest than imperative code."* If the extraction surfaces hidden dependencies (e.g. `motive-read` needing `prepare` slots that `percept-build` only puts there), make those `:takes`/`:puts` slots explicit in the step plist. If no hidden dependencies surface, T2 stops at PR 1.

T2 is **only worth doing** if the extracted form makes dependencies and tolerated failures clearer than today. If it merely shortens the function, defer.

### Scope discipline (per GPT-5.5)
- Extract **pre-spawn chain only**. Do not extend to the sentinel / post-tool-call flow unless that shape is already obvious; today it isn't.
- Treat the `:error :tolerate|:raise` policy as *both* documentation and enforcement — the runner reads the policy, not the calling code.

### Considered and rejected
- **Hook-based dispatch (`run-hooks 'dl-satan-pre-spawn-hook`).** Loses determinism guarantees and ordering control; A3 invariant becomes harder to test.
- **`cl-generic` dispatch on a "step" generic.** Way too much machinery for 6 steps. Reverse premature abstraction.
- **Leave `broker--spawn` alone; extract only the plist-put chaining into a helper.** Doesn't address accretion; the next phase still adds a line to the call site.
- **Move the steps into individual broker-private functions (`broker--pre-spawn-observer`, etc.).** Just renames the smear; doesn't change shape.

### Open questions
- Should the step list be `defcustom` so tests can shrink it? (Yes — recommend `defvar` plus a `let`-rebound version in tests.)
- Does the runner need to support conditional steps (e.g. "skip percept-build for motd")? Today the answer is no; every mode runs every step. If that changes, add a `:when` predicate to the step plist.

---

## T3: Capsule render registry (narrowed per GPT-5.5)

**Impact:** Med — additive; matters more than the earlier draft assumed. GPT-5.5: *"Attribute presentation is not just rendering; it becomes part of how the model perceives itself and how the user audits state. If the capsule order changes, if framing text shifts, or if attribute bars crowd out motive/resonance content, that can change downstream behavior even when the data layer is correct."*
**Effort:** S–M — narrow scope (sections ordered/named/registerable with byte-identical output) is small; full registry-with-attributes-bundled is M.
**Risk:** Low for the narrow scope; medium if bundled with first-time attribute UX.
**Reversibility:** Easy.

### Current shape
26 render-* / --render-* / format-* functions across 11 source files (sub-agent D):

- **`dl-satan-context.el`** (5) — `--render-now`, `--render-today`, `--render-sources`, `--render-recent-runs`, `--render-prompt` (the master assembler).
- **Per-perceptual-module** — `dl-satan-percept-render-block` (percept.el:123), `dl-satan-resonance-render-block` (resonance.el:113), `dl-satan-motive-render-block` (motive.el:344), `dl-satan-sensor-render-block` (sensor-alerts.el:78).
- **`dl-satan-tank.el`** (5 render-* helpers, separate concern — not in the prompt capsule, in the tank buffer).
- **`dl-satan-patch-prompt.el`** (4 render-* helpers, separate concern — patch-job prompt assembly, not capsule).

The framing header strings live in `~/notes/satan/system/framing.txt` (8 keys: `now`, `percept_block_header`, `resonance_block_header`, `motive_block_header`, `sensor_block_header`, `today`, `sources`, `recent_runs`) — text-first ethos preserved. `--render-prompt` reads framing.txt + calls each block's render-fn in a fixed sequence inside its body.

### Why it hurts
attributes.brief §4 specifies an `Attributes: ###` bars block in the capsule. Adding it means: write `dl-satan-attributes-render-block`, add a `attributes_block_header` to framing.txt, add a require + a render call inside `--render-prompt`. Three touch points, no automatic test that the block was registered.

Future blocks (Pressure, Brooding state, Metamorphosis triggers per attributes.brief §4) each repeat the pattern.

### Target shape
A capsule registry in `dl-satan-capsule.el`:

```text
(dl-satan-capsule-register
 'percept
 :order 30
 :framing-key 'percept_block_header
 :render-fn #'dl-satan-percept-render-block)
```

Each perceptual module registers itself at load time (parallel to how tools register via `dl-satan-tools-register`). `--render-prompt` becomes a fold over the registry sorted by `:order`. Adding attributes = one `dl-satan-capsule-register` call.

### Migration sketch — pick ONE of two narrow paths

Per GPT-5.5: *"Do not mix registry invention with first-time attribute UX."*

**Path A (narrow T3 before attributes).** One goal: make capsule sections ordered, named, and registerable **without changing rendered output**.
1. **PR 1.** Define registry shape + `dl-satan-capsule-register` helper + `capsule-render-fold`. No callers.
2. **PR 2.** Register every existing block (`now`, `today`, `sources`, `recent-runs`, `percept`, `resonance`, `motive`, `sensor-alerts`) via the new API; `--render-prompt` becomes the fold. Golden-file test: byte-identical output against pre-refactor fixtures across all modes.

**Path B (skip T3 until after attributes).** Land attribute bars via the existing 11-file pattern (yet another `render-block`, yet another require, yet another line in `--render-prompt`). Defer the registry until the rendering pain is real and not just predicted.

**Recommendation: Path A.** Cheap, byte-identical, gives attribute bars a clean register-call instead of one more nested edit to `context.el`. But the recommendation flips to Path B if PR 2's golden-file test surfaces existing render-order surprises that imply the current code has implicit invariants the registry would break.

**Do NOT** bundle T3 with attribute-bar rendering as one PR. That mixes registry invention with the first-time UX of the attribute display.

### Considered and rejected
- **Promote `framing.txt` to a full registry (block order + render-fn lookup string).** Text-first is great for headers, bad for dispatch — registry-as-text means parsing function names from a file. Keep framing for headers; registry for dispatch.
- **Re-aggregate all renderers into `context.el`.** Re-creates a god file.
- **Hook-based.** Loses ordering guarantees.

### Open questions
- Should the registry enforce framing-key presence at register-time, or fail gracefully at render-time? (Probably register-time — fail loud per protocol.md ethos.)

---

## T6: Split the test monolith

**Impact:** Med — quality-of-life for every future test PR.
**Effort:** M (mechanical but tedious — 134 tests across 18 modules).
**Risk:** Low — tests don't change; they relocate.
**Reversibility:** Trivial.

### Current shape
`test/dl-satan-test.el` is 2337 LOC and contains 134 ert-deftests covering 18 modules (sub-agent H), already well-sectioned by source-module:

- jsonl (6), block (4), tools registry/dispatch (~20), tools-notify (4), tools-inbox (4), tools-hippocampus (3), tools-org (3), context (~12), self-edit/context (~7), tools schema-builder (4), broker prepare (~3), broker utilities (~7), broker manifest (~2), tick (~7), tools-agenda (~7), tools-activity (~11), tools-notes (~7), budget (~5), audit (~10), protocol (~7).

Memory substrate has the working alternative pattern: 8 dedicated per-module test files totalling ~119 tests (08-TESTABILITY).

### Why it hurts
- Finding a test for a specific module requires searching by name prefix inside a 2337-line file.
- Running a module's tests means running all 134.
- Adding attributes tests (attribute state, intervention records, outcome classifications, Shame deltas, capsule rendering — easily 30+ new tests) would push the monolith past 3000 LOC.

### Target shape
Per-module test files mirroring the memory substrate pattern. The file's existing section structure already maps cleanly: `test/dl-satan-jsonl-test.el`, `test/dl-satan-block-test.el`, `test/dl-satan-tools-test.el`, `test/dl-satan-tools-notify-test.el`, `test/dl-satan-tools-inbox-test.el`, etc. Roughly 12-15 new files; some closely-related sections (broker prepare + utilities + manifest) collapse into `test/dl-satan-broker-test.el`.

### Migration sketch
One PR per module. Lift the section, drop into a new file with `(require 'dl-satan-MODULE)` + helpers, confirm green. No coordination needed across PRs.

Start order:
1. jsonl (smallest, 6 tests) — proves the pattern.
2. block, tools-notify, tools-inbox, tools-hippocampus, tools-org — small handlers.
3. tick, budget, audit, protocol — small subsystems.
4. tools-agenda, tools-activity, tools-notes — read-only tools.
5. context, broker, tools registry/dispatch — largest sections, last.

### Considered and rejected
- **Section the monolith with `;;;; ---- MODULE: foo ----` markers but don't split files.** Kicks the can; doesn't solve discoverability.
- **Split by responsibility (handler tests / dispatch tests / budget tests / audit tests).** Doesn't align with module boundaries; cross-cutting splits are harder to navigate.

### Open questions
- Some tests cross module boundaries (e.g. `dl-satan-broker/refuses-spawn-when-budget-exceeded` exercises both broker and budget). Where does it live? Recommendation: in the file of the module the test asserts on (broker), with a `;; uses dl-satan-budget` comment.

---

## T4: Quick win — collapse the tool/mode allowlist duality

**Impact:** Low (mechanical correctness, not capability change).
**Effort:** S.
**Risk:** Low.

### Current shape
Three places to know about tool→mode mapping:
- `dl-satan-mode.el` mode-spec `:tools` list (authoritative — broker consults this).
- `dl-satan-tools-atsatan.el` calls `dl-satan-tick-register` at load time to dynamically add `patch_job_*` tools to the tick-agent mode.
- Each tool spec carries a `:modes` field — per handover.md, **documentary only; the broker does not consult it.**

### Why it hurts
Mild — drift between the documented `:modes` and the real `:tools` allowlist is hidden. Adding a new tool can land with a wrong `:modes` annotation and nothing catches it.

### Target shape
Pick one path:
- **Option A (preferred).** Remove `:modes` from tool specs (it's documentary-only). Add a load-time consistency check: every tool referenced in a mode spec exists in the registry.
- **Option B.** Keep `:modes`; make a build-time lint that asserts each tool's `:modes` matches the mode-spec `:tools` lists.

A is simpler and respects the "single source of truth" ethos. B preserves human-readable per-tool documentation.

### Migration sketch
1. **PR 1.** Grep every tool spec for `:modes`; confirm none are consulted at runtime (sub-agent or `rg -n ':modes'` in `satan/dl-satan-tools*.el` and broker).
2. **PR 2.** Delete `:modes` from tool specs. Add the consistency check helper.

### Considered and rejected
- **Make `:modes` authoritative and remove mode-spec `:tools` lists.** Backwards from the established mode-centred ethos.

---

## T8: Quick win — externalise pi adapter API-key list

**Impact:** Low.
**Effort:** S.
**Risk:** Low.

### Current shape
`dl-satan-patch-adapter-pi-api-key-vars` is a hardcoded 7-element list in elisp (`patch-adapter-pi.el`). The pi binary (built by Nix flake) must accept the same env var names; no shared spec governs this (`review/12-HARNESS-BOUNDARY.md` §items-from-one-side).

### Why it hurts
Adding a new provider (e.g. Together, Mistral, xAI) means: edit the elisp list, separately configure the pi binary. Silent drift if a provider is added on one side only.

### Target shape
Either:
- **Option A.** A shared JSON spec file (`satan/protocol/api-key-vars.json`) consumed by the elisp constant and (eventually) by the pi binary.
- **Option B.** Document the contract in `docs/satan/patch/adapter-pi.md` (a short README) and leave the list in elisp. Cheaper; relies on discipline.

### Migration sketch
Option A: 1 PR — create the JSON file, replace the elisp constant with a `(json-read-file …)` call at load.

### Considered and rejected
- **Externalise everything (model list, provider registry, etc.).** Scope creep; the API key list is the only place this drift matters.

---

## Anti-recommendations

Per architect brief §1.5, non-optional: patterns the scout flagged or that I considered, but which should be left alone.

1. **Don't merge the patch-agent's 8-file split.** Scout listed it as a hypothesis (review §H5). Verification (02-DEPENDENCIES + patch/brief.md §17) shows the split aligns with distinct responsibilities (adapter / store / worktree / runner / classifier / inbox / listener / prompt) each with separate phase plans. The split is load-bearing and reflects the patch-agent's role as a subordinate worker (patch/brief.md §2).
2. **Don't build a `dl-satan-memory-writer.el` facade.** Five `memory-store-mark` callers across three files (sub-agent C). Below the threshold where a facade pays for itself; call shapes are heterogeneous enough that a facade would either be a leaky abstraction or would force callers to construct the shape twice (once for the facade, once for the existing memory_mark contract).
3. **Don't consolidate the `defcustom` surface.** Scout 99-QUESTIONS Q12 flagged 30+ files with defcustoms; 05-COUPLING §defcustom showed no real grouping problem (max 8 per file, all per-module). The scattered shape is correct — `defcustom` lives with the module that consumes it.
4. **Don't make `tool-spec :modes` authoritative.** See T4 — would invert the established mode-centred ethos and force tool specs to carry the entire mode allowlist.
5. **Don't introduce a "perceptual layer" file directory.** 99-QUESTIONS Q1 hints at this. The current shape (percept/resonance/motive/sensor-alerts/observer/tank/context all in `satan/`) preserves a flat namespace per `docs/emacs/naming.md` and matches the rest of `satan/`. A subdirectory would create the only nested structure inside `satan/` and not pay for itself.
6. **Don't extend `actions.json` with attribute/intervention fields.** See T7 Considered-and-rejected. Per-run append-only files can't satisfy the cross-run query needs.
7. **Don't split tank.el.** 06-COHESION suggested this. Tank is `M-x my/satan-tank`'s buffer-rendering surface, well-contained, no growth pressure from attributes. The "audit-reading vs evidence-reading" dual concern is shallow — both feed the same buffer.

---

## What's well-factored (call out per brief §1.6)

- **Memory substrate** (`memory-grammar`, `memory-canon`, `memory-evidence`, `memory-store`, `memory-migrate`) — clean linear chain, purity-enforced (grep-lint), 8 dedicated test files, 119 ert. The reference pattern.
- **JSONL protocol** (`dl-satan-protocol.el` + `harness/protocol.py`) — shared fixtures, dual validators, 6 message types, no drift (12-HARNESS-BOUNDARY confirms exact match on fields, env vars, manifest shape).
- **Audit substrate** (`dl-satan-audit.el`, single writer, 6-predicate verifier). 291 LOC, focused.
- **Tool registry mechanism** (`dl-satan-tools.el`, 325 LOC) — clean dispatch, schema validator, JSON-Schema builder. The duality T4 addresses is a small wart on an otherwise solid module.
- **Patch-agent boundary** (`patch/brief.md` §1.2, §4) — explicit out-of-scope list; cannot mutate SATAN state. Strong contract.

---

## Open questions for the user (also surfaced in CODE_REVIEW.md §6)

- **Recommended sequence** (refined twice via GPT-5.5):

  ```
  T4 / T8 (quick wins, parallel to everything)
  → T1            (observer file-split, mechanical)
  → T1.5a         (outcome semantics design contract — doc only, no code)
  → narrow T2     (extract pre-spawn chain; ONE behaviour-neutral PR)
  → T7            (audit event types + projection + handler wiring + observer read-path)
  → [attributes core tranche]
  → T1.5b         (negative classifier implementation, depending on T7 substrate)
  → T3 path A     (narrow registry, byte-identical output, ONLY if the rendering pain is real)
  ```

  Rationale: T1.5a's semantics must be settled before T7 freezes audit event shapes ("storage follows the outcome model"); but T1.5b's implementation needs T7's substrate to exist. Narrow T2 should land before attributes because adding attribute-update into the current `broker--spawn` encodes lifecycle/error policy/audit timing into the old shape, which a later refactor must preserve.

- **`:harmful` classification policy.** T1.5a recommends *no automatic* `:harmful` in v1 — only user-marked or via a notes-side `@satan-harmful` directive. This is a deliberately conservative posture. Acceptable for v1, or push for an automatic-but-low-confidence path?

- **Retention of `transcript.jsonl` after T7 lands.** Audit log becomes source of truth for intervention outcomes; if old transcripts are rotated, the Postgres projection is the only record. v2 question or v1 blocker?

- **T2 abort condition.** T2 PR 1 is only worth merging if the extracted form makes data dependencies and tolerated failures clearer than today. If the audit (T2 PR 2) finds none and the result merely shortens code, defer until accretion forces the issue.

- **T3 abort condition.** Path A is only worth doing if PR 2's golden-file test confirms byte-identical output. If existing render-order surprises emerge, flip to Path B (skip the registry; live with the 11-file scatter through attributes).

- **T4 and T8** — independent quick wins, mergeable any time, no ordering constraint.
