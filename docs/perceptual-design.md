---
name: satan-perceptual-design
description: SATAN perceptual loop (v0) — percept capsule, auto-resonance, motive file, outcome observer, sensor alerts. Sits on top of the memory substrate.
metadata:
  type: design
  topic: satan
  status: phase-6-shipped
  updated_at: 2026-05-23
  verified_at: 2026-05-23
---

# SATAN — Perceptual Loop (Design, v0)

Companions:
- [[satan-architecture]] — broker / harness / model / tool / output / state layers
- [[satan-governance]] — file map, modes, tools, capability policy
- [[satan-memory-design]] — substrate (grammar, canonicalizer, evidence window, schema)

This document specifies the **perceptual layer that sits on top of the
existing memory substrate**. It does not redesign the substrate. Its
job is to make the present moment addressable, route prior recurrence
into context, and carry forward a small amount of motive across runs —
without prematurely committing to hypothesis machinery, confidence
math, or demotion ladders the system has not yet observed real failure
data for.

The design is the product of an adversarial review of the original
"SATAN Perceptual Model" reference note
(`notes/references/20260522T101032--satan-perceptual-model__…`)
against the actual state of `~/.emacs.d/satan/`. Many of the original
doc's concerns are already solved by the memory substrate; v0 fills
the remaining gaps with minimum machinery.

---

## 0. Reading order

1. §2 settled decisions — what v0 ships.
2. §3 deferred — what v0 deliberately does **not** ship and why.
3. §4 open — questions left for implementation-time discovery.
4. §5–§9 — architecture, file layout, build sequence, acceptance, evaluation.

---

## 1. Context: what already exists

The substrate is past minimum-viable.

| Component | Status | Location |
|---|---|---|
| Panopticon (sway + firefox capture, segmentizer) | shipped | `~/dev/panopticon`, state in `~/.local/state/behaviour/` |
| Bough CLI read surface | shipped | `dl-satan-tools-bough.el` |
| Evidence assembler (10-min window, deterministic truncation) | shipped | `dl-satan-memory-evidence.el` |
| Canonicalizer (pure, ~14 rules, grammar v1, closed-world enums) | shipped | `dl-satan-memory-canon.el` |
| `satan_memory` PostgreSQL store (traces, handles, links, grammar_version) | shipped | `dl-satan-memory-store.el` + `memory/migrations/` |
| `memory_mark` / `memory_resonate` / `memory_show_trace` tools | shipped | `dl-satan-tools-memory.el` |
| Tick / morning / motd timers, daily token ceiling, audit bundle | shipped | `dl-satan-tick.el`, `dl-satan-broker.el`, `dl-satan-budget.el`, `dl-satan-audit.el` |
| Recent-runs block in tick context | shipped | `dl-satan-context.el` |

What the substrate **does not** do today, and v0 will add:

1. Build a percept capsule from current evidence and inject it into the prompt.
2. Auto-resonate top-k prior traces and inject them as compact lines.
3. Carry a small motive file across runs, edited by both SATAN and user.
4. Observe basic outcomes of prior interventions, deterministically, no LLM.
5. Detect degraded sensors and notify loudly.

---

## 1.5 Implementation status (v0 shipped)

All seven v0 phases shipped 2026-05-22 → 2026-05-23. See `CHANGELOG.md`
and `git log --oneline -- satan/` for per-sub-phase commits and test
counts; this section is just the high-level map.

| Phase | Landed | Commits | Notes |
|---|---|---|---|
| 0 — broker prerequisites | 2026-05-22 | `d9aa1cf5d`, `ab4c3f300`, `ea80c483f`, `ac4ef283c` (0.1–0.4) | prepare phase + run_ctx + dispatch capability + pre_spawn schema + python mirror |
| 1 — percept skeleton | 2026-05-22 | `fded5338a`, `ed9a23c11`, `8b53d5159` (1.1–1.4) | builder + persist + render + golden tests |
| 2 — auto-resonance | 2026-05-22 | `0cef55039`, `470e3f791`, `8a6d4ee66` (2.1–2.4) | §S2 gate, broker call, render, fixtures |
| 3 — motive file | 2026-05-22 | `3df47f0c1`, `e1ef890be`, `b49d1b776`, `65962c882` (3.1–3.4) | parser, motive_read/motive_replace, broker call, motive_replace precedence + bound-naming contract |
| 4 — sensor alerts | 2026-05-22 | `80f357c88`, `f4f6e8847`, `a10c8b971`, `41b11e354` (4.1–4.4) | freshness, capsule block, dispatcher + cooldown + notify, pre_spawn integration |
| 5 — outcome observer | 2026-05-22 | `6422688d3` (5.1 evidence bounds), `9a02562ce` (5.0 `:project_cwd:`), `783d4b2e8` (5.2 skeleton + 24h scan), `1938943e2` (5.3 window-mature + dedup), `67e311e30`/`99fac686a`/`270e72ea2` (5.4a/b/c predicate + classifier), `2d8f36ccb` (5.5 footer rewriter), `3c422c911` (5.6 verdict persistence), `1f3f6398a` (5.7 multi-motive resolver), `a5f38ce2f` (5.8 broker integration) | observer.process now runs in `--spawn` before percept-build; positive-only `auto_rule` traces |
| 6 — cooldown floor | 2026-05-23 | `1a9c9c591` | read-side annotation in `dl-satan-motive-render-block`; cooling-down motives flip to `[cooling-down (Nm remaining)]` |
| fixes | 2026-05-23 | `7179e276a`, `547ef003b` | evidence `:truncated_at` JSON-serializable; jsonl coerces symbols |

