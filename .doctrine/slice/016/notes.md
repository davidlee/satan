# Notes SL-016: goad as SATAN's elicitation surface

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest

**fresh-as-of:** stage `design` (pre-design research round complete), head
`6c4eaf8`, 2026-09-21. Nothing implemented; nothing committed.

### Produced

- **SL-016** — this slice. Scoped, tagged, `governed_by` ADR-017 / ADR-001 /
  POL-001, `related` RFC-016.
- **IMP-020** — SATAN rewrites its own goad backend via satan-patcher
  (deferred follow-up; `references/originates_from` SL-016).
- **Research artefact** — `.doctrine/slice/016/research/` (runtime tier,
  gitignored): `research.md` + `raw/{governance,code-map,goad-contract}.md` +
  hand-stamped `baseline.toml`. **Disposable** — anything below that must
  outlive the slice has a durable sink named here.
- **`.gitignore`** gained `.doctrine/slice/*/research/`, matching the existing
  runtime-tier block.

### Learned (durable sinks)

- [[mem.fact.satan.intervention-classification-gate]] — **recorded this
  session.** The correlation gate, predicate ordering, and the manual/auto
  split in `satan-observer-classify*`. This is the finding that most changes
  SL-016's design, and it is general to any intervention work.
- Not yet sunk, still only in the disposable research artefact — harvest at
  close if they survive contact with design:
  - SATAN parses no TOML in elisp and has no library on the load path; adding
    one would be the first elisp package dep and contradicts `satan.el:5`.
  - Probes do not feed the percept — they emit numeric attribute pressure via
    `satan-attribute-enqueue`; model-readable content is the evidence-assembler
    route or an on-demand tool.
  - `satan-tool--description` **signals** on a missing corpus-side `.md`, so a
    tool landed in the mechanism repo without its description breaks every run
    of every mode that allowlists it.
  - goad's renderer now draws **all five** field kinds; `~/satan/goad/field-notes.md`
    (2026-09-14) is stale on this.

### Open

Carried into `/design`; ids are doc-local to the slice scope document.

- **OQ-1** — which PERCEIVE route (attribute pressure / evidence-window content
  / on-demand tool), or which combination. Re-framed by research: it is a
  three-way, not capsule-vs-tool.
- **OQ-2** — one queue file or file-per-question. Research dissolved the stated
  deciding constraint (no concurrency exists); decide on provenance grounds.
- **OQ-3** — where the keeper's answer lands SATAN-side; entangled with the
  correlation question below.
- **OQ-4** — **resolved by research**: a fourth entry in
  `satan-observer--predicates`, not a manual-outcome write.
- **NEW — motive correlation.** How a goad ask correlates, given that without
  overlap nothing classifies at all. Gates both legs of the slice's own
  verification intent. Design must settle this first.
- **NEW — refusal transport.** Whether `goad-emit`'s refusal envelope arrives on
  stdout, stderr, or the exit code. Decides the shell-out tier, because
  `satan-trace-call` discards stderr. A five-minute experiment.
- **A1 — falsified.** POL-001's thin-shell seat does not reach goad (its
  rationale is output landing on the *editing* surface). Design owes an explicit
  No-branch / no-trigger-fired ruling; widening the seat clause is a REV, not a
  slice edit.
- **A2 — partly settled.** `data/*.toml` is corpus-tracked at `eeb4f3c`. Queue
  and answers placement is a *separate* call and fits neither root cleanly —
  see the governance tension below.
- **Governance tension (unresolved, two accepted authorities).** ADR-018 D5
  (*"no new stateful layer lands in elisp"*) vs POL-001's anti-candidate clause
  (tiny single-file state stays). ADR-018 VA-4 is checked at design review, so
  it must be settled there, not drift.
- **Revision candidates** (none caused by this slice; route via `/reconcile`
  REV at close): POL-001's seat rationale; `.doctrine/state/boot.md` still says
  the protocol spec and authority ledger are *"not written yet"* (both exist);
  RFC-017 D1 rows G1/G2 still read *"not written"* (both landed).
- **Blockers to real use.** ISS-012 (scheduled `motd`/`morning` runs fail at
  turn 0 on an expired key) — and `tick-pulse`, the only unattended mode that
  completes, holds neither `notify` nor `inbox-write` capability
  (`satan/satan-mode.el:146-154`).
