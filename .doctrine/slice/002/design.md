# Design SL-002: Remove bough integration

<!-- Reference forms (.doctrine/glossary.md § reference forms): entity ids padded
     (SL-001, ISS-001); doc-local refs bare — D1 (§7), R1 (§8), OQ-1 (§6),
     RN-1 (§10). SL-001's abandoned design.md is the authoritative seam map;
     §2 here inherits and *extends* it — a removal touches surfaces the flag
     never had to. §10 carries the codex inquisition + adjudication. -->

## 1. Design Problem

Bough is dormant (no use since ~2026-05) and its return is uncertain. SL-001
designed a feature flag to make it *absent-when-disabled*; the four-round
inquisition there produced a complete, verified seam map, and in doing so made
the flag's cost plain — two-view tool filtering plus per-run/session freeze
state, all to preserve ~1,000 lines nobody exercises. Decision (YAGNI): remove
the integration instead. SL-001 is abandoned; its `design.md` §2/§10 is retained
as the authoritative seam map for this removal and any future resurrection.

This design is **not** "delete the files the slice lists." The prior analysis
scoped a *flag*, which only had to gate the **model-facing behavioural** seams
(tool exposure, evidence calls, sensor signal). A **removal** must also reckon
with surfaces a flag could leave inert. The load-bearing distinction that
governs the whole shape is **bough-specific derivation/matching vs
content-agnostic substrate**:

- **Bough-specific machinery** — the live data-path that *derives* bough signal
  from a running bough (the tool, the evidence probes/fields/status, the canon
  rules that turn bough evidence into memory handles, the `focal_bough_nanoid`
  hint→handle derivation) or *matches/signals* on it (the `:bough_event_match`
  observer predicate, the `:bough` sensor synthesis, alerts, tank render), plus
  the caller inputs that feed them. **Removed.**
- **Content-agnostic substrate** — machinery that merely *can carry* bough
  values but is not about bough: the persisted grammar (a DB-synced,
  version-gated closed-world schema, in both elisp and SQL), the motive
  admitted-namespace vocabulary, the generic memory retrieval/show/recent path,
  and the generic handle-*propagation* paths (observer positive-persistence,
  intervention counter-memory) that copy a trace/motive/intervention's existing
  handles verbatim into new records. **Preserved.**

The consequence — the honest boundary, corrected across two inquisition rounds
(§10) — is precise and narrower than "bough disappears":

> After removal, **no bough handle is ever *derived* again** (evidence,
> canon rules, and the hint→handle path are gone) and **no bough signal is
> matched or surfaced** (predicate, sensor, alerts, tank gone). What the
> preserved substrate still permits — an intentional consequence of keeping the
> grammar vocabulary admitted (D1/D4), *not* a leak — are three residual
> mechanisms for a **legal bough literal** (RN-11): (1) **read** — historical
> bough-attributed records stay queryable; (2) **copy-forward** — a bough handle
> already in a persisted trace/motive/intervention, **or in a per-run percept
> artifact (`percept.json` / its `bundle.json` mirror), from which a bough-only
> motive still correlates (RN-13)**, is copied verbatim into new records by
> content-agnostic writers (observer persistence, intervention counter-memory,
> attribute outcome forwarding); (3) **fresh introduction** — a
> caller or config may still write a *new* `bough_*` literal through any generic
> handle-accepting API (`motive_replace`, `memory_resonate` cue.handles →
> audit, pattern sync, `intervention-create`, the raw `memory-store-mark`),
> because the vocabulary validates it. None of these is bough-specific code. The
> residual vocabulary **and** any residual handles across **every** store are
> retired completely by a grammar-v2 + data migration (OQ-3) — a separate slice,
> not part of removing an integration.

Two questions decide correctness and neither is settled by the slice scope:
(1) **where is that boundary drawn**, precisely, at every surface, *including
the propagation paths* (D1); and (2) **is the slice's inventory complete and
correct** — verification says no on both counts (§2, D2).

Target end-state: no live bough data-path, no bough derivation/matching/signal,
no dead code referencing a removed shape, no `bough_read` tool, no `:bough`
sensor, no bough alerts, no bough tool inputs — while the persisted grammar
(elisp + SQL), the motive vocabulary, historical data, and the content-agnostic
propagation machinery stay intact and honestly documented, dormant, awaiting the
OQ-3 retirement. Resurrection: git history (pre-removal SHA in close notes) +
the SL-001 ledger. No scaffolding, no stubs, no flag.

## 2. Current State — the seam map

Verified against the tree 2026-07-18 (grep + read + codex rounds 1–2). Three
partitions, treated differently.

### 2.A Bough-specific machinery (REMOVE)

The live path bough data is *derived* along, everything that *matches/signals*
on it, and every caller input that feeds derivation.

- **Tool module** — `satan/satan-tools-bough.el` (whole file, 108 refs):
  `satan-tool/bough-read` and its top-level `(satan-tool-register "bough_read")`.
- **Load edges** — `satan/satan-memory.el:15` `(require 'satan-tools-bough)`
  plus its module docstring line 5.
- **Mode allowlists** — `"bough_read"` in 5 static specs
  (`satan/satan-mode.el:98,124,148,171,193`) and the two `satan-tick-register`
  default sets, `tick-pulse` and `tick-agent` (`satan/satan-tick.el:58-119`) —
  seven registrations total (SL-001 RN-3).
- **Evidence assembly** (`satan/satan-memory-evidence.el`, 70 refs): the three
  bough reads (`--bough-recent`/`--bough-active`/`--bough-day`) and their
  `--bough-call` helper; `--bough-status` and the `:bough` sensor_status
  synthesis; the `:bough_recent`/`:bough_active`/`:bough_day` evidence fields;
  the `satan-memory-evidence-bough-limit` defcustom **and its caller option**
  `:bough_limit` (`:22` doc, read `:653`); the `:bough_workspace` opt (doc `:18`,
  read `:648`).
- **Truncation passes** (same file, `--truncate` `:553-601`): **three of five
  passes are bough** — pass 1 drops `bough_day` bodies (`:561`), pass 4 shrinks
  `bough_active` annotations (`:587`), pass 5 (hard-cap last resort) drops
  `bough_recent` (`:595`). Passes 2 (browser `:571`) and 3 (focus `:579`) are
  the only non-bough passes and are all that survives. **The slice inventory
  names only 4–5 and its Non-Goal claims removal "leaves passes 1–3"; both are
  wrong (D2).**
- **Sensor capsule** (`satan/satan-sensor-alerts.el`, 21 refs): `:bough` in
  `satan-sensor--source-order` and `--source-label`; the `bough_unreachable`
  cause derivation (`:130`); the `--bump-bough-streak` code (`:249`). Removing
  `:bough` from the fixed source-order makes the signal *absent* rather than
  `bough=ok` (SL-001 RN-1) — achieved by construction. **Plus a one-time cleanup
  of the persisted runtime state (RN-17):** `notified.json`
  (`satan-sensor-state-file`, under `XDG_STATE_HOME`, `:21`) durably holds
  `:streaks.bough_unreachable` and `:causes.bough_unreachable`; state is read
  whole (`:174`), cause maps copied (`:207`), and written back wholesale
  (`:396`), so merely deleting the bump/cause code **leaves those keys orphaned
  and preserved forever**. This is bough-*specific* integration state (not
  content-agnostic substrate), so it is pruned **in this slice** on state read —
  distinct from the memory-handle residue deferred to OQ-3.
- **Tank render** (`satan/satan-tank.el`, 7 refs): the `bough_active` render
  line and `--render-bough-active`.