What this means for the rest of the doc: §2 (settled decisions) S1–S7
all map to landed code; §5 (architecture) describes the broker flow
that now executes verbatim; §6 (file layout) lists files that exist;
§7 (build sequence) is the as-built order, in commit time-order; §8
(acceptance) criteria all have ert coverage (see CHANGELOG per-phase
totals). The doc body remains the design of record; this status block
exists so a future reader doesn't mistake design language for plan.

---

## 2. Settled decisions

### S1 — Percept capsule (broker-built, deterministic)

**Run-lifecycle slot — depends on Phase 0 broker refactor.**
Percept build happens in `dl-satan-broker--prepare`, a new function
introduced in Phase 0 (§7), which allocates `run_id` and freezes one
`time_now`. The same `time_now` and evidence-window snapshot back both
`bundle.json` and `percept.json` — they must derive from the same
frozen tuple or the run is invalid (acceptance criterion A7).

**Perceive / consume split (DE-010, landed 2026-06-10).** The tick is
cut into **perceive** (deterministic sensing) and **consume** (the
gated LLM run carrying all effects). Crucially, perceive runs
**unconditionally before the session/budget gates** — sensing no
longer depends on whether the system can afford to think (ISSUE-001
fixed at root; see [[ADR-001]]). Perceive's only write is the
perception-of-record (`percept.json`, mirrored as `:percept` in the
bundle even on budget-denied/blocked runs). All consumption-state
mutation (probe high-water marks, the per-source ingest cursor) and
all effects (interventions, tokens, DB outcome writes) are
consume-side. The attribute-charging probes are split read/commit: a
pure read-snapshot at perceive, the charge + watermark advance at
consume.

> **Signal model unchanged here.** DE-010 lands the structural cut
> only. Perception still reads present-tense live state
> (`current_window`, `git_state`, `fs_state`, bough) — it is **not yet
> replayable** from a watermark; that promotion is [[IMPR-013]].

Sequence (perceive/consume, as built):

```text
broker-run
  ↳ broker--prepare        → allocate run_id, freeze time_now, run_ctx plist
  ↳ mkdir run-dir
  ↳ PERCEIVE (unconditional, no LLM, no effects, no consumption-state mutation):
      ↳ percept.build(evidence, ctx)   → handles + handle_sources (canon)
      ↳ percept.persist(percept.json)  → perception-of-record (only perceive write)
      ↳ probe read-snapshot (curiosity/content/wpm) → native high-water, frozen onto prepare
      ↳ on error → no-child terminal close (shared --write-no-child-run), return
  ↳ if session-active  → write blocked bundle (MIRRORS :percept), return
  ↳ if budget-exceeded → write-denied bundle (MIRRORS :percept), return   ← ISSUE-001 fixed
  ↳ else CONSUME (effects + tokens):
      ↳ observer.process(run_ctx)          → outcome accrual, DB writes
      ↳ probe commit                       → charge + advance watermark to snapshot high-water
      ↳ memory.resonate(cue_handles)       → top 0–3 matches (per S2 gate)
      ↳ motive.read                        → motive_text
      ↳ sensor_alerts.check                → maybe dispatch notify (via S6 tool path)
      ↳ ingest-cursor.advance              → per-source frontier, success-only
      ↳ context-fn assembles bundle.json (capsule = perceive ∘ enrich)
      ↳ make-process (harness LLM)
```

The canonicalizer already emits the right shapes
(`surface:browser`, `surface_transition:terminal->browser`,
`domain_kind:docs`, `artifact:bough_status_change`, …). v0 reuses it
verbatim — no LLM in the path.

Capsule rendering shows only handles the canon actually emits. There
is no v0 rule that emits "no artifact in window"; absence-of-handle
means absence, and the capsule lists positive findings only.

```text
# Percept
project: emacs.d
surface: browser  (surface_transition:terminal->browser, focus_segments/3..4)
domain_kind: docs
```

No new substrate. No new grammar entries. The handles already exist;
they were previously emitted only into trace storage.

### S2 — Auto-resonance injected into capsule

The broker, after building the percept, calls `memory_resonate` with
the derived cue handles and injects the top **1–3** matches into the
prompt capsule.

**Resonance gate (anti-generic-recall).** When sensors are degraded
or evidence is sparse, the percept can reduce to handles that match
almost any prior moment and produce useless recall. The broker
requires **at least one sensor-observed handle** in the cue before
calling resonate. If the cue does not meet this bar, resonance is
skipped and the capsule omits the resonance block.

The gate excludes:

```text
ctx-derived handles            mode:*, day:*, week:*
cwd/git-derived project        project:*       (from git remote or cwd)
extension-derived file_kind    file_kind:*     (from cwd or recentf)
```

The gate admits anything in:

```text
panopticon-observed            app:*, surface:*,
                               surface_transition:*, domain_kind:*,
                               domain_transition:*
bough events / state           bough_event:*, bough_node:*,
                               bough_project:*, artifact:*
hint-side LLM-supplied         topic:*, phase:*, focal_app:*
```

