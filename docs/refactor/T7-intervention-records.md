---
name: satan-refactor-T7
description: First-class intervention records — audit events + Postgres projection. BLOCKER for attributes.
metadata:
  type: refactor-theme
  topic: satan-refactor
  status: merged
  blocked_by: []
  updated_at: 2026-05-23
---

# Theme T7 — First-class intervention records (BLOCKER for attributes)

**Impact:** High. **Effort:** L. **Risk:** M. **Reversibility:** Medium.

## Current shape

No first-class intervention record exists. The five user-facing tool handlers (`inbox_append`, `notify_send`, `proposal_stage`, `patch_job_create`, `sway_border_set`) write nothing beyond what the broker captures centrally in `actions.json` (raw action plists, no `expected_outcome` / `outcome_window_minutes` / `friction_level`). Observer reads "interventions" by filtering `actions.json` after the fact (`observer.el:144` + `observer.el:791`).

attributes.brief §3.1 mandates an intervention record at action-time with the full metadata schema (§5 SQL). attributes.brief §3.2 mandates outcome classification (`worked|neutral|ignored|contradicted|harmful|unknown`). Today's actions.json shape carries none of those.

## Why it hurts

Without intervention records, Shame is ungrounded; negative outcomes can't be observed deterministically. attributes.brief §3.4 counter-memory ("SATAN suspected X, but the user produced Y") requires links the current shape can't carry. **Blocking for attributes.**

## Target shape (per GPT-5.5: append-only audit events as source of truth, Postgres as rebuildable projection)

- Audit gains three event kinds, written to `transcript.jsonl` at the appropriate phase:
  - `intervention.created` — handler-side, at tool-call time. Carries stable id + full metadata.
  - `intervention.outcome_classified` — observer-side, when maturity gate fires.
  - `intervention.outcome_revised` — corner case where a later run updates a prior classification.
- `memory/migrations/0006_interventions.sql` — `satan_interventions` + `satan_intervention_outcomes` tables. **Projection only**, rebuildable from the audit events (a rebuild CLI mirrors `dl-satan-memory-renormalize`).
- `dl-satan-intervention.el` — write API (emits audit event + inserts projection row in one transaction) and read API.
- Each of the 5 handlers writes through this single API; intervention-id surfaces in `tool_result`.
- Observer's `applied-interventions-in-run` deletes; the read path moves to SQL against the projection.

The memory-substrate's Postgres-as-source-of-truth precedent (for traces) is **not** invoked. Per GPT-5.5: memory joins are an internal retrieval optimization; intervention/outcome records are governance-relevant behavioural history and warrant the audit-first shape.

## Migration sketch

Five small PRs:
1. Audit event types + validator + protocol-doc update.
2. Migration `0006_interventions.sql` + rebuild CLI.
3. Write API (`dl-satan-intervention.el`) + first handler wired through.
4. Remaining 4 handlers wired through.
5. Observer read-path swap (delete `applied-interventions-in-run`; SQL against projection).

## Design points the migration must answer (NOT optional)

- **Projection rebuild contract.** The rebuild CLI must be deterministic + idempotent: rebuilding the projection from a fixture audit log twice yields identical rows. Drift between projection and audit log must be detectable (an ert that diff-checks projection rows against a reconstructed-from-audit view). Without a tested rebuild path, "rebuildable projection" is just a claim.
- **Event identity + idempotency.** `intervention.created` and `intervention.outcome_classified` need stable IDs (recommend `format-time-string "%Y%m%dT%H%M%S" + run-id + 6-hex-random`, matching run-id convention). Replaying an audit log must not produce duplicate projection rows. Handler-side write API is responsible for ensuring the (audit-emit + projection-insert) pair is one transaction; on crash, both either land or both roll back.
- **Sentinel / post-tool failure policy.** Today's `actions.json` is only finalised at audit-close. The intervention write happens at tool-call time. Question: if the handler's intervention write succeeds but the broker's subsequent audit-record (`broker.el:400`) fails, what is canonical? Recommendation: the handler-emitted `intervention.created` audit event is the ground truth; the `:action-applied` audit record (which links by `intervention_id`) is the cross-reference. They are two events, separately validated, separately re-readable on rebuild.
- **Outcome revision semantics.** `intervention.outcome_revised` exists for the corner case where a later run updates a prior classification (e.g. `ignored → worked` after a delayed artifact). Whether revisions are allowed at all is a T1.5a decision; if allowed, the projection's `satan_intervention_outcomes` carries the latest by `observed_at` while the audit log keeps every revision.

## Considered and rejected