- **Canon producer rules** (`satan/satan-memory-canon.el`, 23 refs): the two
  rules `bough.recent_status_change` (`:373`) and `bough.active_focus` (`:392`)
  — they *read* `:bough_recent`/`:bough_active` and `hints.focal_bough_nanoid`
  and *emit* grammar handles; dead-input once evidence is gone. Also the
  `:focal_bough_nanoid` hint-normalization block (`:246`) and its mention in the
  `satan-memory-canon-canonicalize-from-raw` contract docstring (`:602`).
- **Observer matcher** (`satan/satan-observer-classify.el`, 15 refs): the
  `:bough_event_match` predicate (`:266`, registered `:445`) and its
  `--motive-bough-nanoids` helper (`:252`) — the sole *bough-specific* matcher.
  *(The generic overlap ranker `--rank-motives-by-overlap` `:542` is preserved
  — §2.B.)*
- **Caller inputs — `focal_bough_nanoid`** (`satan/satan-tools-memory.el`): a
  field in the **shared `hints-shape`** (`:263`) exposed on **two** tool schemas
  — `memory_mark :hints` and `memory_resonate :cue.hints`. Removed from
  `hints-shape` (off both at once); docstring probe mention at `:236` updated.
  *(No `memory_note` tool exists — the round-0 draft misnamed this; RN-3.)*
- **Percept forwarding** (`satan/satan-percept.el`): `:bough_workspace` in the
  forwarded-opts docstring (`:48`) and "reads … and bough" (`:63`).
- **Harness** (`satan/harness/runloop.py:32-68`): `bough_read` in the tier-2
  drop set (inspected, harmless) and its `test_gptel_harness.py` fixture.

### 2.B Content-agnostic substrate (PRESERVE — dormant/propagatable)

Preserved whole; retiring any of it is the grammar-v2 + data migration (OQ-3).

- **Persisted grammar — elisp mirror**: `satan/satan-memory-grammar.el` (16
  refs), the in-process mirror of grammar v1 (docstring `:3-11`). Namespaces
  `bough_kind`/`bough_status`/`bough_event` (closed),
  `bough_node`/`bough_project` (open) (`:36-40`); closed-world values (`:77-83`);
  `artifact` values `bough_status_change`/`bough_task_created`/`bough_annotation`
  (`:68`); `outcome` value `bough_progress` (`:76`); weights incl. deliberate
  `bough_node = 0` (`:113-117`).
- **Persisted grammar — SQL**: `satan/memory/migrations/0002_grammar_v1.sql:39-43`
  holds the bough default-weight rows in the DB (`__default__`, matching elisp)
  (RN-4/RN-10 — corrected locator). Persistence split: the DB stores grammar
  *version + aliases + default weights* only (`0001_init.sql`, `0002`); the elisp
  side additionally mirrors namespace-world + closed-value tables, which are
  **not** persisted and are checked only by *internal* elisp consistency tests.
  The `db-sync-*` tests pin version/aliases/weights and permit the DB to run
  *ahead* of elisp — they do **not** prove the whole grammar unchanged (RN-4).
- **Motive vocabulary**: `satan/satan-motive.el:83-92`
  `satan-motive--admitted-namespaces` (`:85`) contains the three bough
  namespaces. It decides §S3 admission (admittable vs `:no-sensor-handle`
  dormant, `:147-156,212-233`) and gates write-validation (`:410-453`).
  Content-agnostic vocabulary, not a bough matcher — the *list* is **preserved
  untouched** (D4). This defconst line (`:85`) is the **single irreducible bough
  token** left in production (§9 census). The one *other* motive occurrence — the
  `:475` admission-error help-string example ("…app/surface/bough/topic…") — is
  **reworded to drop the bough example** (behaviour-neutral; the admitted set is
  unchanged) so the census gate has exactly one allowlisted occurrence (RN-14).
- **Generic retrieval/show/recent path**: `memory_resonate` accepts explicit
  caller `cue.handles` (string-list-validated only) → `satan-memory-store-resonate`
  inverted-index lookup over `trace_handles`, *no mutation*
  (`satan/satan-tools-memory.el:187-236`; `satan/satan-memory-store.el:200-236`).
  `memory_show_trace` and recent reads (`satan/satan-memory.el:107-121`) return
  whatever handles a trace holds. Content-agnostic; **historical
  bough-attributed memories stay queryable** (RN-1).
- **Generic handle-propagation (copy-forward)** — the paths RN-9 exposed:
  - Observer positive-persistence: `satan-observer--motive-handle-rows`
    (`satan/satan-observer.el:102`) converts a *fired* motive's `:cue` handles
    into mark rows written to a **new** trace (`:139,158-169`). A mixed
    app+bough motive fires via its non-bough overlap (the generic ranker,
    `satan-observer-classify.el:542-565`) and copies its bough handle forward.
    The correlation reads the run's **persisted percept** handles from
    `bundle.json` (`satan-observer-classify.el:531`) — a durable run artifact
    written as `percept.json` (`satan-percept.el:99`, const `--filename`) and
    mirrored into `bundle.json` (`satan-context.el:469` via `satan-audit.el:49`).
    So a bough handle can seed correlation from a run artifact, not only from a
    trace/motive/intervention (RN-13). Run artifacts live under
    `runs/<run-id>/` (runtime, gitignored) — named here for the OQ-3 topology.
  - Intervention counter-memory: `satan-intervention--counter-memory-handles`
    (`satan/satan-intervention.el:518`) writes an intervention's persisted
    `:cue_handles` **verbatim** into a new trace (`:561-580`); outcome
    forwarding carries cue handles too (`:456-474`).
  These are **content-agnostic** — they copy whatever handles a record already
  holds, with no bough-specific logic. **Preserved** (D1/§5.3); scrubbing
  residual bough handles from persisted records is OQ-3.
- **Generic seed-introduction (fresh literals)** — the paths RN-11 exposed:
  because the vocabulary admits `bough_*`, any generic handle-accepting API
  writes a caller/config-supplied bough literal without deriving it:
  `motive_replace` (`satan/satan-tools-motive.el:73` → validate-for-write
  `satan-motive.el:410-453`); `memory_resonate` explicit `cue.handles` recorded
  into `tool-call`/`tool-result` audit (`satan/satan-broker.el:324`); pattern
  sync into `satan_patterns.cue_handles_json` (`satan/satan-pattern.el:51,131-172`);
  `satan-intervention-create` into audit transcript + projection
  (`satan/satan-intervention.el:352,376-399`); the raw
  `satan-memory-store-mark` handle rows (`satan/satan-memory-store.el:91`).
  **Preserved as content-agnostic** (D1) — the removal adds no bough filter to
  generic APIs; closing this surface (reject `bough_*` at admission) is part of
  OQ-3.

### 2.C Prose — living vs frozen (RN-6, complete census)

Full markdown bough census (26 files) classified by front-matter `status:`:

- **Living / canon — reconciled in-slice** (declared `design-target`):
  `docs/architecture.md` (canon, `:27-34`), `docs/governance.md`
  (canon/"Living document", tool+evidence `:362,368`, modes `:487-492`, live
  tool `:521`), `docs/memory/design.md` (canon, 95 refs; evidence/canon/tool
  `:253-270,338-413,415-422,534-567`), `docs/protocol.md` (canon, cue-handle
  `:187`), `docs/patch/brief.md` (canon, 8 refs), `docs/data-collection.md`
  (living, tool+scopes `:167-181`, evidence+hard-cap `:471-485`),
  `docs/perceptual-design.md` (phase-6-shipped, observer/sensor
  `:364-418,457-476`), `docs/patch/plan.md` (living), `docs/INDEX.md` (living),
  `docs/bough-gaps.md` (living, 24 refs — a whole-doc bough analysis; **marked
  superseded** like the flag brief, not line-edited), and
  `docs/memory/handover.md` (**`status: living`**, 41 refs; says "`bough_read`
  is the only path into bough" `:14-20` — reconciled or formally superseded
  in-file; RN-12). Plus in-code prose comments `satan-resonance.el:19,41`,
  `satan-percept.el:63`, `satan-db.el:69`.
