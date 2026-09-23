# goad as SATAN's elicitation surface

## Context

goad (`~/dev/goad`) is a standalone Rust/Slint "programmable personal
intervention shell": a GUI host that renders whatever a user-owned backend tells
it to, and carries the answer back. Its governing invariant is *the host
understands interaction, not intent* — the backend owns all domain meaning and
persistence. It runs today as a systemd user unit against
`~/satan/goad/backend.py` (a 14-item daily checklist), committed to the corpus
repo at `eeb4f3c`.

SATAN has no way to ask the keeper anything. Every SATAN→human surface in the
tree is fire-and-forget push — `notify_send` (D-Bus, no `:actions` callback),
`inbox_append`, `proposal_stage`, sway borders, the owned daily org block. The
inverse direction exists (`@satan` directives, `@satan-intervention-harmful`)
but the human always originates. **Nothing poses a question and receives a
structured answer.**

This matters because of [[RFC-016]], which diagnoses SATAN's dormancy as an
attention-economy failure rather than an ops one: the behaviour layer has been
dead since 2026-05-31, and the organism has *"no sense organ for being
ignored"*. Its D3 keystone is "disengagement becomes perceptible and
consequential".

goad supplies exactly that organ. `Later`, `Enough`, and an unanswered window
are refusal semantics the protocol already carries. And the seat is pre-built:
`"ask"` is a **reserved but unemitted** member of the closed intervention-kind
set in all three registries — `satan-memory-grammar.el:72`, `satan-audit.el:233`,
`satan-observer-classify.el:258` — with a 60-minute outcome window documented at
`docs/attributes/outcome-semantics.md:109`. Because `"ask"` is already in
`satan-observer-user-facing-kinds`, an unanswered prompt classifies as
`:ignored` with no new classifier work.

A goad answer would also be SATAN's **first direct human-sourced outcome
signal**. The observer's four positive predicates today are all ambient
telemetry (editor focus, a git commit, a `recentf` entry).

## Scope & Objectives

Three capabilities, in dependency order. Each is independently useful.

```
            ~/satan/goad/                        ~/dev/satan/satan/
  ┌──────────────────────────────┐
  │  data/YYYY-MM-DD.json        │ ──(1) PERCEIVE──►  percept / sensor
  │    answers + deferrals       │                    (pure; perceive phase)
  ├──────────────────────────────┤
  │  <queue>/    SATAN-authored  │ ◄─(2) PROMPT────   ask tool
  │  <answers>/  keeper's reply  │ ──────────────►    (effects; consume phase)
  ├──────────────────────────────┤
  │  backend.py  merges both     │
  └──────────────────────────────┘
            ▲ evaluate/respond
       ┌────┴─────┐
       │ goad host│ ◄────(3) DOORBELL──────────────   goad-emit shell-out
       └──────────┘   /run/user/1000/goad.sock        (refusal-aware)
```

