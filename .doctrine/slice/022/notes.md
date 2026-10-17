# Notes SL-022: SATAN's jails and patcher on the LLM gateway

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Further review pass

Written after RV-023 concluded (rev 30). None needed before lock: 18 findings
over two re-check rounds, the last of which surfaced only nits and local
mechanics. A further pass would probe, in order of risk:
- the frontier move to `ready`: every caller of `satan-ingest-cursor-advance`
  and every probe commit still sees a consistent snapshot, and a run that never
  reaches `ready` leaves each frontier untouched;
- the cross-repo rollout window (DEC-048): no tick between landing satan and
  restarting Emacs runs an old broker against a new harness that rejects it;
- `classify_error` rule order against real openai SDK exception shapes, not
  the fakes.
These are better settled by the planned tests and the VH rollout checks than by
another prose pass.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-18 · ready (plan authored, no phase started; design run locked rev 34) · 4efa5fa

### Produced
- research round 1 — `research/research.md` (gitignored), threads in `research/raw/`
- design locked (run rev 34); sections 1–9 in `design.md`; RV-023 concluded, 18 findings verified (F-5, F-8 tolerated; F-1/F-2 routed `review`)
- `plan.toml` / `plan.md` — 8 phases, run order 01, 02, 07, 03, 04, 05, 06, 08; phase sheets materialised
- DEC-041..DEC-049 — the design's decisions (DEC-041/047/048 amended after RV-023; DEC-047 again after user overruled F-8; DEC-048 again at planning: deploy the harness before the broker work)
- minted: ISS-043 — satan-attrd jail forwards keys on argv (split from ISS-029); flakes:IMP-037 — gateway launcher hint names jail not client
- cross-repo prose edits, uncommitted: emacs:SL-015 slice-015.md (ownership pointer), flakes:IMP-030 body (promotion note)
- live probe on the `pi` gateway key (two tiny deepseek-flash calls)

### Learned
- mem.fact.satan.deploy-provenance-split — broker loads live from ~/dev/satan; deployed harness from flakes' locked satan input; rollout order matters
- mem.fact.satan.llm-gateway-error-shapes — budget 429 `budget_exceeded`, model-access 403, reasoning_content passes through

### Open
- QUE-004 — who records the flat `reasoning_effort` client convention (flakes README vs emacs:SL-015)
- DEC-048 — $20 lifetime budget for the `satan` key: confirm with the user at PHASE-07 EX-1
- research.md drifted from slice/design (advisory); not restamped — design supersedes it
- CHR-009 (reindent `satan-broker--spawn`) overlaps PHASE-05; candidate to fold in

## PHASE-01 execution (harness on the gateway)

### Done
- `build_provider` now reads SATAN_MODEL / LLM_GATEWAY_URL / LLM_GATEWAY_KEY via `_required`; registry, deepseek/openrouter adapters, `SATAN_PROVIDER` and the `op://` check removed. Stray `SATAN_PROVIDER` is ignored.
- `classify_error`: budget_exceeded -> credits, 403 "not allowed to access model" -> auth, then MRO-name rules (APITimeoutError -> timeout before APIConnectionError -> server). No openai import in runloop.
- Tests: factory tests rewritten; classify tests added with an `_error` helper; five duplicated run-env blocks collapsed into `_run_harness`.
- Python 55 tests OK (54 before). `just check` 1368/1374, 6 skipped (same as baseline). ruff E,F,W clean; VA-1 empty.

### Learned
- `doctrine slice verify-vt` stays UNATTRIBUTABLE until the phase's files are committed (it keys on files modified by the slice's commits).
- A docstring that mentions `SATAN_PROVIDER` trips the VA-1 rg; reword rather than exempt.
