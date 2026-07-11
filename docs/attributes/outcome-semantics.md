---
name: attributes-outcome-semantics
description: Design contract — outcome classification vocabulary, lifecycle, evidence, and revision rules for the SATAN attribute layer
metadata:
  type: design-contract
  topic: attributes
  status: merged
  feeds: [T7, T1.5b]
  authority: blocking
  updated_at: 2026-05-23
---

# Outcome semantics — design contract (T1.5a)

> **Status.** This is the **contract**, not the implementation. T7 (intervention records) encodes this vocabulary into the audit event schema. T1.5b implements the classifier extensions in `satan-observer-classify.el`. Where this document conflicts with code at any point, this document wins — file an issue or amend the contract first.

This document defines what an *outcome verdict* is, when it is allowed to transition between states, what evidence each kind of classification requires, and what v1 deliberately refuses to infer.

It exists because attribute Shame deltas (`attributes.brief` §3.3) are mechanically driven by negative-outcome classifications. A noisy classifier produces a noisy Shame signal which biases every downstream attribute that caps on Shame (Cruelty, Doubt). The boundary between "classifier got it wrong" and "system mis-shamed itself" must be drawn before code lands, not discovered in production.

Companion docs:

- [`../attributes.brief.md`](../attributes.brief.md) — attribute layer brief; this contract refines §3.2 (outcome observation) and §3.3 (Shame deltas).
- [`../perceptual-design.md`](../perceptual-design.md) §S5 — today's positive-only outcome observer, which T1.5b extends.
- [`../refactor/T7-intervention-records.md`](../refactor/T7-intervention-records.md) — the audit-event substrate that carries these verdicts.
- [`../refactor/T1.5-outcome-semantics.md`](../refactor/T1.5-outcome-semantics.md) — the theme brief.

---

## 1. Vocabulary

An outcome verdict carries exactly one *classification* from this closed set:

| Classification | Meaning |
|---|---|
| `:worked`       | Expected artifact / contact occurred inside the attribution window. |
| `:neutral`      | Attribution window matured; intervention was non-user-facing (e.g. `sway_border_set`); no positive nor negative evidence. |
| `:ignored`      | User-facing intervention (`inbox`, `notify`, `proposal`, `visible_sign`) matured; no positive predicate fired; no user-acknowledgement event in window. |
| `:contradicted` | SATAN suspected drift/avoidance; user produced useful artifact from the suspected activity. **Manual-only in v1.** |
| `:harmful`      | Intervention interrupted active progress, created churn, or repeated a known-bad pattern. **Manual-only in v1.** |
| `:unknown`      | Maturity not yet elapsed; or evidence gathering failed (e.g. window crosses midnight); the verdict is not authoritative and may be revised. |

The string forms used in audit events / projection rows match `attributes.brief` §5 SQL: `worked`, `neutral`, `ignored`, `contradicted`, `harmful`, `unknown`. Elisp keywords are used inside `observer-classify.el`; SQL strings cross the audit boundary. Mapping is name-equality without the colon.

`:worked` is the only classification today's positive classifier already emits (`satan-observer-classify` returns `:verdict "positive"`). T1.5b folds that emission into this new verdict shape.

---

## 2. Verdict shape

The classifier returns a plist with exactly these slots. All slots are required unless marked optional.

```elisp
(:intervention-id "20260523T120000-morning-deadbe.iv03"   ; T7 stable id
 :classification  :worked|:neutral|:ignored|:contradicted|:harmful|:unknown
 :confidence      :low|:medium|:high                       ; see §4
 :evidence        PLIST                                    ; see §5; machine-readable
 :maturity        :pending|:mature|:stale                  ; see §3
 :next-revisit-at "2026-05-23T12:30:00+1000"               ; ISO8601; see §6
 :source          :auto|:manual                            ; see §7
 :classified-at   "2026-05-23T12:30:01+1000"               ; ISO8601; broker :time_now
 :revises         "20260523T100000-morning-cafeba.iv01"    ; optional — id of prior
                                                          ;   verdict this revises;
                                                          ;   absent on first emit
 :notes           "free-form")                             ; optional; manual-mark only
```

**Invariants.**