**1. PERCEIVE.** SATAN reads `~/satan/goad/data/*.json` ([[DEC-009]]) as a
percept/sensor source — per-item `value` (a boolean for checklist items, the
chosen option and its field values for SATAN's asks — [[DEC-025]]) and
`deferred_at`. Read-only; no goad change;
no governance surface. Lands in the **perceive** phase, which [[ADR-001]] /
DE-010 require to be pure (its only write is `percept.json`).

**2. PROMPT.** SATAN-authored questions rendered by goad. A file-drop queue
under `~/satan/goad/`, which `backend.py` merges into `pending()` alongside its
hardcoded `ITEMS`; answers are written back for SATAN to read. Keeping the queue
backend-side satisfies goad's own architectural review question #1 ("could this
behaviour live entirely in the backend?") and therefore needs **no goad host
change**. Emitting the prompt is an effect → **consume** phase, recorded as an
intervention of the reserved kind `"ask"`. A question may carry its own answer
form — options, each with goad's field kinds — rather than Yes / No only
([[DEC-024]]); the form is persisted on the intervention record and validated by
SATAN at emit ([[DEC-026]]).

**3. DOORBELL.** SATAN chooses the moment via
`goad-emit --source satan --kind K --data JSON`. `source: "host"` is reserved
(goad SPEC-003/R-13); `data` is opaque and reaches the backend whole (R-11).

## Non-Goals

- **Approval gating — deliberately excluded.** goad elicits; it never blocks a
  SATAN enactment on a human yes. [[ADR-017]] §1 assigns human-approval flows to
  the Emacs client *permanently*, and the authority ledger has all seven rows at
  `emacs-client` with nothing migrated. This slice holds **no authority item**
  and adds **no ledger row**; goad is a data-plane surface. Making goad an
  approval gate would require an ADR amendment, not a slice decision.
- **SATAN rewriting `backend.py` via satan-patcher** — the follow-up below.
- **Any change to the goad host** (`~/dev/goad`). If the design finds a host
  change unavoidable, that is a signal to re-examine the design, not to widen
  scope: goad is separately governed with its own ADRs and specs.
- **Reviving the `:staged` action path.** `satan-broker.el:239` logs
  `action-staged` and discards the plist — a real dead hole under
  `:auto-apply 'none`, but it is the approval story, not the elicitation one.
- Reporting or analytics over `data/` (goad's own field notes defer this too).
- Retiring the checklist's four-button shape, or the `ITEMS`-as-code list.

## Affected surface

SATAN (`~/dev/satan`) — the mechanism repo:

- a new sensor/percept reader for the goad day files
- a new thin tool module for the doorbell and the ask queue
- `satan-context.el` (bundle assembly), if the goad state joins the capsule
- intervention emission at the reserved kind `"ask"`, carrying an optional
  answer form (`:form`, a `form_json` column, the audit validator)
- `satan-custom.el` — `satan-state-root` treats an empty `XDG_STATE_HOME` as
  unset, through one helper shared with the curiosity and content readers
  ([[DEC-027]])
- `satan-intervention.el` — rows read as JSON, not split on `|`, and an
  open-asks query for the queue ([[DEC-028]])

Corpus (`~/satan`) — separate repo, separate patch job if ever automated:

- `goad/backend.py` — merge the SATAN queue into `pending()`
- `goad/` — queue and answer directories, tool descriptions

## Risks, assumptions, open questions

- **R1 — Timestamp format trap.** goad stamps local-offset microsecond ISO
  (`2026-09-21T09:38:45.346563+10:00`). Per
  [[mem.pattern.satan.sensor-watermark-format]], a sensor cloned from the
  curiosity/content family that advances a watermark by lexical `string<` MUST
  store the source's own max timestamp verbatim — comparing `…+10:00` against a
  formatted `…Z` is garbage, and it fails silently (re-fires, or never advances).
- **R2 — Blast radius of the backend.** `backend.py` has no tests, no fixtures
  and no check recipe. goad degrades safely on a backend fault (the host does
  not crash) but prompts stop, and goad's own field notes already record that
  *"waiting and dead look the same"*. Any change to `backend.py` wants fixtures
  first.
- **R3 — Ingress is lossy by design.** goad SPEC-003/R-12: an envelope arriving
  mid-exchange or inside the minimum spacing is **refused** with a structured
  reason (`too_soon`, `engaged`, `retry_after_ms`) and is never queued, delayed
  or coalesced. The doorbell is therefore a *hint*, not a delivery mechanism; the
  queue file is the durable carrier and a refused emit must be harmless.
- **A1 — POL-001 seat.** The SATAN-side code is assumed to earn its seat as a
  *thin shell*, the same rationale POL-001 already grants
  `satan-tools-{notify,sway,activity,agenda}.el`. To be confirmed at design.
- **A2 — data/ is corpus, not state.** `data/*.toml` is tracked at `eeb4f3c`,
  so daily answers are versioned. This is a defensible read of the three-roots
  model (cf. the hippocampus, SL-015 D3) but it churns the corpus repo daily.
- **OQ-1** — Does the goad state join the percept capsule every tick, or is it
  pulled on demand by a tool? Capsule inclusion costs tokens on every run.
- **OQ-2** — One queue file or a file per question? Concurrency between SATAN
  writing and `backend.py` reading is the deciding constraint.
- **OQ-3** — Where does the keeper's answer land on the SATAN side: straight to
  an intervention outcome, a memory trace, the inbox, or all three?
- **OQ-4** — Does answering a SATAN `"ask"` also close the observer loop
  directly, or only via the existing `:ignored`/`:neutral` classification? If
  outcomes are ever marked from goad, they MUST route through
  `satan-intervention-write-manual-outcome` with a **new `marked-by` value** —
  not a reimplementation (the closed set is `satan-intervention--manual-marked-by`).
- **D1 — ISS-012 gates the autonomous producer.** `motd` and `morning` runs fail
  at turn 0 on an expired API key; only `tick-pulse` and interactive runs
  complete. SATAN-initiated prompts need a working unattended run.

## Deliberate non-duplication

Named so the design can decide against them explicitly rather than drift:

- **`satan-tools-inbox.el`** — the existing "SATAN put something in front of
  you" surface. If this slice builds question *presentation*, the inbox is the
  incumbent and a second one is a parallel implementation. It has no reply leg,
  so the *answering* half is genuinely new.
- **`satan-intervention-mark.el`** — same shape (pick an item, give reason /
  confidence / evidence), opposite direction and human-initiated. Reuse its
  writer; do not clone it.
- **`satan-tank.el`** — the existing read-only Emacs GUI. If the elicitation
  surface ever wants ambient presence in Emacs, the tank is the natural host.

## Verification intent

Done is judged by a closed loop, observed end to end:

1. SATAN emits an intervention of kind `"ask"`; the question reaches the goad
   window without a goad host change.
2. The keeper answers; the answer is readable by SATAN and attributable to the
   originating intervention — whatever form SATAN gave the question.
3. An *unanswered* prompt matures and classifies as `:ignored` through the
   existing observer path — the [[RFC-016]] D3 keystone, demonstrated.
4. A refused `goad-emit` (`too_soon` / `engaged`) loses nothing: the queued
   question is still asked at the next slot.
5. Sensor watermark advance is covered by a test that seeds a **source-format**
   (local-offset) watermark and asserts it advances (R1).

## Summary

Make goad SATAN's elicitation surface — read the keeper's answers as perception,
pose SATAN's own questions through the existing backend, and ring the doorbell
when the moment matters. Elicit only: no authority item, no ledger row,
[[ADR-017]]'s Emacs carve-out untouched. Fills the reserved-but-empty `"ask"`
seat and closes [[RFC-016]]'s D3 keystone.

## Follow-Ups

- **[[IMP-020]] — SATAN rewrites `backend.py` via satan-patcher.** The hard blocker is
  cleared (`goad/` committed at `eeb4f3c`, so `git diff --name-only base...HEAD`
  can see it). Two prerequisites remain: `backend.py` needs fixtures so a patch
  job's `checks` are non-empty, and the job must target the **corpus** repo with
  repo-relative `allowed_paths` — mechanism and corpus are separate repos and
  need separate jobs ([[mem.fact.satan.patch-job-contract]]).
- Reporting over `data/` once there is enough of it.
- The `:staged` action hole (`satan-broker.el:239`) — approval-side, unrelated
  to this slice but adjacent to any future goad approval story.
