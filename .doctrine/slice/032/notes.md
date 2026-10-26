# Notes SL-032: MCP run identity per conversation, not per connection

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-10-26, exploring → inquiring)

Superseded in detail by the design run. Evidence: `research/research.md`.
Settled: DEC-121..DEC-125 (design B, amended after an informal Codex review
the same day). inq-4 and inq-7 non-durable; inq-6 deferred to malebolge
IDE-002. Scope: `slice-032.md`.

Codex review (gpt-6.1-sol, informal, no ledger), findings and outcome:
1 close during nested wait → DEC-122 (deferred finalisation, interrupted
calls); 2 non-dispatch writers → DEC-123; 3 status `completed` fails the
verifier → DEC-122; 4 pool lifetime → DEC-125; 5 refresh coupling →
DEC-125; 6 initialize state → DEC-121/122; 7 kind per activity → pool key
(conversation, kind); 8 ADR-017 §4 / REQ-007 → DEC-122 rationale and the
SPEC-001 revision; 9 upstream `_meta` instead → declined (user kept B).

Drafting settled the open items: all four emitter callers are listed in
design sec-4; the observer passes its broker run, and manual counter-memories
pass none.

## Review pass plan (2026-10-26, reviewing)

RV-060 pass conducted (Codex gpt-6.1-sol, raiser; three rounds): 7 findings,
F-4..F-7 verified; F-1..F-3 (major) answered with design repairs the raiser
accepted, their probe/demonstrate obligations deferred to `/plan` (route
criteria read from the RV ledger).

A further design pass is not needed: the remaining risk is in mechanism that
only an implementation can settle. If one ran, it would probe:

- the settle/admission rules (sec-3) under a real nested
  `satan-patch-rpc` wait — that is the F-1/F-2 probe, owned by the plan;
- the pool's new-entry refresh against a restarted live server — the F-3
  demonstration, owned by the plan;
- whether closing the transport on `quit` is the right user-facing response
  (a design judgement the user may revisit at section review).

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-26 · ready, PHASE-01 next (phases materialised) · b30b00a

### Produced

research/research.md; DEC-121, DEC-122, DEC-123 (amended, RV-060 F-5),
DEC-124, DEC-125; design.md (locked, run rev 35); 9 design-target selectors;
RV-060 (pass conducted, 7 findings); plan.toml / plan.md (PHASE-01..08).

### Learned

- pi/MCP tie identity to the connection; pi-mcp passes
  `capabilities.experimental` (research Thread 3; DEC-121).
- MCP close status `completed` fails `satan-audit-verify-run` (pre-existing;
  DEC-122).
- `satan-patch-rpc.el:137` permits nested dispatch (DEC-123).
- `@satan` directives run as a broker-tick tool and emit `trace_marked`
  against the consuming run today (DEC-123 amendment).
- quotient pi workers see only their `cwd` root: malebolge work needs
  `cwd: ~/dev/malebolge` (a satan-rooted worker reports it empty).

### Open

- RV-060 F-1/F-2 (probe), F-3 (demonstrate): answered; discharged by
  PHASE-05/06/07 VA rows.
- At reconcile: SPEC-001 REQ-007 and QUE-001, SPEC-002 transports row,
  memory mem_eb8e5cff…, malebolge IDE-002 note (design sec-91).