1. `:classification :harmful` ⇒ `:source :manual`. The classifier API rejects an auto-emitted `:harmful` at compile-time (a `cl-check-type` or equivalent guard).
2. `:classification :contradicted` ⇒ `:source :manual` in v1. Future versions may relax this once `expected_outcome` counterfactual evidence is collectible; the contract change is a v2 amendment.
3. `:maturity :pending` ⇒ `:classification :unknown`. A pending verdict cannot assert a substantive classification.
4. `:maturity :stale` ⇒ no further auto-emits permitted; manual revisions still allowed.
5. `:revises` is set ⇔ this verdict supersedes a prior one (see §6 revision policy). The prior verdict is identified by its own `:intervention-id` + emit timestamp; T7 audit events keep the full chain.

Verdicts are addressed by `(intervention-id, classified-at)` in audit events. The projection row `satan_intervention_outcomes` (per `attributes.brief` §5) holds the latest by `:classified-at`; the audit log retains every emit.

---

## 3. Lifecycle

A verdict moves through three maturity states keyed off the intervention's `created_at` (set at `intervention.created` audit-event emit time, T7) and its `outcome_window_minutes` (declared at create-time; defaults to 30 per today's `satan-observer-window-mature-seconds`).

```text
                                    +--- :stale cutoff -----+
                                    |  (mature + 24h)       |
   created_at        +outcome_window_minutes      …          eternity
        |------------|---------------|---------------------->
        ^            ^               ^
   :pending      :mature         :stale
```

| State | Window | Auto-classifier behaviour | Manual-mark behaviour |
|---|---|---|---|
| `:pending`  | `[created_at, created_at + outcome_window_minutes)`  | Always emits `(:classification :unknown :maturity :pending)`; does not consult predicates. | Allowed; emits with `:source :manual` and the supplied classification (rules below). |
| `:mature`   | `[created_at + outcome_window_minutes, +24 h)`        | Runs predicates; emits one of `:worked`/`:neutral`/`:ignored`/`:unknown`. May be revised by a later auto-pass while still `:mature` (e.g. late `:worked` evidence trumps an earlier `:ignored`). | Allowed; may revise the auto verdict. |
| `:stale`    | `[mature + 24 h, ∞)`                                  | No further auto-emits; the last `:mature`-era verdict freezes in the projection. | Allowed; emits with `:revises` referencing the frozen verdict. |

**Why a finite `:stale` cutoff.** Two reasons: (i) late evidence beyond 24 h has weak causal claim on Shame; (ii) the observer's per-tick cost is bounded by the maturity-eligible set, and without a cutoff that set grows unboundedly.

