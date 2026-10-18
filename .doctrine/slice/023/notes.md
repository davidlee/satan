# Notes SL-023: Patch runner for the oubliette assistant room

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Pre-design research (2026-10-18)

Research artefact (gitignored, on disk): `.doctrine/slice/023/research/research.md`
+ `raw/` — five threads (governance, elisp runner, Go satan-patcher, oubliette
door, malebolge/pi-durable/pi-env) and an option-D spike. Leading candidate:
**option D** — a daemon runner hosting a pi-durable harness on the host, tools
in the room via pi-env; both existing runners retired (logic ported, not code).
Oubliette SL-005 consumes the same file (its X6/X7 cross-check is in it).

## Design triage (2026-10-18, run dr-01a14d77)

Input: research F1–F9, deltas 1–7, EVD-005. Terms: *room* = persistent
oubliette microVM; *door* = Plan F §5 ingress (agent user, runner key, relay
socket); *quarantine* = host bare repo guest commits are fetched into.

**Constraining governance**
- POL-001 — earns-the-seat (queue/dispatch/fetch: No; promotion UI: Yes);
  Rust target with workload-fit exceptions; cutover not addition; disable
  switch; ceilings hold with Emacs absent; ert corpus → acceptance fixtures.
- ADR-017 §1 (Emacs owns approval surfaces), §3 (one owner per item; ledger
  INV-1..3), §4 (fail closed client-absent).
- ADR-018 D1 (one daemon repo — none exists yet; `~/dev/satan-attrd` is a
  single Rust crate), D3 (Postgres state, control plane UDS RPC; no new
  `pg_notify` control traffic, VT-3), D5 (no new stateful layer in elisp),
  OQ-2/OQ-3 open (don't front-run the global RPC shape).
- SPEC-001 REQ-003 audit, REQ-004 ceilings, REQ-005 kill switch fails closed,
  REQ-007 lifecycle is request/response, REQ-009 no dual enforcement,
  REQ-010 fail closed. SPEC-002 REQ-013 one schema owner per store (today
  `patch_jobs`: elisp 0005 + Go 0006). SPEC-003 OQ-3 (SL-023 picks the
  surviving runner and its spec). DEC-049 (no credential row), DEC-043
  (gateway budgets ≠ SATAN ceilings), oubliette DEC-031 (room stops routine).

*Superseded by the inquiry outcome: DEC-050..DEC-064 and REV-006 are
authoritative; the lists below are the pre-inquiry triage.*

**Shaping decisions (proposed)** — option D; both runners retired (logic
ported); Emacs keeps producer tool, inbox, promotion.

**Open questions** — QUE-005 (glue language/repo), QUE-006 (room down);
store layout; control socket + auth (RSK-018); replay-safe tools; per-job
ceiling; audit writer for patch jobs (row 4 forbids a third writer);
`patch_jobs` contract owner + ISS-041; who enacts promotion; ledger rows;
runner spec home.

**Assumptions** — ASM-005 (door as sketched). Door-touching decisions
(room addressing, quarantine fetch) defer to oubliette SL-005's design;
build against slot f / a stub until then.

**Risks** — pi-durable/pi-env are experimental ("changes without notice") →
pin versions; designing against a sketched door; half-extraction during
cutover (two consumers live, ISS-039).

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-18 · design locked (run dr-01a14d77 rev 44); plan written, 14 phases materialised, slice ready · e8f4012 + uncommitted

### Produced
- SL-023 scoped, linked (IDE-007/008, RFC-018, ISS-030/038/039/041, IMP-006; governed_by POL-001, ADR-017, ADR-018) — 42b2dea
- IDE-007 gateway-key wording corrected — 42b2dea
- research round + option-D spike against capsule slot f — artefact on disk, not committed
- design run inquiry complete: DEC-050..DEC-064 (shape SL-023); inq-14 deferred on ASM-005 — uncommitted
- REV-006 applied: ADR-018 D1/D3 scope amendment, POL-001 IMP-006 destination — uncommitted
- IMP-041 (malebolge lint → typescript-eslint, before runner code) — uncommitted
- slice scope aligned to the decisions (objective 7 added) — uncommitted
- design.md drafted: 14 sections materialised, design-target selectors recorded; user rulings on §6 OQ-1..OQ-6 and pre-ready fixes 1-6 applied; DEC-052 (ordered creation) and DEC-058 (ack op, failure resend) amended with revision notes; `drafting-ready` recorded — uncommitted
- DEC-056 amended (recovery before resume); run advanced to reviewing; Codex (gpt-6-sol) pass on RV-025: 14 findings (4 blocker, 9 major, 1 minor), all accepted fix-now and integrated; F-1/F-2 routed demonstrate (model gate, env-boundary failure typing), rest review; DEC-055 and DEC-057 amended — uncommitted
- RV-025 third pass: F-4, F-8, F-13, F-15..F-19 verified; F-19 raised; DEC-057 note (warning placement via submission record) — uncommitted
- design locked 2026-10-18: section attestations, review-disposed (conducted RV-025), design-accepted; slice-023.md risks/closure reconciled — uncommitted
- plan.toml + plan.md (PHASE-01..14), phase sheets materialised, slice status ready — uncommitted
- slot f left running; its volume holds `~/sl023-spike` and the pi-env daemon in `~/.pi`

### Learned
- pi-durable: no hook can deny a request (throwing hooks are skipped); tool/env exceptions are converted before afterTool; submit/abort/compact/wait start the task scheduler
- doctrine orders design sections by id *lexically* (sec-10 before sec-2) and has no section delete; bodies were rebound so reading order holds
- pi-durable 1.3.0 `beforeRequest` rewrites messages only — no per-request maxTokens hook (design §6 OQ-1)
- EVD-005 — pi-env drives a slot through its relay; dropped connection fails one tool call, run recovers
- mem.pattern.satan.pi-env-oubliette-gateway — recipe: pi-env via relay ProxyCommand, pi-ai via the gateway
- pi-durable: one SQLite file may hold pi tables (prefix) and host tables via one adapter; built-in tools declare no replay (unsafe) — cited in DEC-052/054
- Biome 2.5 lacks tsc-backed unsafe-any / strict-boolean / assertion rules — IMP-041

### Open
- design §6 OQ-1 — model gate; PHASE-01/EX-2 demonstrates it; on failure /consult and amend DEC-057 (weaker guarantee, user ruling)
- RV-025 — concluded and disposed conducted; F-1/F-2 (BLOCKER, demonstrate) answered, transcribed into PHASE-01/EX-2 and EX-3; verify on RV-025 after the spike
- Further review passes (2026-10-18, after RV-025 concluded): none before lock. Three Codex passes converged; the last rounds found only wording and one crash-window edge. What remains unproven is empirical, not textual: the model gate (F-1, OQ-1), pi-env failure typing and the wrapper's host write (F-2, F-17), steer placement mid-run and status() leaving scheduling paused. The first-phase spike is the next probe; a re-review is warranted only if the spike fails and DEC-057/DEC-055 are amended.
- ASM-005 — oubliette SL-005 pins the door as Plan F §5 sketches (room adapter, door config, promotion verb wait on it)
- QUE-005, QUE-006 — answered (DEC-051, DEC-055)