- **Authoritative-but-example-valid — no edit, explicitly classified**
  (`scope-relevant`): `docs/attributes/outcome-semantics.md` (**`status:
  merged`, `authority: blocking`** — wins over code `:15`; its lone bough cue
  example stays *semantically valid* under the preserved vocabulary, so it is
  not edited but is not "draft" either; RN-6). `docs/resonance-payload-handover.md`
  (`status: shipped`, 2 refs — dispositioned at plan).
- **Draft / secondary — dispositioned at plan** (declared `scope-relevant`;
  light annotation where they describe the removed integration as current, no
  load-bearing edits): `docs/at-satan/design.md`, `docs/at-satan/plan.md`,
  `docs/resilience-design.md`, `docs/refactor/T-attr-1-attribute-layer.md`,
  `docs/attributes.brief.md`,
  `docs/attributes/patterns_attributes.design_note.md`.
- **Frozen snapshots — left as history** (not selectors):
  `docs/bough-feature-flag-brief.md` (superseded), `docs/review/*` (dated
  review snapshots).

### 2.D Tests — classify each bough fixture (RN-15)

A bough test fixture is one of three kinds; the *class* is design/plan work, the
individual edits are execute-time. **Do not blanket-prune** — §9 relies on
some bough fixtures as preserved-boundary pins.

- **DELETE — integration-specific**: `satan/test/satan-tools-bough-test.el`
  (whole file, 93 refs) and bough cases that exercise *removed* machinery:
  evidence bough probes/status/truncation passes 1/4/5
  (`satan-memory-evidence-test.el`), the `:bough` sensor line + `bough_unreachable`
  (`satan-sensor-alerts-test.el`), the two canon bough rules
  (`satan-memory-canon-test.el`), the `:bough_event_match` predicate
  (`satan-observer-test.el`), the tank bough render (`satan-tank-test.el`),
  `focal_bough_nanoid` on the tool schemas (`satan-tools-memory-test.el`), and
  bough mode/tick fixtures in `satan-broker-test`/`satan-mcp-test`.
- **AMEND — mode-list / harness fixtures**: fixtures that merely *carry*
  `"bough_read"` in a mode `:tools` list or the harness tier set lose that entry
  (`satan-mode-test` and `satan-mcp-test` have 0 bough refs today, so likely no
  change; `test_gptel_harness.py` drops its fixture).
- **PRESERVE / ADD — substrate-boundary pins**: bough fixtures that prove the
  *preserved* content-agnostic behaviour stay (and are extended per §9) — e.g.
  `satan-intervention-test.el:410` (caller bough handles survive audit +
  projection, RN-15); `satan-audit-intervention-test.el:25`;
  **`satan-tools-atsatan-test.el:318,407,455`** (persisted intervention cue,
  caller `intervention-create` cue, counter-memory copy-forward — RN-15,
  substrate boundary, *not* mode/tick fixtures); motive admission of bough
  namespaces; historical explicit-handle retrieval. These are **not** integration
  tests and must not be pruned. `satan-memory-grammar-test.el` also **retains**
  its bough reference (`:74`, pins the preserved `bough_node` weight = 0) and
  stays **green unchanged** — a preserved-artifact pin, not an integration test.

`satan-mode-test.el`, `satan-mcp-test.el` stay **green unchanged** (0 bough refs
today; §5.3/§5.6).

### 2.F Durable / persisted-state census (the complete store taxonomy)

Every durable location that can hold a bough literal, and its disposition — the
category rounds 5–7 probed (RN-13/RN-16/RN-17/RN-18). Codex's round-7 sweep found
no bough-specific DB table, cache, or state file beyond these.

| Store | Nature | Disposition |
|---|---|---|
| `notified.json` (`XDG_STATE_HOME`, `satan-sensor-alerts.el:21`) | **active** sensor state; generic updates re-propagate it | **Prune in-slice** the `:streaks.bough_unreachable` + `:causes.bough_unreachable` keys on state read (RN-17) — bough-specific integration residue |
| `tick-trace-YYYY-MM-DD.jsonl` (`XDG_STATE_HOME`, `satan-trace.el:36`) | **append-only** tick telemetry; day-bucketed; no re-propagation | Removing the evidence reads deletes the `evidence.bough_recent/active/day` stage wrappers (`evidence.el:701,704,707`) so **no new** stage names are emitted; historical files are **immutable observability, retained/aged by retention — not scrubbed** (RN-18) |
| run audit bundle `runs/<run-id>/` (percept/bundle/transcript/final/actions/stdout/stderr) | append-only run artifacts carrying content-agnostic **handles** | **OQ-3** — retention/whole-run expiry or immutable preservation (RN-16) |
| memory DB (traces) · motives · interventions · attributes · `satan_patterns` DB + `patterns.eld` | content-agnostic **handle** stores; legal bough literals persist/propagate | **OQ-3** — scrub + reject `bough_*` at admission (RN-11/RN-13) |
| grammar: `satan-memory-grammar.el` + `0002_grammar_v1.sql` | persisted, version-gated **schema** | **Preserved** whole; retire via grammar-v2 (OQ-3) |
| external `bough_read` description (`satan-tools-descriptions-dir`, `~/notes`) | out-of-repo operator file | **Manual cleanup**, flagged in close notes (slice Non-Goal) |

The split is principled: **active** bough-specific state (`notified.json`) is
cleaned now; **append-only telemetry / audit** and **content-agnostic handle
stores** are historical data with no in-place-scrub obligation this slice —
retention/expiry (telemetry, audit) or the OQ-3 migration (handles, schema).

### 2.E Nil-safety (inherited from SL-001 §10 "Verified true")

SL-001 verified alert cause derivation, canon rule bodies, observer predicates,
and the tank renderer are all absent-key / nil-safe — the fact that makes removal
a *cascade*, not a minefield. We still remove the readers (no dead-input code);
nil-safety is what lets phases end green.

## 3. Forces & Constraints

- **Derivation/matching ≠ substrate.** The grammar (elisp + SQL) is DB-synced
  and version-gated; motive admitted-namespaces, the retrieval path, and the
  copy-forward writers are content-agnostic. None is hand-edited as bough
  machinery. This fixes the boundary — and it means bough *values* can persist
  and propagate after the *integration* is gone (honest §1 statement, D1).
- **No dead-input code, no half-states.** Producers, bridge, bough-specific
  matcher, and caller inputs of a removed data shape go together (SL-001 RN-2).
- **Two startup invariants** (verified, §10): `satan-mode-check-tool-references`
  (`satan-mode.el:60`) hard-errors if a mode `:tools` entry names an
  *unregistered* tool — registration and all seven mode entries drop in the
  **same** phase. The MCP description preflight (`satan-mcp.el:119`) checks the
  raw registry union — once `bough_read` is unregistered its description is no
  longer required.
- **Five hard-cap surfaces are already false and removal makes them worse.**
  SL-001 D7/RN-7: the truncation cap is documented "mandatory/hard" but never
  enforced. Removing passes 1/4/5 deletes the pass-5 last resort, leaving 2–3.
  All five surfaces (§5.5) are reconciled here; ISS-001 updated to the
  post-removal inventory — not closed (D3).
- **Compatibility, zero-migration.** Admitted-namespaces, the retrieval path,
  and the copy-forward writers are preserved untouched — so no persisted motive
  changes status, no historical memory becomes unreadable, and no propagation
  path breaks. Complete retirement (scrub vocabulary + residual handles) is
  OQ-3.