**Why 24 h.** Matches `satan-observer-scan-window-hours` (today's prior-run scan window) — re-using the same horizon means a single tick's scan covers everything still mutable, and a missed-tick day does not prematurely freeze the projection.

The intervention's `outcome_window_minutes` is **declared at create-time by the handler**, not inferred. T7's `intervention.created` audit event carries the value; the observer reads it. The handler picks a value appropriate to the intervention kind:

| Intervention kind | Recommended `outcome_window_minutes` (handler default) |
|---|---|
| `notify`, `inbox`, `visible_sign`     | 30 (today's default) |
| `proposal`, `patch_job`               | 120 (proposals need triage time) |
| `accuse`, `ask`, `delay`              | 60 |
| `quarantine`, `surface`               | 240 (action may sit for hours) |

These are recommendations, not enforced; the handler may override per call.

---

## 4. Confidence vocabulary

A finite three-level enum: `:low | :medium | :high`. Matches the `small | medium | high` delta vocabulary in `attributes.brief` §3.3, so the Shame-delta table can be a direct lookup.

| Level | Audit-event string | Trigger conditions (v1) |
|---|---|---|
| `:high`   | `"high"`   | Two or more positive predicates fire (S5 P1–P4); or a manual mark by interactive command with an explicit `:confidence :high`. |
| `:medium` | `"medium"` | Exactly one positive predicate fires; or a manual mark via interactive command (default); or `:ignored` with a clear absence-of-acknowledgement signal (no read-receipt audit event in window for `notify`/`inbox`). |
| `:low`    | `"low"`    | `:neutral` and `:unknown` always emit at `:low`; manual marks from the `@satan-intervention-harmful` notes directive default to `:low` unless the directive carries `(conf: high)`. |

**Rejected: float confidence on `[0,1]`.** A continuous score implies a calibration story the codebase does not yet have. The enum admits exact equality checks in tests, deterministic Shame-delta selection, and is trivially auditable.

**Confidence does not gate emission.** A `:low` verdict still lands in the audit log and projection. Confidence is consumed by the §3.3 Shame-delta lookup *and* by the `attribute-control-loop-damping` policy (`CODE_REVIEW.md` anti-recommendation §5 #9): high-confidence verdicts may produce a high Shame delta; low-confidence verdicts cap at the corresponding `small` delta even when the classification is `:contradicted`.

---

## 5. Evidence per classification

The `:evidence` slot holds a plist whose shape varies by classification. Every shape carries `:source-events` — a list of audit-event `(run_id, seq)` references the classifier consulted — so an auditor can reconstruct the verdict from the audit log alone.

```elisp
;; Common to every verdict
(:source-events ((:run_id "20260523T120000-morning-deadbe" :seq 14)
                 ...))
```

### `:worked`

```elisp
(:source-events (...)
 :predicates    (:editor_edit_in_window :git_commit_observed ...)   ; which S5 P1–P4 fired
 :motive-id     "morning.kanban-cleanup"
 :handle-overlap 3)                                              ; |motive.cue ∩ percept.handles|
```

Today's `satan-observer-classify` already produces the `:predicates` payload (as a single `:predicate` keyword); T1.5b extends it to a list to allow `:confidence :high` via multi-predicate firings.

### `:ignored`

```elisp
(:source-events (...)
 :target-surface "inbox" | "notify" | "proposal" | "visible_sign"
 :no-positive-predicates t      ; every S5 P1–P4 returned nil
 :acknowledgement-checked t     ; observer scanned for a user-ack event in window
 :ack-events-found 0)
```

The acknowledgement scan is the new evidence class introduced by T1.5b. The substrate is panopticon-derived focus-segment events on the target surface (e.g. for `notify`: a focus segment on the relevant Sway window starts after the intervention emit ts).

### `:neutral`

```elisp
(:source-events (...)
 :target-surface "sway_border_set" | other non-user-facing kind
 :no-positive-predicates t)
```

`:neutral` does not check acknowledgement — the intervention had no user-facing surface to be acknowledged on. This is what distinguishes `:neutral` from `:ignored`.

### `:contradicted` (v1: manual-only)

```elisp
(:source-events (...)
 :prior-suspicion "drift-on-X" | "avoidance-of-Y" | free-form
 :user-artifact "/notes/projects/X/decisions.org L42"
 :counter-memory-trace-id "trace_…"   ; optional; the counter-memory trace T1.5b's writer adds
 :marked-by :interactive-command | :notes-directive)
```

The classifier API **must** reject auto-emission of `:contradicted` even with `:source :manual` absent. The justification: detecting contradiction requires the intervention to have carried an `expected_outcome` counterfactual *and* the observer to have evidence both that the user did the suspected behaviour *and* that an artifact emerged. T7's `intervention.created` schema carries `expected_outcome` but v1 has no canonical place to capture the user's free-text rebuttal. Reserving `:contradicted` for manual marks defers that capture story to v2.

### `:harmful` (v1: manual-only)

```elisp
(:source-events (...)
 :reason "interrupted-focus" | "churn" | "repeated-known-bad" | free-form
 :marked-by :interactive-command | :notes-directive
 :evidence-pointer "/notes/projects/X/notes.org L88")
```

`:harmful` requires causal reasoning the codebase does not have. See `attributes.brief` §3.2: *"Do not infer `harmful` casually. Start conservative."* The architecture-level reason (`CODE_REVIEW.md` anti-recommendation §5 #8): false-positive Shame on `:harmful` is worse than missing-Shame, because Shame caps Cruelty (the friction lever) — a false `:harmful` permanently depresses the system's willingness to intervene where the user actually wanted intervention.

### `:unknown`

```elisp
(:source-events (...)
 :reason :crosses_midnight | :no_baseline | :no_correlation | :motive_dormant | :pending)
```

The `:reason` keywords mirror today's `satan-observer-classify` `:reason` slot. A `:pending`-maturity verdict always reports `:reason :pending`.

---

## 6. Clock, window, and revision policy

### 6.1 Clock

All maturity transitions use the broker's `:time_now`, **frozen at `satan-broker--prepare`**. Acceptance A3 (byte-identical-rerun) requires this; computing maturity from `(current-time)` would defeat A3 every tick.

Per `CODE_REVIEW.md` §6 Q7, T7 and T1.5b are the two themes allowed to break A3 byte-identical-rerun (new IDs, new classifier outputs). T1.5b breaks it because the verdict shape is wider; T7 breaks it because intervention IDs include a random suffix.

### 6.2 Window

The maturity window opens at `intervention.created_at` (per the `intervention.created` audit event T7 emits) and closes at `created_at + outcome_window_minutes`. `:next-revisit-at` is exactly the window-close timestamp.

The observer's `:stale` cutoff is `created_at + outcome_window_minutes + (24 h)`. After `:stale`, the auto-classifier ignores the intervention; the projection row carries the last `:mature`-era verdict.

### 6.3 Revision policy

| Trigger | While `:mature` | While `:stale` |
|---|---|---|
| Auto re-pass produces a *different* classification with ≥ existing `:confidence` | Emit `outcome_revised` event; new verdict supersedes; `:revises` references the prior. | Forbidden — observer skips `:stale` interventions. |
| Auto re-pass produces a *different* classification with lower `:confidence`     | Drop (no revision; the higher-confidence prior wins). | Forbidden. |
| Manual mark by interactive command                                              | Allowed; emits `outcome_revised`; `:source :manual`. | Allowed; `:revises` references the frozen verdict. |
| Manual mark via notes directive                                                 | Allowed; routed through the same writer; `:source :manual`. | Allowed. |
| Late evidence arrives after `:stale` cutoff                                      | (Impossible — `:stale` is later than `:mature`.) | Dropped. Re-classify only by manual mark. |

**Why ≥ confidence for auto revisions.** An equal-confidence revision flip is permitted because it represents *new* evidence in the same maturity window (e.g. a `:worked` predicate fires on the second tick after an `:ignored` on the first); a strictly-lower-confidence revision is dropped to prevent classifier noise from churning Shame.

The audit log carries **every** revision. The projection row reflects the latest by `:classified-at`. A rebuild from audit log replays revisions in `:classified-at` order; this is part of T7's projection rebuild contract.

---

## 7. Manual marking — workflow contract

Manual marks are the only legal route to `:harmful` and (in v1) `:contradicted`. Two surfaces; one writer.

### 7.1 Interactive command

```text
M-x satan-intervention-mark-harmful
M-x satan-intervention-mark-contradicted
```

(T1.5b PR 4 ships these.) The command prompts for:

1. **Intervention id** (completing-read over recent interventions, newest first; filter by maturity-not-`:stale` by default with a prefix-arg to show `:stale`).
2. **Reason** (single-line; freeform).
3. **Evidence pointer** (optional; an org or notes file path + line; defaults to current buffer + line).
4. **Confidence** (`:low`/`:medium`/`:high`; defaults to `:medium`).
5. **Notes** (optional multiline).

The command writes a single `intervention.outcome_classified` (or `outcome_revised` if a prior verdict exists) audit event with `:source :manual :marked-by :interactive-command`. The projection row updates atomically.

### 7.2 Notes directive

A `@satan-intervention-harmful` directive in a notes file:

```org
* DONE Refactor X
  CLOSED: [2026-05-24 Sat 09:00]
  @satan-intervention-harmful: iv_id=20260523T1200-morning-deadbe.iv03 reason="interrupted flow" conf=high
  The proposal arrived mid-debug and broke my train of thought.
```

The tick-agent's `notes_at_satan_scan` tool finds these (the existing `@satan-*` scanner); a new `notes_at_satan_intervention_done` handler (mirroring `notes_at_satan_done`) routes through the same writer as the interactive command. `:source :manual :marked-by :notes-directive`. Once consumed, the scanner rewrites the directive to include the run-id stamp (mirroring `satan-tools-atsatan--rewrite-line`).

Directive grammar:

```text
@satan-intervention-{harmful|contradicted}: iv_id=<intervention-id> reason="<freeform>" [conf=low|medium|high] [evidence=<path>:<line>]
```

`conf=` defaults to `:low` (per §4 — directives default low because they carry no proof of the writer's calibration; an explicit `conf=high` is a stronger claim).

### 7.3 Evidence pointer storage

The `:evidence-pointer` slot is a freeform string — typically `path:line` or `path:line-line`. The projection stores it as text in `satan_intervention_outcomes.notes` JSON; it is *not* indexed for query. Resolving the pointer (opening the file at the line) is the consumer's job; the contract does not promise the pointer remains valid after file edits.

### 7.4 Revising manual marks

Every revision emits a new `intervention.outcome_revised` event with `:revises` filled in. The projection row reflects the latest. The audit log holds the full chain so an auditor can reconstruct who marked what when.

A manual mark **does not** prevent later auto-revisions while the verdict is still `:mature`. Rationale: manual marks happen at human speed and may lag behind late evidence in the window; the user can re-mark if the auto-revision is wrong. After `:stale`, manual marks are the only path.

---

## 8. What v1 deliberately does not infer

This is the contract's negative space. Items here are **out of scope** for T1.5b and any code change between this contract landing and the v2 contract amendment.

| Item | Why deferred |
|---|---|
| Causal harm (`:harmful` auto-detection)                  | Needs counterfactual reasoning the codebase does not have; false-positive Shame is worse than missing Shame. |
| Contradiction without explicit counterfactual evidence  | `expected_outcome` is captured at intervention create; *user's rebuttal artifact* has no canonical capture surface today. |
| Fine-grained `:ignored` vs `:pending` discrimination beyond the maturity window | Acknowledgement evidence is panopticon-derived focus segments; v1 treats absence-of-segment in window as `:ignored` without distinguishing "user saw and dismissed" from "user never noticed". |
| Cross-intervention amplification (multiple `:ignored` ⇒ stronger `:contradicted` later) | Adds a temporal model the v1 classifier does not have; `attributes.brief` §6 explicitly asks for small deltas and caps before formulas. |
| Confidence as continuous float                          | Calibration story missing; enum suffices. |
| Per-attribute decay (anti-recommendation §5 #9 (a))     | Belongs to the attribute layer's update loop, not the outcome classifier. Outcome semantics emits verdicts; decay is downstream. |

Each item is a **deliberate** refusal; if a future need argues for inferring one of these, amend this contract before writing code.

---

## 9. Implications for T7 (audit event shapes)

T7 must encode this vocabulary. The three audit event kinds T7 introduces carry these payloads:

### `intervention.created`

Emitted by the handler at tool-call time. Carries the full intervention metadata (`attributes.brief` §3.1) plus the new outcome-relevant fields:

```elisp
(:event "intervention.created"
 :payload (:intervention_id "20260523T120000-morning-deadbe.iv03"
           :run_id           "20260523T120000-morning-deadbe"
           :ts               "2026-05-23T12:00:00+1000"
           :mode             "morning"
           :kind             "notify" | "inbox" | "proposal" | …
           :target_surface   "sway-mainbar" | "/notes/inbox.org" | …
           :message          "…"
           :related_motive_id "morning.kanban-cleanup"
           :related_trace_ids ("trace_…")
           :cue_handles       ("bough_node:abc" "bough_project:def")
           :expected_outcome  "user opens kanban.org and updates DONE column"  ; freeform
           :outcome_window_minutes 30
           :severity          "low" | "medium" | "high"))
```

### `intervention.outcome_classified`

Emitted by the observer (auto) or the manual-mark writer. Carries the §2 verdict shape verbatim, with classification + confidence as strings (no leading colon) at the audit boundary:

```elisp
(:event "intervention.outcome_classified"
 :payload (:intervention_id "…"
           :classification   "worked" | "neutral" | "ignored" | "contradicted" | "harmful" | "unknown"
           :confidence       "low" | "medium" | "high"
           :evidence         <plist; classification-specific shape per §5>
           :maturity         "pending" | "mature" | "stale"
           :next_revisit_at  "2026-05-23T12:30:00+1000"
           :source           "auto" | "manual"
           :classified_at    "2026-05-23T12:30:01+1000"
           :marked_by        "interactive-command" | "notes-directive" | nil
           :notes            "…" | nil))
```

### `intervention.outcome_revised`

Same payload as `outcome_classified` plus `:revises`. The revised event is a full re-emit; the projection reads the new event and updates the `satan_intervention_outcomes` row.

```elisp
(:event "intervention.outcome_revised"
 :payload (… all outcome_classified slots …
           :revises "<intervention-id-of-prior-verdict-or-revision>"))
```

T7's validator must reject:

- `intervention.outcome_classified` / `outcome_revised` with `classification = "harmful"` and `source = "auto"`.
- `intervention.outcome_classified` / `outcome_revised` with `classification = "contradicted"` and `source = "auto"` (v1 only; relax in v2 amendment).
- Any event referencing an `intervention_id` whose `intervention.created` was not previously seen in the audit log (validator's idempotency / replay safety).

The projection migration (`memory/migrations/0006_interventions.sql` per T7) holds:

- `satan_interventions` — one row per `intervention.created`. Immutable.
- `satan_intervention_outcomes` — one row per `intervention_id`, reflecting the latest `outcome_classified` / `outcome_revised`. Updated atomically with the audit-event write (single transaction).

A rebuild from audit-log replays `created` → `outcome_classified` → `outcome_revised`* in `ts` order and reconstructs both tables byte-identically.

---

## 10. Implications for T1.5b (classifier extensions)

T1.5b lands four PRs in `satan-observer-classify.el` (already extracted by T1 — see [`../refactor/T1-observer-split.md`](../refactor/T1-observer-split.md)):

1. **Verdict shape extension.** Replace today's `(:verdict "positive" :predicate :kw)` with the §2 plist. Today's positive classifier becomes `:classification :worked :confidence (:medium when one predicate fires, :high when ≥2)`. The `:unknown` reasons map straight from today's `:reason :crosses_midnight`/`:no_baseline`/`:no_correlation`/`:motive_dormant`.
2. **Negative predicates.** Add `classify-negative` returning `:ignored` (user-facing intervention, no positive predicate, no ack event in window) or `:neutral` (non-user-facing intervention, no positive predicate). `:contradicted` and `:harmful` are rejected at the API boundary.
3. **Lifecycle coordinator.** `satan-observer--maturity-state intervention now` returns `:pending|:mature|:stale`. The classifier dispatches: `:pending` → emit `(:classification :unknown :maturity :pending)`; `:mature` → run predicates; `:stale` → no-op.
4. **Manual override path.** Interactive commands `satan-intervention-mark-{harmful,contradicted}`; notes-side `notes_at_satan_intervention_done` handler consuming `@satan-intervention-{harmful,contradicted}` directives. Both route through `satan-intervention-write-manual-outcome` (the single writer).

PR order respects T7 dependencies: PRs 1–3 land after T7 (need audit-event substrate); PR 4 may land same-cycle or shortly after.

---

## 11. Open questions

Decisions intentionally left for T7 / T1.5b implementation, not the contract:

1. **`intervention_id` exposure to the model in `tool_result`.** The contract specifies the id schema but does not mandate visibility. Recommendation (carried from `CODE_REVIEW.md` §6 Q8): id-only in v1 — the handler returns the id; the model can call a future `intervention_status` tool to fetch the current outcome. Letting the model see the live `:classification` in-band invites it to optimise for the metric.
2. ~~**Notes-directive consumption ordering.** A directive sat in a notes file may be consumed before or after the auto-classifier has emitted a `:mature` verdict for the same intervention. T1.5b PR 4 must pick a rule: latest-write-wins (simplest); or notes-directive-trumps-auto (richer evidence wins). Recommendation: latest-write-wins by `:classified-at`, with the directive's `ts` being the file mtime at scan time.~~ **Resolved (T1.5b PR 4, 2026-05-23):** latest-write-wins by `:classified-at`. The directive's `:classified-at` is the consuming tick's `:time-now` (no special handling required — `intervention-classify` already orders by that field).
3. ~~**Counter-memory writer.** `attributes.brief` §3.4 mandates a counter-memory trace on `:contradicted` / `:harmful`. T1.5b PR 4 must wire it through `satan-memory-store-mark` with `:trace-origin :auto_rule :kind "observation"`. Whether to ship counter-memory in PR 4 or a follow-up PR is an implementation call.~~ **Resolved (T1.5b PR 4, 2026-05-23):** shipped in PR 4. `satan-intervention--write-counter-memory` invokes `satan-memory-store-mark` with `:trace-origin "auto_rule" :kind "observation" :source "intervention.manual_mark" :valence "negative"`; trace `:handles` inherit the intervention's `:cue_handles` verbatim (with `:rule_id "intervention.manual_mark" :origin "derived"` provenance) so resonance can surface the counter-memory when the same cue re-fires. The dedicated `outcome:*` handle-values amendment to the memory grammar is deferred to the attribute-layer build, not a one-off PR.

These do not block T7. T7 may proceed with the §9 event shapes as fixed.

---

## 12. Change history

| Date | Change | Author / source |
|---|---|---|
| 2026-05-23 | Initial contract — drafted from `CODE_REVIEW.md` T1.5 + `attributes.brief` §3 + `perceptual-design.md` §S5. | T1.5a PR. |
| 2026-05-23 | §11 Q#2 (notes-vs-auto ordering) + Q#3 (counter-memory writer) struck through with resolution notes — both shipped in T1.5b PR 4. Q#1 (id exposure) remains open. | T1.5b PR 4 follow-ups. |
