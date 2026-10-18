# Review RV-024 — reconciliation of SL-022

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Mode: **conformance** (post-implementation, self-audit). Surface: primary
checkout, main @ 9b44a21 (in-session capsule run, not /dispatch).

Lines of attack:

1. **Invariants I1–I6** (design § Invariants) hold in code, not just in the
   phase evidence: I1 closure sweep; I2/I3 via the flake check and its
   negative control; I4 refusal typing (ready/error/timeout/signal edges,
   first-write-wins); I5 frontiers commit once, only on `ready`, against the
   perceive snapshot; I6 no host fact in satan elisp/Python.
2. **Code impact table** (design § Code impact) vs what landed. Conformance
   undeclared paths are leads: `satan/satan.el` (`satan-run-attended`
   deletion), `satan/test/satan-patch-adapter-test.el`,
   `docs/perceptual-design.md`, `docs/refactor/*`, `docs/review/*`.
3. **Orchestrator adaptations** beyond EX criteria (PHASE-03 diagram moved
   from 06; PHASE-05 deleting `satan-run-attended` and a Python test; PHASE-04
   test renames) — scope creep or legitimate?
4. **Error classes** (design § Error classes rules 1–4) match
   `classify_error`; no `openai` import in runloop.
5. **Docs truth** (PHASE-06): governance.md claims checked against code.
6. **Governance follow-through** (design § Governance follow-through): every
   stale governing text is routed to the reconciliation brief (SPEC-003 REV,
   SPEC-002, ADR-017 ledger note, DEC-020/021/022, ASM-002, ISS-023, QUE-001,
   ISS-029, REQ-016/025).
7. **Residual risks surfaced in execution**: ISS-044 sentinel stderr race,
   stderr-tail drain race (PHASE-03 residual), launcher refusal hint naming
   the wrong alias, CHR-013/014.
8. **Gates**: `just check`, `just check-jails`, `doctrine check gate`,
   `doctrine slice verify-vt 22`.

## Synthesis

**Closure story.** SL-022 does what the design said. SATAN reaches models only
through the host LLM gateway. The harness reads `SATAN_MODEL`,
`LLM_GATEWAY_URL` and `LLM_GATEWAY_KEY`, and the jail launcher passes the key
over a file descriptor. Every provider-key, `op://` and `satan-credential`
path is gone from the broker, the patch runner, the pi adapter, the test
harness and the Emacs config. The I1 and I6 sweeps are clean, and the flake
check enforces I2 and I3; its negative control was recorded at PHASE-02. The
four live checks passed on the deployed system at PHASE-08: a tick succeeded
with spend on `satan`, the argv scan found no key, a refused launch ended
`spawn_failed` with the launcher's message in the audit, and Emacs started
clean. Gates at 2243b41: `just check` (1341/1348 passed, 7 skipped; 55 Python
tests OK), `just check-jails`, `doctrine check gate`, and every VT passes.