- **Every phase ends green; suites pass per phase.** TDD red/green/refactor.
- **Resurrection = git + ledger**, not scaffolding (slice Non-Goal).
- **Environment**: reservation remote unreachable — prefix id-allocating
  commands (the OQ-3 backlog item) with `DOCTRINE_RESERVATION_FALLBACK=1`.

## 4. Guiding Principles

- Remove the **bough-specific derivation and matching** completely and
  coherently; preserve the **content-agnostic substrate** whole and document its
  residual behaviour honestly.
- Leave no code referencing a removed shape (field, handle, hint, tool, option).
- Cut at cohesion boundaries; sequence leaf-first so each phase is green.
- Reconcile *living/canon* prose to reality; leave *frozen* snapshots as history.
- Byte-behaviour-neutral for every non-bough path; read- and
  propagation-compatible for every historical bough-attributed record.

## 5. Proposed Design

### 5.1 The boundary (the load-bearing decision — D1)

Cut between **bough-specific derivation/matching** (§2.A, removed) and
**content-agnostic substrate** (§2.B, preserved):

- Remove every derivation (evidence probes, canon rules, `focal_bough_nanoid`
  hint→handle), bough-specific matcher/signal (observer predicate, sensor synth,
  alerts, tank), the tool, load edge, mode/tick allowlist, truncation pass, and
  caller input (`focal_bough_nanoid` both schemas, `:bough_limit`,
  `:bough_workspace`).
- Preserve the grammar (elisp + SQL), motive admitted-namespaces, the generic
  retrieval path, and the generic copy-forward writers.

End-state, half-state-free and honest: nothing *derives, matches, signals, or
advertises* bough; the substrate retains a complete dormant bough sub-vocabulary,
stays read-compatible with existing data, and can still *propagate* a
pre-existing bough handle through content-agnostic machinery — which is exactly
what a versioned schema + generic memory engine does between a feature's removal
and its schema's next version. The narrower truth (§1 block-quote) replaces the
round-0 "closed and frozen" claim, which RN-9 disproved.

### 5.2 Seam-by-seam removal (code impact / touch-set)

| Surface | Change |
|---|---|
| `satan-tools-bough.el` | delete file (registration dies with it) |
| `satan-memory.el` | drop `(require 'satan-tools-bough)` + docstring mention |
| `satan-mode.el` | drop `"bough_read"` from 5 specs |
| `satan-tick.el` | drop `"bough_read"` from tick-pulse + tick-agent defaults |
| `satan-memory-evidence.el` | drop 3 bough reads + `--bough-call`; `--bough-status` + `:bough` synth; 3 evidence fields; `bough-limit` defcustom **and `:bough_limit` opt** (`:22`,`:653`); `:bough_workspace` opt (`:18`,`:648`); truncation passes 1, 4, 5 (survivors keep labels; OQ-2); docstrings |
| `satan-sensor-alerts.el` | drop `:bough` source-order + label; `bough_unreachable` cause; `--bump-bough-streak`; **add a one-time state-read prune of the persisted `:streaks.bough_unreachable` + `:causes.bough_unreachable` keys in `notified.json`** (RN-17) |
| `satan-tank.el` | drop `bough_active` render line + `--render-bough-active` |
| `satan-memory-canon.el` | drop `bough.recent_status_change` + `bough.active_focus` rules; `:focal_bough_nanoid` hint-norm (`:246`) + docstring mention (`:602`) |
| `satan-observer-classify.el` | drop `:bough_event_match` predicate + registration + `--motive-bough-nanoids` (leave the generic ranker) |
| `satan-tools-memory.el` | drop `focal_bough_nanoid` from shared `hints-shape` (`:263`) — off both `memory_mark` + `memory_resonate`; fix docstring (`:236`) |
| `satan-percept.el` | drop `:bough_workspace` docstring (`:48`) + "reads … and bough" (`:63`) |
| `satan-motive.el` | reword the `:475` help-string example to drop `bough` (behaviour-neutral); **`satan-motive--admitted-namespaces` `:85` untouched** (D4) |
| `harness/runloop.py` + `test_gptel_harness.py` | drop `bough_read` tier-2 entry + fixture |
| living/canon docs (§2.C) | reconcile bough-as-current; `bough-gaps.md` → superseded |

### 5.3 Preserved (dormant/propagatable) — and why it stays consistent

- **Grammar (elisp + SQL)** — untouched, both artifacts. `db-sync-*` +
  internal-consistency tests green unmodified. §9 adds a **no-diff check** on
  `satan-memory-grammar.el` and `0002_grammar_v1.sql`.
- **Motive admitted-namespaces** — untouched (D4). Persisted motive status
  unchanged; bough-only stays admittable, mixed unchanged; no write-validation
  change; no operator migration.
- **Historical data + propagation** (RN-1/RN-9) — the retrieval path and the
  copy-forward writers are content-agnostic and preserved. Existing
  bough-attributed traces remain queryable; a retained motive/intervention that
  carries a bough handle can still fire (via any overlapping handle) and copy
  that handle into a new trace. **No bough handle is ever *derived* anew** (all
  derivation removed) — but the historical set is **not frozen**; it can echo
  forward from existing seeds until OQ-3 scrubs vocabulary + residual handles.
- Resting state: legal-but-underivable + read/propagation-compatible — correct
  for a versioned closed-world vocabulary + generic memory engine, not dead
  *code*.

### 5.4 Motive vocabulary & the `focal_bough_nanoid` split (D4)

RN-2 proved the round-0 plan wrong: *removing* the motive bough namespaces flips
persisted bough-only motives to dormant and rejects future writes
(`satan-motive.el:147-156,212-233,410-453`). Ruling: **keep**
`satan-motive--admitted-namespaces` (`:85`) as preserved vocabulary; **reword**
the separate `:475` help-string example to drop `bough` (behaviour-neutral — the
admitted set is unchanged), so production holds exactly one bough token and the
§9 zero-token gate is satisfiable (RN-14). Corrected semantics (RN-2 residue): a
retained bough motive is **not universally
inert** — a mixed app+bough motive still fires via its non-bough overlap (generic
ranker) and propagates its bough handle; a bough-only motive fires only if a
persisted percept already carries that bough handle (no *new* bough handle
enters a percept, derivation being gone). Zero migration; §9 tests all three
cases (bough-only / mixed / historical-pending) plus counter-memory copy.

`focal_bough_nanoid` is the opposite case — a **producer input** feeding only the
removed `bough.active_focus` rule and derived-cue canonicalization. Removed from
the shared `hints-shape` (off both schemas). Explicit-handle retrieval is
unaffected: a caller may still pass `bough_node:<id>` in `cue.handles`; it just
can no longer be *derived* from a hint.

### 5.5 Documentation reconciliation — five hard-cap surfaces + living docs (D3)

Five living assertions of a mandatory/hard truncation cap — never enforced, now
hollowed to passes 2–3 — reworded to **deterministic best-effort / last-resort**:
(1) evidence header `:budget_hard_cap_bytes hard byte cap` (`evidence.el:22`);
(2) `budget-hard-cap` defcustom doc (`:79-81`); (3) `--truncate` docstring
"HARD-CAP (mandatory)" (`:553-558`); (4) `docs/memory/design.md:415-422`;
(5) `docs/data-collection.md:471-485`. Pass-5's inline "hard cap" comment is
*deleted with pass 5*, not reconciled. Plus a **repo-wide** evidence-cap wording
gate (§9) closes the sixth-surface risk. Wording-only; the behavioural reducer
stays with ISS-001, whose body is updated to passes 2–3 — **not closed**.