- Postgres-as-source-of-truth with audit "secondary" (earlier draft) — governance regression; dual-writer drift.
- Pure flat-file (one JSONL stream or one directory per intervention) — viable but loses SQL query convenience for the maturity-window lookup.
- Extend `actions.json` — per-run, append-only; no cross-run query; no rebuild story.
- Stuff intervention rows into `satan_memory.traces` — different lifecycle.

## First concrete step

PR that adds the three audit event types to the validator + fixtures + `docs/satan/protocol.md`. No callers yet. The T1.5a design contract must already exist (or be drafted as part of the same review cycle) so the audit event shape encodes the right vocabulary.

## Open questions

- ~~Should rebuild-from-audit run on every migration, or only on operator demand?~~ **Resolved (PR 2): operator-demand only.** Migration `0006_interventions.sql` only creates the tables; population is via `my/satan-rebuild-interventions` / `satan/bin/satan-rebuild-interventions`. Matches `dl-satan-memory-renormalize` precedent.
- ~~Intervention-id exposure to the model in `tool_result` — yes/no?~~ **Resolved (PR 3): id-only (no live verdict).** `notify_send`'s `tool_result` carries `:intervention_id` alongside the existing `:id`. The contract recommends v2 add an `intervention_status` tool for explicit lookups; PR 3 stops at id exposure to keep the model from optimising for the metric (per outcome-semantics §11.1).
- Audit-log retention policy once Postgres projection is the only durable record.

## PR log

- [x] PR 1: audit event types + validator + fixtures + protocol.md — merged 2026-05-23
- [x] PR 2: migration `0006_interventions.sql` + rebuild CLI — merged 2026-05-23
- [x] PR 3: write API + first handler (`notify_send`) — merged 2026-05-23
- [x] PR 4: remaining 4 handlers wired through — merged 2026-05-23
- [x] PR 5: observer read-path swap — merged 2026-05-23
  - Delete `dl-satan-observer--applied-interventions-in-run`,
    `dl-satan-observer-scan-prior-interventions`,
    `dl-satan-observer-mark-classified`, the
    `dl-satan-observer-state-file` dedup path, and the supporting
    `--read-state`/`--write-state`/`--classified-p`/`--key-of`/`--mature-p`/
    `--in-scan-window-p`/`--run-id-from-dir`/`--run-started-at` helpers.
  - `dl-satan-observer-pending` becomes a thin wrapper over
    `dl-satan-intervention-pending`, mapping projection rows to the plist
    shape the classifier already consumes (`:run_id`, `:run_dir` resolved
    under the runs root, `:intervention_emitted_at` from `:ts`,
    `:applied_index` derived from the `<run-id>.ivNNN` counter so existing
    metadata callers keep working).
  - `dl-satan-observer-persist-verdict` drops `mark-classified` and instead
    calls `dl-satan-intervention-classify` with the
    `outcome-semantics §2` payload (`:classification`, `:confidence`,
    `:evidence`, `:maturity "mature"`, `:next_revisit_at`, `:source "auto"`,
    `:classified_at`).  Translation table for PR 5 (T1.5b widens this):
    - `verdict "positive"` → classification `"worked"`, confidence
      `"medium"` (single predicate; ≥2-predicate `"high"` lands in T1.5b
      with the verdict-shape extension), evidence carries `:predicates`
      `:motive_id` `:handle_overlap`.
    - `verdict "none"` (any reason / no fire) → classification
      `"unknown"`, confidence `"low"`, evidence carries `:reason`.
  - Broker (`dl-satan-broker--spawn`) opens the audit handle *before*
    `observer-process` so the observer can emit
    `intervention.outcome_classified` / `outcome_revised` into the
    current run's transcript.  `dl-satan-audit-open` now permits a `nil`
    bundle (deferred) and a new `dl-satan-audit-attach-bundle` writes
    `bundle.json` once the context-fn has produced it.
  - Observer test: drops the file-walk / scan-window / state-file ert
    that exercise the deleted helpers; new DB-touching ert mirror
    `dl-satan-intervention-test--with-db` (skip-unless reachable +
    reset-and-migrate) and assert pending + classify writes through the
    projection.  Reset-list prepends `satan_intervention_outcomes,
    satan_interventions`.
  - **A3 determinism boundary:** observer's
    `intervention.outcome_classified` events now appear in transcript
    timestamps + carry intervention ids minted from the prior runs, so
    two byte-identical reruns of `--spawn` may diverge.  No current
    transcript-level golden test asserts byte-identical broker reruns;
    the percept-level A3 ert (`dl-satan-percept-test`) is unaffected.
    Boundary noted at the module header of `dl-satan-observer.el` and in
    the CHANGELOG line for PR 5.