**What the audit changed.** Four code fixes landed in 2243b41, all small, and
two of them closed holes in I4 ("a child that dies before `ready` is never an
untyped failure"):
- a failed `stderr.log` flush (the ISS-044 race) no longer skips the refusal
  record (F-2);
- a child that delivered `final` is not treated as a refusal (F-4);
- the `--commit-frontiers` trace wrappers were dead once the commits moved
  after the tick, so they went (F-3);
- PHASE-05's closure sweep had deleted the PHASE-01 "stray `SATAN_PROVIDER`
  is ignored" test, so it was restored (F-1).

**Standing risks.**
- ISS-044: the stderr-flush race still loses `stderr.log` occasionally, and
  it can still abort a `just test` run. It no longer costs the typed refusal.
- The PHASE-03 stderr drain race (stderr arriving after the main sentinel)
  has no bounded drain. The refusal test passed 80/80 runs, 40 of them under
  8-way load. Accepted, not fixed.
- The frontier commits now run in the stdout process filter, so a slow psql
  attribute enqueue blocks the filter rather than the tick. There is no
  deadlock, since the harness doesn't wait on stdin after `ready`, but this is
  a new execution context.
- The perceive snapshot is taken after the percept build, so rows that land
  between the two can still be skipped. The window is narrower than before
  the slice.
- PHASE-08 VH-3 for the patcher was best effort only: ISS-038 and ISS-039
  (whether `jailed-pi` resolves for the daemon) are still open.

**Tradeoffs accepted.**
- F-6 is tolerated: the no-argument live-heads branch of
  `satan-ingest-cursor-advance` stays, because PHASE-03 EX-3 requires it and
  no broker path reaches it.
- `satan-run-attended` was deleted in PHASE-05, beyond its EX criteria. Its
  only consumer was the deleted credential policy, and nothing in satan/,
  dev/, docs/, `~/.config/emacs` or `satan/bin` references it.

**Design opportunity, not a defect.** Three stderr-tail helpers now exist:
`satan-broker--stderr-tail` (byte-capped, character-safe) and two identical
last-10-lines copies in `satan-attribute-listener.el:279` and
`satan-patch-listener.el:116`, which predate this slice. They are candidates
for one shared helper.

## Reconciliation Brief

### Per-slice (direct edit)
- **F-7** — selector registry: `doctrine slice selector add` (design-target)
  for `satan/satan.el`, `satan/test/satan-patch-adapter-test.el`,
  `docs/perceptual-design.md`, `docs/refactor/**`, `docs/review/**`, so
  `slice conformance 22` reports no undeclared code/doc paths. Mirror these in
  design.md § Code impact: `satan.el` drops `satan-run-attended` (its only
  consumer was the credential policy); the pi child-env test lives in
  `satan-patch-adapter-test.el`; perceptual-design CONSUME diagram; T8
  `abandoned`; historical banners.
- **F-2, F-4** — design.md § A refused launch: the refusal rule is "the
  process ended with neither `ready` nor `final`, and the run is still
  `running`". The `stderr.log` flush fails soft, so a missing run dir cannot
  cost the refusal.
- **F-3** — design.md § Frontiers commit on `ready`: the commits run from the
  process filter after the tick, outside any tick trace. The four
  `probes.commit.*` / `spawn.ingest_cursor` tick-trace stages are retired.

### Governance/spec (REV)
- **F-8** SPEC-003 → REV modify:
  - spawn-contract key row → "none: the jail launcher supplies
    `LLM_GATEWAY_KEY` by fd";
  - model+budget row drops `SATAN_PROVIDER`;
  - REQ-020: retitle, or withdraw in favour of a jail-enforced env rule (the
    jail starts from `env -i`; the launcher process still inherits the Emacs
    env until emacs:SL-015);
  - REQ-022: the harness reads model, budgets and the gateway pair from env;
    there is no provider key;
  - REQ-025: the jail forwards only the declared `SATAN_*` vars; the launcher
    sets `LLM_GATEWAY_URL` and passes `LLM_GATEWAY_KEY` by fd;
  - "Failure at spawn": a child that ends with neither `ready` nor `final`
    and no `error` is `spawn_failed`, and frontiers commit on the first
    `ready`.
- **F-8** SPEC-002 → REV modify: the overview no longer says the editor
  supplies a credential backend; Transports gains harness/pi → gateway; update
  the REQ-016 rationale gap list.
- **F-8** ADR-017 authority ledger (`.doctrine/adr/017/authority-ledger.md`):
  add a note that provider-credential custody left SATAN's inventory for the
  host gateway (DEC-049). No new row. Annotate RFC-018 D3 and D5 step 1.
- **F-8** knowledge:
  - DEC-020, DEC-021, DEC-022 → superseded by DEC-041 and DEC-042;
  - ASM-002 → invalidated/retired;
  - QUE-001: drop the `credential_*` pre-spawn gates from its list.
- **F-8** backlog:
  - ISS-023 → closed, `obsolete` (no 1Password dialog remains);
  - ISS-029 → resolved for `~/dev/satan`; split the `satan-attrd/flake.nix:66`
    forward into a new backlog item.
- **F-8** REQ-016 and REQ-025 stay `pending`: criteria 1–3 belong to ISS-028.
  No status change.