Rationale: `project:emacs.d` is just-as-generic as `day:2026-05-22`
when the user always works in this repo. Until something the sensors
actually *saw happen* lands in the cue, resonance should stay silent.

Each surviving match renders as:

```text
rings  20260519T171522-a8f3  score 11.2
       matched: project:emacs.d, surface_transition:terminal->browser,
                domain_kind:docs
       "after terminal error in emacs.d, user moved to docs and produced no artifact"
```

The model retains explicit `memory_resonate` and `memory_show_trace`
calls for deeper lookup. v0 just removes the requirement that the
model *ask* for top-k recurrence on every tick.

This matches the explicit promise in
[[satan-memory-design]] §5.2: "Auto-injection of top-k matches into
tick-pulse system prompts is a v2 layer (it composes; the substrate
does not need to know)." v0 is that v2.

### S3 — Motive file (prose with light metadata footer)

A single, bounded, user-and-SATAN-editable prose file lives at:

```text
~/notes/satan/motives.org
```

Hard bounds, enforced broker-side on every write:

- ≤ 3 active motives
- ≤ 10 lines of "background ruminations"
- one archive file beside it for paper trail

Each motive section is free prose, terminated by a small machine-
readable footer:

```org
* test: docs-after-error
  Docs after terminal error often substitute orientation for contact.
  :cue: project:emacs.d surface_transition:terminal->browser domain_kind:docs
  :cooldown_s: 1800
  :worked_count: 0
  :last_intervention_at: 2026-05-21T14:02Z
```

Footer fields:

```text
:cue:                    REQUIRED for active motives. Space-separated
                         list of canonical handle strings. Each handle
                         must match the canon regex
                         ^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*$
                         (memory/design.md §2.5). At least one handle
                         must be sensor-observed (per the §S2 gate).
                         A motive without a valid :cue: is treated as
                         dormant — not rendered in the capsule, not
                         considered by the observer for correlation.

:cooldown_s:             author-set. Seconds between active fires.
:worked_count:           broker-maintained. Informational only.
:last_intervention_at:   broker-maintained. ISO 8601 UTC.
```

SATAN authors prose AND `:cue:` (it knows what cues to write when
proposing a motive). The broker maintains the lower three fields in
place. Single source of truth.

There is **no `:ceiling:` field in v0** — an intrusion ladder is
deferred (see §3). Cooldown alone is the noise floor.

Ruminations are even cheaper — date-stamped one-liners:

```org
* ruminations
  - 2026-05-22  docs-after-error often artifactless when project is emacs.d
  - 2026-05-19  patch jobs accepted more when directive cites file path
```

Auto-prune lines older than N days unless touched (N tuned at
implementation; start at 14).

Two new tools:

```text
motive_read()                      → whole file
motive_replace(content)            → atomic write, validated
```

Broker rejects `motive_replace` payloads that breach the bounds.

### S4 — Cooldown floor + positive reinforcement only

`:cooldown_s:` is fixed once set. `:worked_count:` counts up; nothing
counts down. v0 ships **no demotion ladder, no intrusion ceiling, no
geometric backoff, no re-promotion, no explicit dismiss tool**.

Two enforcement points:

1. **Cooldown floor (broker-side, pre-tick).** When the broker is
   about to render motives into the capsule, motives whose
   `(now - last_intervention_at) < cooldown_s` are marked
   `cooling-down` in the capsule rather than offered as actionable
   pressure. The model still sees them, but is told they are off-budget
   this tick. Last-intervention-at is updated whenever the observer
   correlates an intervention to a motive (§S5).

2. **`worked_count` is informational only.** It does **not** influence
   motive selection ordering, capsule placement, or any auto-promotion
   logic. The model sees it as one number in the motive footer and
   draws its own inferences. v0 explicitly does not feed back into
   substrate decisions.

Rationale: the elaborate demotion design rejected during conversation
was speculation built on made-up numbers (attribution windows,
backoff exponents, ceiling-step semantics). Pestering in v0 is
bounded by:

- daily token ceiling
- quiet hours
- per-motive `:cooldown_s:` floor (default 1800 s)
- 3-motive cap
- motive file is editable by hand in seconds

Run for a month; collect `:worked_count:` + observer-written
`auto_rule` observation traces; let real failure modes inform a v1
demotion / ceiling design.

### S5 — Outcome observer (light, deterministic)

A small broker module runs at the **start of each tick** (during
`dl-satan-broker--prepare`, before evidence assembly). It scans prior
runs' `transcript.jsonl` files for **interventions whose attribution
window has matured** (i.e. `intervention_emitted_at + 30 min <= time_now`),
classifies each as positive against a simple predicate, and:

- increments `:worked_count:` and updates `:last_intervention_at:` in
  the motive file footer when the intervention correlates to a motive
- writes an **`observation`-kind trace** with `trace_origin = auto_rule`
  into `satan_memory`, recording the intervention id, the correlated
  motive id, and the positive verdict

**Positive-only writes.** Interventions whose window has matured but
do not meet the positive predicate produce no trace and no counter
update. v0 deliberately does not record "ignored" or "inconclusive" —
absence of a positive trace is the only negative signal. (Acceptance
test A12 forbids spurious increments; A10 asserts a positive case
writes; there is no acceptance test asserting a negative-case write.)