Living-doc removal (RN-6): the §2.C living/canon set is reconciled in-slice and
declared as `design-target`; draft/secondary docs are `scope-relevant`
(dispositioned at plan); frozen snapshots left as history.

### 5.6 Invariants, assumptions & edge cases

- `satan-mode-check-tool-references` passes post-removal (tool unregistered *and*
  absent from every mode list — same phase).
- MCP description preflight no longer requires a bough description; the external
  description file under `satan-tools-descriptions-dir` (`~/notes`, outside repo)
  is flagged for manual cleanup in close notes.
- Grammar (elisp + SQL) unchanged; `db-sync-*`, internal-consistency (incl.
  `satan-memory-grammar-test.el:74` pinning the preserved `bough_node` weight),
  `satan-mode-test`, `satan-mcp-test` green unmodified; no-diff check enforces it.
- Cue derivation (`satan-tools-memory--derive-cue-handles`) still works
  (`:cue_only` already skips bough_recent/day); post-removal it produces no bough
  handles. Explicit-handle resonate still returns historical bough traces.
- Truncation: oversized objects run passes 2–3 only; no bough labels in
  `:truncated_at`. Tests assert label honesty + bough-label absence — **not** a
  byte-cap bound (never held; ISS-001).
- Sensor line carries no `bough=` segment (source-order entry deleted).
- Persisted motives: status unchanged; mixed motives fire and propagate bough
  handles; bough-only fire only on a persisted percept overlap.
- Non-bough classification/resonance/motive firing unchanged for every non-bough
  handle.

## 6. Open Questions & Unknowns

- OQ-1: **[RESOLVED, RN-6]** Living/canon docs enumerated (§2.C) + edited
  in-slice; drafts dispositioned; frozen snapshots left. No deferral.
- OQ-2: **Truncation survivor labels** — keep `browser_segments_middle` /
  `focus_segments_middle` after deleting passes 1/4/5, or renumber comments.
  Cosmetic; plan decides.
- OQ-3: **Complete bough retirement follow-up** — a backlog item (grammar-v2 +
  data migration) to retire the dormant bough vocabulary (elisp + SQL) — which
  closes both copy-forward *and* fresh-introduction by rejecting `bough_*` at
  grammar admission — **and** disposition every residual store (RN-11/RN-13):
  scrub persisted traces, motives, interventions; the attribute inbox/events;
  the `satan_patterns` DB **and its authoritative source `satan/patterns.eld`**
  (a gitignored runtime/operator config file — else a scrubbed DB re-seeds from
  the file on next sync); and the **entire per-run audit bundle** under
  `runs/<run-id>/` (`satan-audit.el:3`), which durably carries handles across
  `percept.json`, `bundle.json`, `transcript.jsonl`, `final.json`, `actions.json`,
  and even raw `stdout.log`/`stderr.log` (the broker tees a `memory_resonate`
  bough cue there before parsing — `satan-broker.el:389`; final/actions written at
  close — `satan-audit.el:109`; action payloads pass validation unfiltered —
  `satan-protocol.el:86`, `satan-output.el:28,89`) (RN-16). These artifacts are
  **append-only** (reopen never rewrites, `satan-audit.el:78`), so they cannot be
  scrubbed in place — disposition the run bundle by retention/whole-run expiry or
  explicit immutable preservation. Related-to SL-002. Allocate with
  `DOCTRINE_RESERVATION_FALLBACK=1`.

## 7. Decisions, Rationale & Alternatives

- **D1: cut between bough-specific derivation/matching and content-agnostic
  substrate.** Remove derivation/matchers/signals/tool/inputs; preserve grammar
  (elisp+SQL), motive vocabulary, the retrieval path, **and the copy-forward
  writers** — documenting that pre-existing bough handles stay readable and can
  propagate (RN-1/RN-9). Alternative A (deep purge: strip grammar + vocab + scrub
  historical handles + filter propagation) — rejected: a grammar-v2 change gated
  by a DB sync test, a data rewrite, and a data-migration; a separate slice
  (OQ-3). Alternative B (bough-specific filter in the generic propagation
  writers) — rejected: re-introduces bough-specific code into the substrate we
  are removing bough-specificity *from*, and is incomplete (doesn't scrub
  existing data). Alternative C (delete only the files the slice lists) —
  rejected: dead-input canon code, a dead two-schema tool input, an unreconciled
  retrieval/propagation story, and (RN-2) would *break* persisted motives if it
  touched admitted-namespaces. D1 is the only boundary that is coherent,
  half-state-free, and zero-migration.
- **D2: correct and complete the inventory.** The slice omits the SQL grammar
  artifact, the two-schema `focal_bough_nanoid`, `:bough_limit`,
  `:bough_workspace` percept forwarding, the canon docstring, two hard-cap
  surfaces, six-plus living/canon docs, and the copy-forward paths; and
  mis-states the truncation passes (1/4/5 are bough, leaving 2–3). §2 is the
  corrected map; the slice scope is reconciled post-lock.
- **D3: reconcile all five hard-cap surfaces here; update ISS-001, don't close.**
  Removing pass 5 worsens the false wording; a repo-wide gate guards a sixth.
- **D4: preserve motive vocabulary; remove the `focal_bough_nanoid` producer
  input.** Vocabulary removal changes persisted-motive status/writes (RN-2);
  keeping it is zero-migration. Bough motives are not universally inert (mixed
  fire + propagate); the producer input is removed from both schemas.
- **D5: resurrection via git history + SL-001 ledger; no scaffolding.** Record
  pre-removal SHA in close notes.

## 8. Risks & Mitigations

- **R1: an omitted bough reference survives.** Mitigation: §2 full sweep; §9
  **cross-extension** completeness census (`.el`+`.py`+`.sql`+living `.md`), no
  `bough` outside a narrow justified allowlist (grammar elisp+SQL, motive
  admitted-namespaces, documented propagation/historical note, frozen docs).
- **R2: touching the grammar reddens the sync test / drifts elisp↔SQL.**
  Mitigation: D1 forbids touching either; §9 no-diff check + unchanged `db-sync-*`.
- **R3: a persisted motive / historical memory / propagation path breaks.**
  Mitigation: D4 + RN-1/RN-9 keep admitted-namespaces, the retrieval path, and
  the copy-forward writers untouched; §9 tests bough-only/mixed motive
  classify+persist, historical retrieval (resonate/show/recent), counter-memory.
- **R4: startup invariant regression.** Mitigation: same-phase removal; existing
  `satan-mode-test` / `satan-mcp-test` green (0 bough refs) confirm.
- **R5: test-suite blast radius** (~17 files). Mitigation: leaf-first phasing,
  suites green per phase.
- **R6: false residual-freeze belief.** Mitigation: §1/§5.3 state propagation
  honestly; OQ-3 owns the complete scrub; §9 asserts *no new derived* handles,
  not *no new* handles.

## 9. Quality Engineering & Validation

ert, red/green, `satan/test/`; suites green per phase.

- **Completeness census (R1/RN-14)**: hard grep gate (VT) — a **zero**-`bough`-token
  gate over all production `.el`/`.py`/`.sql`, with the allowlist restricted to
  the exact persisted-grammar artifacts (`satan-memory-grammar.el`,
  `0002_grammar_v1.sql`) and the single motive-vocabulary occurrence
  (`satan-motive--admitted-namespaces`). The content-agnostic substrate files
  (`satan-observer.el`, `satan-intervention.el`, `satan-attribute.el`,
  `satan-pattern.el`, `satan-memory-store.el`, `satan-broker.el`,
  `satan-context.el`, `satan-audit.el`) carry **no** `bough` token today and stay
  under the zero-token gate — a future accidental bough branch there must fail.
  Bough boundary *fixtures* live in tests + this design's prose, never in generic
  production files; harness free of `bough_read`; the runtime
  `satan/patterns.eld` (gitignored) verified clean where present (currently 0).
  Separate doc review (VA) — every living/canon `.md` mentions
  bough **only** as removed/historical, never as a live capability; frozen
  `docs/review/*` + superseded briefs untouched.
