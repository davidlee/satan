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
fresh-as-of: 2026-10-18 · design (reviewing, run rev 30) · 2619867 (all SL-022 work uncommitted)

### Produced
- research round 1 — `research/research.md` (gitignored), threads in `research/raw/`
- design run reviewing; sections 1–9 in `design.md`; RV-023 holds 18 findings, all answered (F-5 and F-8 tolerated; F-16..F-18 from the reviewer's re-check)
- DEC-041..DEC-049 — the design's decisions (DEC-041/047/048 amended after RV-023; DEC-047 again after user overruled F-8)
- minted: ISS-043 — satan-attrd jail forwards keys on argv (split from ISS-029); flakes:IMP-037 — gateway launcher hint names jail not client
- cross-repo prose edits, uncommitted: emacs:SL-015 slice-015.md (ownership pointer), flakes:IMP-030 body (promotion note)
- live probe on the `pi` gateway key (two tiny deepseek-flash calls)

### Learned
- mem.fact.satan.deploy-provenance-split — broker loads live from ~/dev/satan; deployed harness from flakes' locked satan input; rollout order matters
- mem.fact.satan.llm-gateway-error-shapes — budget 429 `budget_exceeded`, model-access 403, reasoning_content passes through

### Open
- QUE-004 — who records the flat `reasoning_effort` client convention (flakes README vs emacs:SL-015)
- DEC-048 — $20 lifetime budget for the `satan` key is a proposal the user may adjust
- RV-023 — all 18 verified and the pass concluded at rev 30 (F-1/F-2 routed `review`); awaiting user acts: section-reviewed, review-disposed, design-accepted