**Window-mature gate.** An intervention is only classified when
`intervention_emitted_at + 30 min <= time_now` for the frozen
`time_now` of the current tick. Interventions whose 30-minute window
has not yet ended are left pending and re-checked on the next tick.
This prevents an early tick from scoring an intervention before its
window has actually passed (A11).

**Observer-owned attribution window.** The observer does **not** reuse
the next-tick's 10-min evidence window. It opens its own bounded
window per intervention: `[intervention_emitted_at,
intervention_emitted_at + 30 min]`, reading panopticon focus segments,
browser segments, git refs, and `bough_recent` directly from their
on-disk surfaces. Quiet-hours gaps and skipped ticks do not lose
evidence — the observer reads history, not live state.

**Intervention-time baseline + after-state diff.** The current evidence
substrate exposes most signals as *state*, not as *deltas*: focus
segments are derived later, `git_state` is HEAD + dirty flag (dirty
deferred; commit history moved to the 24h git-activity feed),
fs evidence is `recentf-list`. The P2 predicate (`:git_commit_observed`)
scans the `:git_commits` feed rows directly (window-anchored, no
baseline comparison needed). Other predicates compare two snapshots: one at
`intervention_emitted_at` (the baseline, read from the
`evidence_window` already stored in `bundle.json`'s percept evidence
or `metadata_json` of any memory trace recorded at that run) and one
at `intervention_emitted_at + 30 min` (the after-state, reconstructed
now from panopticon segments + git + fs mtimes). The positive
predicate fires on a delta, not on a state.

**No `motive_id` in protocol.** v0 does **not** add a `motive_id`
field to action schemas. The observer correlates by **handle overlap**
between the intervention-run's percept handles (read from
`percept.json`) and each motive's `:cue:` handles (parsed from the
motive footer, locked as a v0 requirement — see §S3). A motive without
a valid `:cue:` is dormant and never correlated. Per-intervention
dedup: increment at most once per intervention id (acceptance A13).

**Why `observation` not `outcome`.** Memory design §8.1 keeps the
outcome canon path dormant in v1: no canon rule emits `outcome:<value>`
and the `memory_mark` tool does not expose an `outcome` hint. Writing
an `outcome`-kind trace from the observer would either trip the
§9.12 invariant or require waking the dormant lane. The observer
writes `observation` traces with a free-form payload describing the
verdict. The schema reserves `outcome` for the future scorer.

v0 positive predicate (deliberately narrow):

```text
Let baseline   = snapshot at intervention_emitted_at  (from the
                 intervention-run's evidence_window in bundle.json)
Let after      = snapshot now (reconstructed by reading panopticon
                 segments + git refs + fs mtimes covering
                 [intervention_emitted_at, intervention_emitted_at + 30m])

positive = within the observer's per-intervention 30-min window
           AND any of:
             1. a focus_segment in `after` whose app surface is editor
                AND whose start_at > intervention_emitted_at
                AND whose buffer path resolves under the motive's
                project handle's cwd
             2. git HEAD short ref differs between baseline and after
                in the motive's project cwd
             3. an mtime delta exists on a file under the motive's
                project cwd, not present in baseline.recent_files
             4. a bough_event appears in after.bough_recent referencing
                the motive's bough_node/bough_project
```

Edits on paths unrelated to the motive's project cwd do **not** count
(acceptance A12).

### S6 — Sensor freshness, with loud failure

The evidence assembler computes a per-source freshness check and
drops stale sources from the evidence window before canonicalization.

Thresholds (start values; tune from observed cadence):

| Source | Threshold | Action when exceeded |
|---|---|---|
| `current/sway.json` | 5 min mtime | drop from `current_window` |
| `segments/focus-<day>.jsonl` (latest entry) | 30 min | drop tail |
| `segments/browser-<day>.jsonl` (latest entry) | 30 min | drop tail |
| `segments/git-<day>.jsonl` (commit feed) | none — bursty | never stale; in-window slice only |
| `bough` call | 5 s timeout | mark unreachable; rules emit nothing |
| `satan_memory` (psql) | error | log + notify; resonance disabled this run |

**Git is the odd sensor out.** focus/browser/current are *continuous*
streams where silence means the capture is broken (page-worthy). Commits
are *bursty*: a feed whose newest entry is days old just means no recent
commits — normal, not a fault. So the git probe inverts the freshness
contract: status is only `ok` / `missing` / `malformed`, **never
`stale-Nm`**, the slice is never age-dropped, and it carries **no alert
cause** (a quiet feed must not page). The feed is written by a global
`post-commit` hook (`satan/bin/satan-git-post-commit`) — pwd-independent,
so commits made anywhere (e.g. via Claude in a terminal) are captured,
not just those made from inside Emacs. Repos with an in-window commit
surface as `project:<slug>` handles (canon `vcs.recent_commit`, reusing
the open-world `project` namespace — no grammar bump). The model can then
drill into any repo's full history on demand via the `vcs_log` tool.

Sensor status returned alongside evidence:

```text
:sensor_status (:current_window ok :focus ok :browser ok :bough ok :git ok)
:sensor_status (:current_window stale-28m :focus ok :browser ok :bough unreachable :git ok)
```

Rendered into the capsule as one line:

```text
sensors: current=STALE(28m) focus=4m browser=4m bough=unreachable git=ok
```

**Loud failure on shouldn't-be-missing.** When a sensor degrades in a
way that suggests user intervention is required, the broker dispatches
a notification **through the existing `notify_send` tool handler**,
not through an ad-hoc D-Bus call. This routes the alert through the
normal capability check + audit pipeline. Causes that trigger:

- `current/sway.json` stale > 5 min during non-quiet hours (panopticon
  daemon likely dead)
- segmentizer hasn't run for ≥ 36 h
- bough unreachable on ≥ 3 consecutive ticks
- malformed JSON in any sensor file
- psql connection error to `satan_memory`

**Audit semantics — actions.json schema bump.** Today `actions.json`
is exactly `{applied, staged, rejected, failed}` and the audit
verifier (`dl-satan-audit.el`, ~line 159) requires those four
partitions to count-match `final.actions`. Sensor alerts fire
*before* the model has a turn — they are not a model action and must
not pollute the final-action partitions.

v0 adds a sibling key, `pre_spawn`, to `actions.json`:

```json
{
  "applied":   [...],
  "staged":    [...],
  "rejected":  [...],
  "failed":    [...],
  "pre_spawn": [
    { "kind":         "sensor_alert",
      "cause":        "panopticon_current_stale",
      "severity":     "warning",
      "message":      "panopticon current_window stale (28m).",
      "remediation":  "systemctl --user status panopticon-sway",
      "suppressed":   false,
      "dispatched_at": "2026-05-22T11:13Z" }
  ]
}
```

The audit verifier learns the `pre_spawn` key:

- it accepts entries with a `kind` field
- it does **not** count `pre_spawn` entries into the four model-action
  partitions (count invariant against `final.actions` remains intact)
- it requires that every alert observed in `~/.local/state/satan/notified.json`
  for this run is represented by either a `dispatched_at` entry or a
  `suppressed: true` entry, and vice-versa (acceptance A15)

**Suppression.** State for cooldown lives in
`~/.local/state/satan/notified.json`:

- per-cause `last_notified_at`
- per-cause cooldown (default 24 h)
- skip during `dl-satan-tick-quiet-p`; fire on first awake tick
  instead (suppression is recorded in `actions.json` either way, so
  the audit shows what was held back)

User preference: tune-out annoyance later beats long quiet-failure
bug hunts.

### S7 — Action-shape classification is already adequate

The original critique anticipated needing a meta-classifier for
"patch-shaped vs inline" actions. Inspection shows the existing tool
surface, capability system, and mode allowlist already encode shape:
the model picks a tool, the broker validates per-tool. No central
classifier exists or is needed.

Residual: model judgment between close neighbours (`proposal_stage`
vs `patch_job_create`, `inbox_append` vs `notify_send`). Address by
sharpening the "when to pick me over my neighbour" sentence in:

```text
~/notes/satan/tools/proposal_stage.md
~/notes/satan/tools/patch_job_create.md
~/notes/satan/tools/inbox_append.md
~/notes/satan/tools/notify_send.md
```

No new code, no schema, no enforcement. Revisit if observation shows
the model consistently picking wrong.

---

## 3. Deferred (not v0)

Each item below was considered and explicitly punted. None is forbidden;
each waits on real failure data the v0 run will produce.

| Deferred | Why deferred |
|---|---|
| Hypothesis substrate (predictions, confidence math, outcome scorer feedback into beliefs) | No falsifiable per-instance predictions yet. Observer writes `observation`-kind `auto_rule` traces — that data becomes the input for v1 hypothesis design. |
| Intrusion ceiling (`:ceiling:` field, `inbox`/`notify`/`visible_sign` ladder, per-channel demotion) | Premature ontology — no observed pestering yet. Cooldown floor alone is the v0 noise control. |
| Action `motive_id` citation in protocol | Would require protocol bump + validator + fixtures both sides. Observer correlates by handle overlap instead. Add when fuzzy correlation proves insufficient. |
| Demotion ladder + re-promotion + geometric backoff | All made-up numbers. Wait for observed pestering to inform tuning. |
| Explicit `satan_dismiss` tool + keystroke binding | Requires user workflow discipline; not justified before pestering observed. |
| Per-channel attribution windows (5m / 30m / 60m) | Speculative. Single observer-owned 30-min window per intervention suffices. |
| Partial-credit retrieval / handle hierarchies / sibling weights | Current weighted-overlap is good enough at v1 grammar volume. |
| `data_quality:*` handles in grammar | Capsule prose surfaces sensor state today; promote to handle if substrate proves to need it. |
| Outcome-kind traces from observer (`auto_rule` + `outcome:<value>` handle) | Memory design §8.1 keeps the outcome canon path dormant. Waking it is a v1 task bundled with a real scorer. |
| Token-degradation prompt-budget policy | No observed budget pressure on tick capsule (~150–300 tokens). |
| Visibly-wrong UX channel (predicted vs observed deltas) | Bundled with hypothesis substrate. |
| Mode → hypothesis-state coupling | n/a until hypotheses ship. |

---

## 4. Open questions

These don't block v0 implementation but should be resolved during it.

1. **`current_window` staleness threshold.** Start at 5 minutes; tune
   from observed sway focus cadence and false-positive notify rate.