- **Preserved-artifact no-diff (R2)**: `satan-memory-grammar.el` and
  `0002_grammar_v1.sql` byte-identical pre/post; `satan-memory-grammar-test.el`
  (`db-sync-*` + internal) green **unmodified**.
- **Startup invariants**: `satan-mode-check-tool-references` green post-removal;
  MCP preflight passes with `bough_read` absent; `satan-mode-test` /
  `satan-mcp-test` green unmodified.
- **Evidence/truncation** (`satan-memory-evidence-test.el`): no `:bough_*`
  fields, no `:bough` sensor_status; `:bough_limit`/`:bough_workspace` opts no
  longer consumed; oversized object runs passes 2–3 and records **no** bough
  label in `:truncated_at` (label honesty, not a byte bound — D3).
- **Sensor** (`satan-sensor-alerts-test.el`): no `bough=` segment; no
  `bough_unreachable` cause derivable; **and persisted-state cleanup (RN-17)** —
  a `notified.json` pre-seeded with `:streaks.bough_unreachable` and
  `:causes.bough_unreachable` (plus an unrelated non-bough cause), run through the
  post-removal state read/write path, ends with **both bough keys absent and the
  unrelated sensor state intact**.
- **Tick telemetry (RN-18, VA)**: a post-removal evidence assembly emits **no**
  `evidence.bough_recent/active/day` stage into `tick-trace-*.jsonl`
  (`satan-trace.el`); historical day-bucketed files are left untouched (immutable
  retained observability, §2.F).
- **Canon/observer** (`satan-memory-canon-test.el`, `satan-observer-test.el`):
  bough rules + `:bough_event_match` predicate gone; non-bough rules/predicates
  and the generic overlap ranker unchanged; cue derivation yields no bough
  handles.
- **Tool schemas** (`satan-tools-memory-test.el`): both `memory_mark` and
  `memory_resonate` no longer advertise `focal_bough_nanoid`; existing flows
  unchanged.
- **Historical read (RN-1)**: a seeded trace with a `bough_node:` handle is
  still returned by explicit-`cue.handles` resonate, `memory_show_trace`, **and
  recent-trace reads** (all three preserved paths).
