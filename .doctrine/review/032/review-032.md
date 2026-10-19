# Review RV-032 — reconciliation of SL-025

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Mode: **conformance** (self-audit). Subject SL-025, all five phases complete.
Five repos: this repo (selector-fenced), M `~/dev/malebolge`, F `/srv/fleet`,
H `~/flakes`, C `~/satan-corpus` — the last four are outside the source-delta
registry, so they are audited by hand against design §4–§6.

Lines of attack:

1. **M vs §4.2** — config refusal set, `withinModeScope` first and before the
   repo lookup, containment by `disallowedPaths` only, scope outside the policy
   ladder (`policy.ts` untouched), lifetime (submit-only admission; replay,
   run and rejoin unaffected by narrowing). VT keyword mandates present.
2. **This repo vs §4.1** — stamping from ctx `:mode-name`, refusal without it,
   defcustom gone; and the cross-system join: do real run ctxs carry
   `:mode-name` strings equal to the runner's mode names, and do those lanes
   allow `patch_job_create`?
3. **H vs §4.3**, **F vs §4.4**, **C vs §4.5** — literal conformance and any
   change made beyond the design.
4. **Deployment vs §4.6** — drain, one switch, prompts after restart, reload;
   provenance of the deployed runner build.
5. **Verification vs §6** — every VT/VH row has evidence; gates re-run now
   (M, this repo, F).
6. **Governance follow-through (§7)** — SPEC-004 job contract and ADR-017
   ledger rows; memory correction; conformance registry cells.


## Synthesis

**Closure story.** SL-025 turned a runner mode from a policy rung into a lane
with a boundary. Emacs now stamps the acting run mode on every
`patch_job_create` (DEC-068), and the runner refuses a submit whose repo or
paths fall outside that mode's required `repos` / `allowed_paths` (DEC-069).
The room holds `satan` and `satan-corpus`, so SATAN's two self-edit lanes have
somewhere to run.

```
SATAN run (mode m) ──ctx :mode-name m──▶ patch_job_create ──submit{mode:m}──▶ runner
                                                                   │ withinModeScope(m): repo ∈ repos, paths ⊆ allowed_paths
                                                                   │ else invalid_request "…it allows: …"
                                                                   ▼
                                                     room assistant /work/<repo> ─▶ collect ─▶ needs_review
```

- **Conforms:** M `226b27c` matches design §4.2 nearly verbatim.
  `withinModeScope` runs first and before the repo lookup. Containment reuses
  `disallowedPaths`, `policy.ts` is untouched, and admission is the scope
  snapshot (VT-3, VT-4 and VT-5 cover replay, run and rejoin after narrowing).
- **Conforms:** this repo `36cd441` matches §4.1. H `338beea1` matches §4.3:
  the rendered config has 4 modes and 15 repos, with `tick-agent` computed.
- **Gates re-run during the audit:** M `just check` passes (1276 tests, zero
  warnings). This repo passes (1309 ert tests, 0 unexpected; 55 Python OK).
  F passes.
- **Live (PHASE-05):** one job per lane reached `needs_review`, one
  out-of-scope submit was refused naming the allowed repo, and the
  `interactive` smoke passed.
- **Divergences:** each is a design under-statement, not a code defect (F-1
  `"*"` on both axes, F-2 the fleet's goad follows, F-3 the check guidance).
  They go to the per-slice design.
- **Deployment provenance (F-6, major):** the one real gap. The live runner was
  built from an unpushed checkout, while H's lock still pins a pre-SL-025
  malebolge. A build from the lock would refuse the new config. Fixed only by
  the user's push and re-lock.

**Standing risks.**
- RSK-019: `interactive` is unbounded, as accepted.
- ISS-028: the harness jail binds `~/dev/satan` read-write, so
  `self-edit-mech` can still bypass the patch lane.
- The broker → `:mode-name` join is proven statically only (F-9). The first real
  lane run exercises it, and a mismatch would fail loudly.
- ISS-044: the satan `just check` sentinel flake seen in PHASE-02 is already
  captured there.
- IMP-044 (room repos hand-copied in three places: fleet, runner.nix and
  SATAN.md), IDE-011 and ISS-047 stay open.

**Accepted tradeoffs.**
- Refusing `"*"` as a list member on both axes (stricter than the design
  wrote).
- The fleet's goad moved forward 2 commits for the goad and goad-walk rooms as
  a side effect of the follows.
- The lane jobs used a hand-built ctx rather than a broker run during the
  sitting.

## Reconciliation Brief

### Per-slice (direct edit)
- **F-1** — design.md §4.2, config-refusal bullets: the `"*"`-as-list-member
  refusal applies to `repos` and `allowed_paths` both. Add why: it is a
  mistaken unbounded marker, and a repo named `*` must not widen a scope.
- **F-2** — design.md §4.4 table: the `satan` input also has `goad` follow the
  fleet's. Note that the fleet's goad was bumped to satan's pin (04147ca), and
  that satan is pinned at 5eee5c8 (pushed main), not cc26eeb. §7 "Second satan
  pin": the room's goad now tracks the fleet's goad, which must not lag
  satan's.
- **F-3** — design.md §4.5 `self-edit-mech.txt` row: the `checks` guidance
  moves into the directive. The agent runs `just check` and reports its
  counts, and uses `SATAN_TEST_ALLOW_NO_DB=1` only when the test DBs are
  unreachable, saying so. The old `SATAN_DB_HOST` / "exits 0" claims were
  stale.
- **F-5** — selector registry (load-bearing):
  `doctrine slice selector add 25 design-target .doctrine/memory/items/mem_01a0ae3334d77601b434d10108d73464/`.
  Mirror it in design.md §5 under "satan (this repo)" as the memory item row.

### Governance/spec (REV)
- **F-8** — SPEC-004 § Job contract → REV modify. Add:
  - `mode` names a runner mode, set by the client from the acting run mode,
    never a model argument (DEC-068);
  - each `[mode.<m>]` requires `repos` and `allowed_paths`, each a non-empty
    list or `"*"`;
  - a submit outside them is refused `invalid_request`, naming what the mode
    allows;
  - admission is the scope snapshot, so narrowing config affects new submits
    only (DEC-069).
- **F-8** — ADR-017 authority ledger → REV modify:
  - row 9 *Enforced at* adds "submit: mode scope `withinModeScope`
    (`protocol.ts`, DEC-069)";
  - row 1 *Enforced at* notes that `patch_job_create`'s mode is stamped from
    the tool ctx (`satan-tools-patch.el`, DEC-068), not schema-validated
    model input.