2. **"Plausibly related" path predicate.** ✅ resolved (Phase 5.4).
   Observer scopes positive signal to file edits under the motive's
   `:project_cwd:` (option (a)). Predicate guard order
   `dormant → midnight → missing title` per §S5 / commit `270e72ea2`.
3. **Rumination prune horizon.** Start 14 days, revisit at first
   observed churn.
4. **Auto-resonance threshold.** Inject only matches with `score ≥ X`?
   Start with no threshold (subject to the §S2 non-ctx-handle gate);
   tune if noise observed.
5. **Capsule placement.** Does percept live inside `system` prompt
   (always-present) or inside a user-turn pre-amble? Lean system —
   the model treats it as oriented framing, not data.
6. **Baseline storage for the observer's diff.** ✅ resolved (Phase 5.4a,
   commit `67e311e30`). Observer reads baseline from the
   intervention-run's `bundle.json` `evidence_window` (option (a)); no
   new `baseline.json` write path was required.
7. **Handling of "always-on" motives whose cooldown is short.** With
   `:cooldown_s: 1800` and a tick every ~30 min, a motive that
   triggers every tick may never get a clean window-mature outcome
   before the next intervention. v0 punts: the dedup invariant
   (A13) prevents multi-counting, but the observer may attribute the
   first signal in the chain rather than the most recent. Acceptable
   noise for v0; revisit if it shows up.

---

## 5. Architecture

The new layer all lives inside `dl-satan-broker--prepare`, before
`bundle.json` freezes. The prepare phase **does not exist today** —
Phase 0 (§7) introduces it as the very first piece of v0 work. The
current broker (`dl-satan-broker.el` ~line 573) builds `bundle` before
any run-context object exists and `dl-satan-broker--tool-ctx` calls
`format-time-string` on demand (~line 222). Phase 0 replaces both
with a single `run_ctx` plist threaded through context-fn, tool
dispatch, and audit.

```text
existing tick run                       additions in v0 (after Phase 0)
==========================================================================
dl-satan-broker--prepare:                dl-satan-broker--prepare:
  (does not exist today; Phase 0)          allocate run_id + freeze time_now
                                           build run_ctx plist
                                           observer.scan_prior_interventions  ← S5
  (evidence assembled lazily today)        evidence.assemble + sensor_status  ← S6
                                           sensor_alerts.check                ← S6
                                             ↳ dispatches via notify_send tool
                                             ↳ records into actions.json.pre_spawn
                                           percept.build(evidence, ctx)       ← S1
                                           percept.persist  → percept.json    ← S1
                                           memory.resonate(cue_handles, gate) ← S2
                                           motive.read                        ← S3
  context.tick → bundle                    capsule includes:                  ← S1/S2/S3/S6
                                             percept block
                                             resonance block (gated)
                                             motive block (cooldown flags)
                                             sensor block
  harness LLM spawn                        (unchanged; uses run_ctx)
  output handler                           cooldown-floor update              ← S4
                                             ↳ writes last_intervention_at
                                               on observer correlation
  audit                                    audit verifier learns
                                             actions.json.pre_spawn key       ← S6
```

Data flow stays one-directional. The broker prepares; the model
chooses; the action gate validates; the observer scores positives at
the next tick's start. No live loop, no callbacks.

---

## 6. File layout additions

```text
~/.emacs.d/satan/
  dl-satan-percept.el           percept builder + persist + capsule render
  dl-satan-motive.el            motive file parse / write / footer state
  dl-satan-tools-motive.el      motive_read / motive_replace handlers
  dl-satan-observer.el          outcome observer (start-of-tick)
  dl-satan-sensor-alerts.el     freshness + notify dispatch
  test/dl-satan-percept-test.el
  test/dl-satan-motive-test.el
  test/dl-satan-observer-test.el
  test/dl-satan-sensor-alerts-test.el

~/notes/satan/
  motives.org                   user-editable motive file
  motives.archive.org           archived motives (append-only)
  tools/motive_read.md
  tools/motive_replace.md

state:
  ~/notes/satan/runs/<id>/percept.json
  ~/.local/state/satan/notified.json
```

No memory schema changes. No grammar bump. No new closed-world enum
values.

---

## 7. v0 build sequence

Phase 0 is a hard prerequisite — phases 1–6 all assume `run_ctx`
threading. Phases 1–4 within v0 are otherwise independent. Phases
5–6 read state written by phases 1–3.

All phases below shipped (see §1.5 for landing dates and commits).
The as-built sub-step numbering and the spec sub-step numbering
diverged slightly during implementation — when reading code, trust
commit subjects (`phase N.M: …`) over the numbering here.