- **Motive + propagation (RN-2/RN-9)**: (a) a mixed app+bough persisted motive
  still classifies/fires via its non-bough overlap and its bough handle is
  copied into the persisted observation trace; (b) a bough-only motive keeps its
  admittable status and **does not fire absent a bough-bearing percept, yet is
  selected and fires *when a persisted percept carries its bough handle*** (the
  positive historical-percept case, RN-7); (c) manual counter-memory from a
  stored bough-bearing intervention copies the bough handle verbatim
  (`satan-intervention-test.el`); (d) an assertion that **no bough handle
  originates from evidence/canon derivation** (the honest invariant, not "no new
  bough rows").
- **Content-agnostic residual surfaces (RN-9/RN-11, boundary pins not
  regressions)**: attribute outcome forwarding copies a bough-bearing
  intervention's cue handles into its record (`satan-attribute-test.el`); and
  **all five** fresh-introduction surfaces still *accept* a caller-supplied
  `bough_*` literal as an **intended, documented** consequence of the preserved
  vocabulary (removal adds no bough filter; closure is OQ-3): `motive_replace`
  (`satan-tools-motive-test.el`), `memory-store-mark`
  (`satan-memory-store-test.el`), pattern sync (`satan-pattern-test.el`),
  `intervention-create` audit+projection (`satan-intervention-test.el:410`,
  preserved), and `memory_resonate` explicit `cue.handles` recorded into the
  broker's `tool-call`/`tool-result` audit (`satan-broker-test.el`).
- **Doc reconciliation (D3/RN-6, VA)**: all five hard-cap surfaces carry the
  narrowed wording; the repo-wide gate is clean; the §2.C living/canon docs no
  longer describe live bough behaviour (`bough-gaps.md` superseded); ISS-001 body
  updated to passes 2–3.

## 10. Review Notes

### Inquisition round 1 (codex) — RV-001

Verdict: **unsound to lock** — 3 BLOCKER, 5 MAJOR (`.doctrine/review/001/`).
RN-1 (BLOCKER): preserved grammar not absolutely dormant — generic retrieval
returns historical bough handles. RN-2 (BLOCKER): removing motive vocabulary
flips persisted bough motives to dormant + fails writes. RN-3 (BLOCKER): caller
inputs misidentified (no `memory_note`; shared `hints-shape` on
`memory_mark`+`memory_resonate`; `:bough_limit` opt; `:bough_workspace` percept;
canon `:602`). RN-4 (MAJOR): SQL grammar artifact + true sync-test scope omitted.
RN-5 (MAJOR): five hard-cap surfaces, not three. RN-6 (MAJOR): living-doc
inventory deferred + incomplete. RN-7 (MAJOR): §9 tests around the claims.
RN-8 (MAJOR): no selectors → `review prime` refused.

#### Adjudication round 1 (claude)

All 8 independently re-verified against source; all confirmed, none contested.
Design amended: D1 reframed (machinery vs substrate); D4 flipped (preserve motive
vocab); §2 inventory corrected (SQL, two-schema input, `:bough_limit`,
`:bough_workspace`); five hard-cap surfaces; living docs enumerated; §9
strengthened; 36 selectors added + RV-001 primed.

### Inquisition round 2 (codex) — RV-001 (re-primed)

Verdict: **unsound to lock**. RN-3, RN-5 **RESOLVED**. RN-4 **PARTIAL**
(SQL locator wrong: rows at `:39-43`, cited `:17-21` — also RN-10). RN-2
**PARTIAL** ("simply never fires" false — a mixed app+bough motive fires via its
non-bough handle through the generic ranker and copies its bough handle forward;
a bough-only motive can be evaluated against an older pending intervention's
persisted percept). RN-1 **BLOCKER-STILL** + **RN-9 (new BLOCKER)**: generic
writers *copy handles forward* into new traces — observer positive-persistence
(`satan-observer.el:102,139,158-169`) and intervention counter-memory
(`satan-intervention.el:518,561-580`; outcome `:456-474`) — so "no producer
creates new bough handles / closed and frozen" is false. RN-6 **BLOCKER-STILL**:
living-doc census incomplete — omits canon `governance.md`, `architecture.md`,
`patch/brief.md` (and others). RN-7 **BLOCKER-STILL**: §9 doesn't test recent
reads, mixed-motive classify+persist, historical-pending bough-only, or
counter-memory copy. RN-8 **BLOCKER-STILL**: selectors omit preserved artifacts
(grammar elisp+SQL, grammar test), startup tests, copy-forward sources, and the
missing living docs. RN-10 **MINOR**: SQL locator.

#### Adjudication round 2 (claude)

All independently re-verified against source; all confirmed, none contested.
Verification: RN-9 — `satan-observer--motive-handle-rows`
(`satan-observer.el:102`) + `satan-intervention--counter-memory-handles`
(`satan-intervention.el:518`, "CUE-HANDLES verbatim") write cue handles into new
traces via `mark-fn :handles`. RN-2 residue — `--rank-motives-by-overlap`
(`satan-observer-classify.el:542`) ranks by content-agnostic cue∩percept overlap,
skipping only dormant motives → mixed bough motives fire. RN-4/RN-10 — bough
weight rows at `0002_grammar_v1.sql:39-43`. RN-6 — `governance.md` (canon,
"Living document"), `architecture.md` (canon), `patch/brief.md` (canon), plus a
full 26-file census. RN-8 — startup tests carry 0 bough refs (scope-relevant,
green unmodified).

Design amended in place:
- RN-1/RN-9 → **D1 reframed to derivation/matching vs substrate**; §1 block-quote
  states the narrower truth; §2.B adds the copy-forward writers explicitly; §5.3
  replaces "closed and frozen" with honest propagation semantics; OQ-3 widened to
  scrub residual handles; §9 asserts "no *derived* bough handle" (not "no new").
- RN-2 residue → §5.4/§5.6 corrected: mixed motives fire + propagate; bough-only
  fire only on a bough-bearing percept; "universally inert" burned.
- RN-4/RN-10 → §2.B SQL locator fixed to `:39-43`; persistence split kept.
- RN-6 → §2.C rewritten as a **complete 26-file census** (living/canon → edit;
  draft → disposition; frozen → leave); `bough-gaps.md` marked superseded.
- RN-7 → §9 adds recent-read, mixed/bough-only/historical-pending motive,
  counter-memory copy, and the honest no-derived-handle assertion.
- RN-8 → selectors expanded: `design-target` += the living/canon docs;
  `scope-relevant` += grammar elisp+SQL, grammar/mode/mcp tests, `satan-observer.el`,
  `satan-intervention.el`, `satan-motive.el`, draft docs; RV-001 re-primed.

Amended; requesting round 3 verdict.

### Inquisition round 3 (codex) — RV-001 (re-primed, 57 selectors)

Verdict: **unsound to lock**. RN-2 residue, RN-4/RN-10 **RESOLVED**. RN-7
**PARTIAL** (missing positive historical-percept case, attribute propagation,
seed-introduction tests). RN-1/RN-9 **BLOCKER-STILL** + **RN-11 (new BLOCKER)**:
the copy-forward story assumed every propagated value is a pre-existing seed, but
generic write APIs also **introduce fresh caller/config-supplied bough literals**
— `motive_replace` (`satan-tools-motive.el:73`), `memory_resonate` cue.handles →
audit (`satan-broker.el:324`), pattern sync (`satan-pattern.el:51,131-172`),
`satan-intervention-create` (`satan-intervention.el:352,376-399`),
`satan-memory-store-mark` (`satan-memory-store.el:91`), attribute forwarding
(`satan-attribute.el:68,131-150`). The "no *derived* handle" invariant holds, but
"only pre-existing handles enter new records" is false; OQ-3's scrub inventory
omitted patterns/attributes/audit. RN-6 **BLOCKER-STILL** + **RN-12 (new
MAJOR)**: `docs/memory/handover.md` is `status: living` (`:7`) but was filed
frozen while still describing `bough_read` as the only live path (`:14-20`).
RN-8 **BLOCKER-STILL**: selectors omit `handover.md`, `satan-tools-motive.el`,
`satan-attribute.el`, `satan-pattern.el`, `satan-memory-store.el`,
`satan-broker.el`, and their tests.

#### Adjudication round 3 (claude)

All independently re-verified against source; all confirmed, none contested.
Verification: RN-11 — `satan-tool/motive-replace` validate-then-atomic-write
(`satan-tools-motive.el:73`); `satan-memory-store-mark` raw caller handle rows
(`:91`); pattern grammar-valid handle write; `satan-attribute-build-outcome-payload`
carries `cue-handles`; broker records `tool-call` obj into audit
(`satan-broker.el:324` → `satan-audit-record`). RN-12 — `handover.md` front-matter
`status: living`, "`bough_read` is the only path into bough".

Design amended in place:
- RN-1/RN-9/RN-11 → §1 block-quote now enumerates **three** residual mechanisms
  (read / copy-forward / **fresh introduction**) as an intentional consequence of
  the preserved vocabulary; §2.B adds the seed-introduction surfaces explicitly;
  OQ-3 widened to reject `bough_*` at admission **and** scrub every residual store
  (traces, motives, interventions, patterns, attribute inbox/events, audit).
- RN-7 → §9 adds the positive historical-percept firing case, attribute-payload
  propagation, and content-agnostic seed-introduction tests (boundary pins, not
  regressions).
- RN-6/RN-12 → §2.C: `docs/memory/handover.md` moved to **living** (reconciled or
  formally superseded in-file, `design-target`); `outcome-semantics.md`
  reclassified as **merged/blocking, example-valid** (no edit, explicit);
  `resonance-payload-handover.md` (`shipped`) → `scope-relevant`; frozen set now
  only superseded briefs + `docs/review/*`.
- RN-8 → selectors expanded again: `design-target` += `docs/memory/handover.md`;
  `scope-relevant` += `satan-tools-motive.el`+test, `satan-attribute.el`+test,
  `satan-pattern.el`+test, `satan-memory-store.el`, `satan-broker.el`,
  `resonance-payload-handover.md`; RV-001 re-primed.

Amended; requesting round 4 verdict.

### Inquisition round 4 (codex) — RV-001 (re-primed, 67 selectors)

Verdict: **unsound to lock**. RN-2, RN-6/RN-12 **RESOLVED**. RN-7, RN-8
**PARTIAL**. **RN-13 (new BLOCKER)**: the copy-forward seed list and OQ-3 omit
the persisted **percept** the positive bough-only test correlates from —
`satan-observer-classify.el:531` reads `bundle.json → :percept → :handles`,
durably written as `percept.json` (`satan-percept.el:99`) and mirrored into
`bundle.json` (`satan-context.el:469` via `satan-audit.el:49`); OQ-3 also
half-enumerated patterns (named the `satan_patterns` DB but not its authoritative
source `satan/patterns.eld`, `satan-pattern.el:44,174`) and used the incoherent
verb "scrub" for append-only audit (`satan-audit.el:3,78`). **RN-14 (new
MAJOR)**: the census gate allowlisted whole generic files (observer/intervention/
attribute/pattern/memory-store/broker) — all 0-bough today — creating a sanctuary
for a future accidental bough branch. **RN-15 (new MAJOR)**: §2.D ordered
blanket pruning of bough cases from the same intervention/audit suites §9 needs
as preserved boundary pins (`satan-intervention-test.el:410`).

#### Adjudication round 4 (claude)

All independently re-verified; all confirmed, none contested. Verification:
RN-13 — `satan-observer--intervention-percept-handles` reads `bundle.json`
percept (`observer-classify.el:531`); `percept.json` const (`percept.el:99`);
`bundle.json` mirror (`context.el:469`); `patterns.eld` is the
authoritative source repopulating the DB (`pattern.el:44,174`; `git check-ignore`
confirms it is a **gitignored** runtime/operator config, currently 0 bough);
audit append-only (`audit.el:3,78`).
RN-14 — the eight generic substrate files carry **0** bough tokens today
(grepped). RN-15 — `satan-intervention-test.el` asserts caller bough handles
survive audit+projection.

Design amended in place:
- RN-13 → §1/§2.B add the per-run percept artifacts (`percept.json`/`bundle.json`)
  as a copy-forward seed source; OQ-3 now names run artifacts + `patterns.eld`
  (not just the DB) and reframes audit disposition as **retention/whole-run
  expiry or explicit preservation**, not in-place scrub.
- RN-14 → §9 census is now a **zero-token gate** over all production code, with
  the allowlist restricted to the exact grammar artifacts + the single motive
  vocabulary occurrence; generic files stay under zero-token.
- RN-15 → §2.D rewritten to **classify** each fixture (delete integration /
  amend mode-list / **preserve** substrate-boundary pins); §9 now tests all
  **five** fresh-introduction surfaces explicitly (adds `memory_resonate`→audit
  + `intervention-create`).
- RN-8 residue → selectors += `satan-audit.el`, `satan-context.el`
  (`scope-relevant`); `satan/patterns.eld` and the run artifacts are gitignored
  runtime/config (not selectors — dispositioned in OQ-3 prose); RV-001 re-primed.

Amended; requesting round 5 verdict.

### Inquisition round 5 (codex) — RV-001 (re-primed, 69 selectors)

Verdict: **unsound to lock**. RN-7, RN-8 **RESOLVED**; RN-13 **PARTIAL** (active
seed topology correct; store list still incomplete → RN-16). **RN-14
BLOCKER-STILL**: the census allowlisted "the single motive occurrence" but
`satan-motive.el` has **two** bough tokens — `admitted-namespaces` (`:85`) and
the `:475` help-string example the design said "stays accurate" — so executing
the design leaves `:475` present while the gate fails; D4/§2.B/§9 disagreed.
**RN-15 PARTIAL**: `satan-tools-atsatan-test.el:318,407,455` are substrate-boundary
pins (persisted/caller intervention cue + counter-memory) wrongly filed under
DELETE; and the "`satan-memory-grammar-test.el` 0 bough refs" claim is false — it
pins the preserved `bough_node` weight at `:74`. **RN-16 (new MAJOR)**: OQ-3's
"every residual store" omitted the rest of the run bundle — `final.json`,
`actions.json`, `stdout.log`/`stderr.log` all durably carry handles
(`satan-audit.el:3,109`; broker tee `satan-broker.el:389`; unfiltered action
payloads `satan-protocol.el:86`, `satan-output.el:28,89`).

#### Adjudication round 5 (claude)

All independently re-verified; all confirmed, none contested. Verification:
RN-14 — `grep -n bough satan-motive.el` → `:85` + `:475`. RN-15 —
`satan-tools-atsatan-test.el:318,407,455` are `bough_node:abc` cue/counter-memory
cases; `satan-memory-grammar-test.el:74` asserts `bough_node` weight 0. RN-16 —
`satan-audit.el:2-8` lists the seven run artifacts; `satan-broker.el:389` tees
stdout.

Design amended in place:
- RN-14 → §2.B/§5.2/§5.4 now **reword** the `:475` help-string example to drop
  `bough` (behaviour-neutral; admitted-namespaces `:85` still untouched), so
  production carries exactly **one** bough token; §9 gate allows only that
  occurrence; `satan-motive.el` moved to `design-target`. D4/§2.B/§9 now agree.
- RN-15 → §2.D moves `satan-tools-atsatan-test.el` cases to **PRESERVE**;
  corrects the grammar-test census (it **retains** `:74`, a preserved-artifact
  pin, green unchanged); `satan-mode-test`/`satan-mcp-test` are the true
  0-bough-ref pair.
- RN-16 → OQ-3 now dispositions the **entire per-run audit bundle** (`percept`,
  `bundle`, `transcript`, `final`, `actions`, `stdout`/`stderr`) by
  retention/whole-run expiry or immutable preservation, not in-place scrub.

Amended; requesting round 6 verdict.

### Inquisition round 6 (codex) — RV-001 (re-primed, 69 selectors)

Verdict: **unsound to lock**. RN-13, RN-14, RN-15, RN-16 **all RESOLVED**; codex
confirmed the remaining test-writing and OQ-3 follow-up are execute-time
obligations that do **not** hold the lock. One new: **RN-17 (MAJOR)** —
integration-specific persisted sensor state is declared removed but never
dispositioned. `notified.json` (`satan-sensor-alerts.el:21`) durably holds
`:streaks.bough_unreachable` + `:causes.bough_unreachable`; state is read whole
(`:174`), cause maps copied (`:207`), written back wholesale (`:396`), so deleting
the bump/cause code alone leaves both keys preserved indefinitely. This is
bough-specific residue, not preserved substrate — it must be cleaned in this
slice.

#### Adjudication round 6 (claude)

RN-17 independently re-verified against source (state file `:21`; whole-object
read `:174`; `--bump-bough-streak` `:249`; `bough_unreachable` cause map `:130`;
wholesale writeback `:396`) — confirmed; the persisted keys would orphan and
survive generic updates. Accepted; this is integration flesh, not substrate.

Design amended in place:
- RN-17 → §2.A/§5.2 add a **one-time state-read prune** of the two persisted
  `notified.json` keys (bough-specific, cleaned in-slice — distinct from the
  memory-handle residue deferred to OQ-3); §9 adds a pre-seed → post-removal
  state-path → both-keys-absent-while-unrelated-state-survives test.

Amended; requesting round 7 verdict.

### Inquisition round 7 (codex) — RV-001 (re-primed, 69 selectors)

Verdict: **unsound to lock**. RN-17 **RESOLVED**. The requested durable-state
sweep found **one** further store: **RN-18 (MAJOR)** — XDG tick telemetry
`tick-trace-YYYY-MM-DD.jsonl` (`satan-trace.el:36`, append JSONL) durably records
the `evidence.bough_recent/active/day` stage names
(`satan-memory-evidence.el:701,704,707`); deleting the evidence call sites stops
new records but leaves historical telemetry undispositioned. Codex confirmed **no
other** bough-specific DB table, cache, or source-owned state file exists.

#### Adjudication round 7 (claude)

RN-18 re-verified: the three bough reads are wrapped in
`satan-trace-stage[-optional] "evidence.bough_*"` (`evidence.el:701-708`);
`satan-trace.el` is the append-only day-bucketed tick-telemetry core under
`XDG_STATE_HOME`. Accepted. Unlike `notified.json` (active, re-propagating state
→ pruned), tick-trace is append-only telemetry with no re-propagation → historical
retention, not in-slice scrub — codex concurs.

Design amended in place:
- RN-18 → new **§2.F durable/persisted-state census** consolidates the complete
  store taxonomy and its per-store disposition (active `notified.json` pruned
  in-slice; append-only telemetry + audit bundle retained/expired; content-agnostic
  handle stores + schema via OQ-3/preserved; external description manual). Removing
  the evidence reads deletes the `evidence.bough_*` stage wrappers so no new stage
  names emit; historical tick-trace files are immutable retained observability. §9
  adds the tick-telemetry check; `satan-trace.el` added as `scope-relevant`.

Amended; requesting round 8 verdict — the durable-state taxonomy is now
consolidated and, per codex's own sweep, exhaustive.

### Inquisition round 8 (codex) — RV-001 (re-primed, 70 selectors)

**Lock verdict: sound to lock.** RN-18 **RESOLVED** (tick-telemetry disposition
correct — stage names originate only in the evidence wrappers `:701`, are never
read/propagated, so removing the wrappers stops emission with no historical
rewrite; retain-not-scrub is the right contrast with active `notified.json`).
Durable-state census **complete** — no unclassified bough-specific store; the DB
holds only the five deliberately preserved grammar-weight rows. One execution-time
note (traces `metadata_json` carries the full evidence window incl. historical
`bough_*` payloads, not just `trace_handles`) is **already covered** by §2.F's
"memory DB (traces)" row + OQ-3's scrub-persisted-traces instruction — no design
amendment required. Test implementation, individual edits, and the OQ-3 migration
are downstream work that does not hold the lock.

> "The pyre stands empty; no further design heresy remains." — RV-001

#### Lock (claude)

Eight rounds; every finding re-verified against source before acceptance; none
contested; all resolved or correctly deferred. **Design SL-002 is sound to lock.**
The removal plan (§2.A/§5.2) was stable from round 1; rounds 1–8 hardened the
*boundary* (bough-specific derivation/matching removed vs content-agnostic
substrate preserved), the *inventory* (§2/§2.F complete + corrected), and the
*verification* (§9). Awaiting the human lock gate before `/plan`.