```text
Phase 0 — broker prerequisites (NEW; ~100–150 lines)   ✅ 2026-05-22
  0.1  dl-satan-broker--prepare:
         allocate run_id, freeze time_now ONCE
         build run_ctx plist {run_id, time_now, evidence, percept,
                              sensor_status, pre_spawn, motive}
         thread run_ctx into context-fn, dl-satan-broker--tool-ctx,
         dl-satan-audit
         replace per-call format-time-string in tool-ctx
  0.2  notify capability guard:
         add :capabilities check in dl-satan-tools.el dispatch
         (existing modes already declare `notify` capability — the
         guard just starts enforcing it)
  0.3  actions.json schema bump:
         add `pre_spawn` key (array of {kind, ...} entries)
         dl-satan-audit verifier accepts pre_spawn entries
         pre_spawn does NOT count into the four model-action partitions
         fixture: a run with one pre_spawn sensor_alert and no model
                  final.actions still verifies clean
  0.4  python harness mirror:
         python audit/fixture validator learns the same `pre_spawn` key
         (parity with elisp; required by harness/protocol.py)

Phase 1 — percept skeleton                             ✅ 2026-05-22
  1.1  percept builder (reuses evidence + canon)
  1.2  persist percept.json
  1.3  render compact handles into capsule
  1.4  unit + golden tests

Phase 2 — auto-resonance                               ✅ 2026-05-22
  2.1  broker call to memory_resonate with derived cue
  2.2  apply §S2 gate (require ≥1 sensor-observed handle, excluding
       ctx, day, week, project-from-cwd, file_kind)
  2.3  inject top 1–3 into capsule when match count ≥ 1
  2.4  fixtures: gate-skip path, zero-matches path, psql-down path

Phase 3 — motive                                       ✅ 2026-05-22
  3.1  motives.org schema + footer parse (incl. required :cue:)
  3.2  motive_read + motive_replace tool handlers
  3.3  broker injects motive file into capsule
  3.4  motive_replace bound enforcement
       (3 motives, 10 ruminations, valid :cue: on every active motive)

Phase 4 — sensor alerts                                ✅ 2026-05-22
  4.1  freshness check in evidence assembler
  4.2  sensor_status plist returned
  4.3  capsule sensor line
  4.4  dl-satan-sensor-alerts:
         per-cause cooldown + quiet-hours suppression
         dispatch via notify_send tool handler
         record every fire AND every suppression in
         actions.json.pre_spawn

Phase 5 — outcome observer                             ✅ 2026-05-22
  5.1  start-of-tick scan over prior 24h transcripts
  5.2  window-mature gate: only classify interventions with
       intervention_emitted_at + 30m <= time_now
  5.3  observer-owned 30-min window per intervention (reads panopticon
       segments + git refs + fs mtimes directly; does not reuse
       next-tick evidence)
  5.4  intervention-time baseline read from the intervention-run's
       bundle.json evidence_window; after-state reconstructed now
  5.5  positive-signal predicate as in §S5 (delta vs baseline,
       project-cwd scoped)
  5.6  motive correlation by handle overlap:
       intervention-run's percept handles ∩ motive's :cue: handles
       (motives without valid :cue: are dormant — never correlated)
  5.7  worked_count increment + last_intervention_at update + motive
       footer rewrite
  5.8  observation-kind auto_rule trace write (positive only)
  5.9  per-intervention id dedup (max one increment per intervention)

Phase 6 — cooldown floor enforcement                   ✅ 2026-05-23
  6.1  broker pre-capsule check: motives in cooldown rendered as
       `cooling-down (Nm remaining)`
  6.2  test: cooldown-not-elapsed → motive marked cooling-down in capsule
  6.3  test: cooldown-elapsed → motive rendered as actionable
```

Phase 0 unblocks every other phase. After it lands, phases 1–4 are
independent short PRs with tests. Phases 5–6 follow.

No `:ceiling:` enforcement in v0 (the field does not exist in the
footer). No action-gate motive consultation beyond the broker's
pre-capsule cooldown flag.

---

## 8. Acceptance criteria

A v0 implementation is acceptable when each of the following has a
corresponding test (unit or fixture).

### Phase 0 prerequisites

A0a. `dl-satan-broker--prepare` exists and is the single allocator
     of `run_id` + `time_now`. No other code path mints either.
A0b. A `run_ctx` plist is threaded into context-fn, tool dispatch,
     and audit. `dl-satan-broker--tool-ctx` no longer calls
     `format-time-string`; it reads `time_now` from `run_ctx`.
A0c. Tool dispatch enforces `:capabilities` declared on a mode.
     A test removes the `notify` capability from a mode and asserts
     that `notify_send` is rejected by the dispatcher (not by the
     handler) with a structured error.
A0d. `actions.json` accepts an optional `pre_spawn` key whose
     entries each carry a `kind` field. The audit verifier accepts
     unknown `kind` values gracefully (rejects malformed structure,
     not unknown discriminants). Count invariants against
     `final.actions` continue to ignore `pre_spawn`.
A0e. Python harness audit/fixture validator (`harness/protocol.py`)
     mirrors A0d. Both validators round-trip the canonical fixture
     bundle.

### Determinism & freezing

A1. Every run writes a deterministic `percept.json` next to `bundle.json`.
A2. `bundle.json`, `percept.json`, and any resonance entries in the
    capsule all carry the same `run_id` and `time_now`. A test
    asserts identity, not just equality.
A3. Re-running the same tick over the same inputs (frozen sensor files,
    frozen `time_now`) produces byte-identical `percept.json` and an
    equivalent capsule modulo non-canonical key ordering.

### Capsule shape

A4. The capsule contains a percept block, sensor block, and motive
    block (possibly empty). A resonance block appears **iff** all of:
    (i) the §S2 gate passes,
    (ii) memory is reachable (no psql error this run),
    (iii) `memory_resonate` returned at least one match.
    If any condition fails, the resonance block is **omitted entirely**
    (no "no matches" line, no empty header). Fixtures cover each
    failing condition.
A5. Gate exclusion is comprehensive. Cues containing **only** any
    subset of `mode:*`, `day:*`, `week:*`, `project:*` (when
    derived from cwd/git via `cwd.project`), or `file_kind:*` (when
    derived via `cwd.file_kind`) do **not** trigger resonance.
    The gate passes only when at least one handle is sensor-observed
    via panopticon (`app`, `surface`, `surface_transition`, `domain_kind`,
    `domain_transition`), bough event/state, `artifact:*`, or a
    hint-supplied `topic`/`phase`/`focal_app`.
A6. The percept block lists only handles the canonicalizer actually
    emitted. There is no rendering of absence (no `artifact: none`,
    no `surface: unknown`).

### Motive file

A7. `motive_replace` rejects payloads breaching `≤ 3 motives` or
    `≤ 10 rumination lines`, with a structured error message naming
    the breached bound.
A8. The motive footer parser accepts `:cooldown_s:`, `:worked_count:`,
    `:last_intervention_at:`, and `:cue:`. `:cue:` is required on
    every active motive — a motive without one is treated as dormant
    (not rendered in the actionable section of the capsule, not
    considered by the observer for correlation, but tolerated in
    the file so the author can stage work). The parser rejects
    `:ceiling:` (not a v0 field) with a structured error.
A9. `:worked_count:` is rendered into the capsule but does **not**
    appear in motive selection or ordering logic. A test asserts
    that two motives differing only in `:worked_count:` produce the
    same capsule ordering.

### Observer

A10. The observer increments `:worked_count:` and writes an
     `observation`-kind `auto_rule` trace **only when its positive
     predicate fires**. Inconclusive/negative cases produce **no**
     trace and **no** counter update. A test asserts that an
     intervention with a fully-elapsed window and no positive signal
     leaves the substrate untouched.
A11. **Window-mature gate.** The observer classifies an intervention
     only when `intervention_emitted_at + 30 min <= time_now` for
     the current tick's frozen `time_now`. A test fires a tick at
     `intervention_emitted_at + 20 min` and asserts the intervention
     remains pending (no trace, no counter change), then fires a
     later tick at `intervention_emitted_at + 35 min` and asserts
     classification happens then. A second test feeds a long
     quiet-hours gap and confirms that an intervention whose window
     elapsed during the gap is correctly attributed on the next
     awake tick.
A12. **No coincidence increment.** A file edit in the observer's
     window on a path *not* under any motive's project cwd does
     **not** increment any `:worked_count:`. The predicate compares
     an intervention-time baseline against the after-state; pure
     state matches without a delta do not count.
A13. **Dedup.** Re-running the observer against the same prior
     transcript does not double-count a previously-correlated
     intervention. The dedup state is durable (survives broker
     restarts).
A14. Motives without a valid `:cue:` are skipped entirely by the
     observer. A fixture with a dormant (no-cue) motive next to an
     active one asserts only the active one receives correlation.

### Sensor alerts

A15. Sensor degradation triggers at most one notify dispatch per
     cause per 24 h, suppressed during quiet hours.
A16. **Every** alert dispatch — fired or suppressed — appears in
     the run's `actions.json` under the `pre_spawn` key as
     `{kind: "sensor_alert", cause, severity, message, remediation,
       suppressed?, dispatched_at?}`. The audit verifier requires
     a one-to-one correspondence between entries in
     `~/.local/state/satan/notified.json` updated this run and
     entries in `actions.json.pre_spawn`.
A17. Sensor-alert dispatch routes through the same `notify_send`
     tool handler used by model-side calls — same dispatch path,
     same capability check (per A0c), same formatting. A test
     removes the `notify` capability from the synthetic pre-spawn
     mode and asserts that sensor alerts are recorded as
     `suppressed: true` with `reason: "capability_denied"`, not
     dispatched.

### Purity

A18. No LLM is invoked in the percept, resonance-injection, observer,
     cooldown-floor, or sensor-alert paths.

---

## 9. What this design satisfies and what it deliberately doesn't

Maps against the goal list from the original reference note.

| Goal | Satisfied by v0? | How |
|---|---|---|
| Locally informed | yes | Percept built fresh each tick from sensors. |
| Token-thrifty | yes | Handles + 1–3 resonances + small motive file = ~150–300 tokens of overhead. Raw data stays out. |
| Motivated across time | partial | Motive file persists; `:worked_count:` carries reinforcement. No falsifiable predictions yet. |
| Hypothesis-bearing | no | Deferred. `auto_rule` observation traces collect the data v1 will need. |
| Visibly wrong sometimes | partial | `:worked_count:` exposes ineffective motives. No prediction surface, so no formal "I was wrong by X". |
| Useful without becoming managerial | yes | Same action gate, same modes, same proposals-first governance. |
| Intrusive without becoming noisy | yes (bounded) | 3-motive cap, fixed cooldown floor, quiet hours, daily token ceiling. No clever demotion, but four independent floors. |

The substrate already gives the design most of what the perceptual-
model note wanted. v0 wires the remaining last-mile pieces with the
minimum machinery that lets a month of real running produce data for
v1's harder decisions.

---

## When implementation conflicts with this document

Same rule as governance: either restore the invariant in code, or
deliberately revise this document and explain why. Do not let
implementation drift become design.
