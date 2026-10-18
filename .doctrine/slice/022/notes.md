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

## PHASE-02 execution (jails on the gateway, and the flake check)

### Done
- `flake.lock` `agents`: `cfda05a5` -> `8b0206dd` (GitHub main, descends from `a24a0f03`). Only that node's `rev`/`narHash`/`lastModified` moved.
- `flake.nix`: `piGateway` / `satanGateway` (`jailLib.gatewayClient`); jailed-pi, jailed-pi-research, jailed-shell, jailed-claude on `piGateway` (subagents `["pi" "claude"]`); harness on `satanGateway`; `satanGptelJailOptions` forwards SATAN_MODEL, SATAN_BUDGET_TOKENS, SATAN_MAX_BUDGET_TOKENS only. Removed `apiKeyJailOptions`, both `useOpEnv`/`passApiKeysFromEnv` pairs, jailed-opencode, jailed-dirge, the `"dirge"` subagent, the SATAN_PROVIDER forward.
- Probe strings live in one binding, `harnessJailProbes` (the I1 sweep excludes it by name). `checks.x86_64-linux.harness-jail-profile` (`harnessJailProfile`) asserts them over the built outer + inner launchers; `just check-jails` builds it.
- Red first: against the pre-change jail the check failed with `harness-jail-profile: outer launcher execs no inner jailed-satan-gptel-harness (not a gateway wrapper?)`.
- VA-1 negative control, on the green tree (each reverted by hand, `diff` against a green copy empty, `just check-jails` green after):
  1. Added `(try-fwd-env "OPENROUTER_API_KEY")` to `satanGptelJailOptions` -> `harness-jail-profile: inner launcher must not contain 'API_KEY'`.
  2. Removed `(try-fwd-env "SATAN_MAX_BUDGET_TOKENS")` -> `harness-jail-profile: inner launcher must contain '--setenv SATAN_MAX_BUDGET_TOKENS "${SATAN_MAX_BUDGET_TOKENS}"'`.
- VA-2: `nix build` of jailed-pi, jailed-pi-research, jailed-shell, jailed-claude, satan-jailed-gptel-harness succeeds (Nix ruff gate passes on PHASE-01 harness code); `nix flake show` lists `checks.x86_64-linux.harness-jail-profile` and no jailed-opencode/jailed-dirge; darwin evaluates.
- `SATAN_TEST_ALLOW_NO_DB=1 just check`: ert 1367/1374, 7 skipped (same as baseline); Python 55 OK. `just lint` clean; `alejandra --check flake.nix` clean.

### Learned
- In a Nix `"…"` string, a bash `${X}` probe is `\${X}`; reading the check's generated `buildCommand` (`nix derivation show`) confirms the probe text before trusting a green.
- Absent-probes must guard the file first: `grep` on a missing file exits 2, which an `if grep` reads as "absent". The inner-launcher extraction fails loudly before any `must_not` runs.

## PHASE-07 execution (2026-10-18, in-session with the user)

- EX-1: user issued `llm-gateway issue satan --models deepseek-flash --budget 20 --out ~/.config/llm-gateway/keys/satan` ($20 confirmed by the user).
- EX-2: user pushed satan (main @ 7ee74c2) and relocked flakes (satan 7ee74c2, agents 8b0206dd; the user's update also moved other inputs). Agent edited `features/satan/patcher.nix` (dropped opBin/opAccount/apiKeyRefs; module default `{}` also drops the `op read` ExecStartPre) and `SATAN.md` (secrets → gateway keys; patcher row; removed the argv-key and SATAN_MAX_BUDGET_TOKENS known gaps). Committed flakes df07c800 with path-limited commit; `agents/gateway.nix` and the other session's staged `emacs/emacs.nix` untouched. User ran home-switch.
- EX-3: `~/.config/satan-patcher/policy.toml` defaults → `llm-gateway` / `deepseek-flash`; `[tag."cheap+code"]` removed.
- VH-1: flake-check probes re-run by hand against `readlink -f ~/.nix-profile/bin/jailed-satan-gptel-harness` (outer k374j1k1…, inner 0kkwwd8b…): all pass; launcher reads `keys/satan`.
- VH-2: user ran satan-tick on today's broker; runs 20261018T125910-tick-agent-f351e0 and 20261018T125926-tick-pulse-952f23 both `done`. `llm-gateway list`: satan spent $0.0187 of $20.
- VH-3: satan-patcher restarted 12:52 active, no ExecStartPre. Job execution not exercised (ISS-038/039).
- Observed: today's broker still runs `satan-credential` pre-spawn, so a 1Password prompt appears per run (tick-agent via satan-run); dismissing it fails the run (likely cause of the 08:16 motd / 09:16 morning failures). Expected until PHASE-05 removes the credential path.
- QUE-004 answered by the flakes session (flakes:DEC-074); body now also cites flakes:SPEC-001 (LLM gateway spec).

## PHASE-03 execution (refused launch typed; frontiers commit on `ready`)

### Done
- Refusal: a child that dies before `ready` without an `error`, with the run still `running`, ends `spawn_failed`; a `broker spawn-failed` audit event carries `(:process-status :code :stderr tail<=2KiB)`, then the normal failure path runs (`satan-broker--record-launch-refusal`, `--stderr-tail`).
- Frontiers commit once, on the first `ready` (`satan-broker--on-ready` -> `--commit-frontiers`, guarded by the new `ready` run slot, set before the commit: RV-023 F-18), from perceive's snapshots. Ingest heads are snapshotted at perceive (`satan-ingest-cursor-heads`; `advance` takes HEADS, max(current, snapshot)).
- Pre-spawn commits removed from `--spawn`; sentinel wrapper extracted as `--wrap-sentinel`, `unwind-protect` so finalize always runs (also fixes a latent strand when the stderr.log write fails).
- CONSUME diagram fixed in `docs/perceptual-design.md`; memories `mem.fact.satan.ingest-cursor-store` and `mem.fact.satan.perceive-consume-seam` updated.
- `credential-refs` slot kept; PHASE-05 EX-2 deletes it.

### Learned
- Stale `satan/*.elc` from a host compile give a false red on single-file batch runs unless `load-prefer-newer` is set (`dev/satan-test.el` handles it).
- The stderr-pipe race (R1) did not appear in 80 runs incl. 8-way load; no drain added. Revisit if a production refusal shows empty `:stderr`.
- Isolated `satan-broker-test.el` fails `run-emits-one-tick-row-outcome-spawned` (`credential_unavailable`): pre-existing at HEAD, credential-stub order dependence; gone with PHASE-05.
- The test DB at 127.0.0.1:54322 was reachable despite podman being down: only 7 tests skip, not ~140.

## PHASE-04 execution (keyless patch path)

### Done
- Patch runner and pi adapter resolve, hold and scrub no key. `satan-patch-runner--queue-ready-p` now means "a job is queued" (peek kept; error and empty return nil). The `credential_deferred patch` journal line, `--credential-warnings` and `--with-warnings` are gone; runner no longer requires `satan-credential` or `satan-announce`.
- Adapter child inherits `process-environment` unchanged; INPUT `:env` is ignored. `satan-patch-adapter-pi-api-key-vars` deleted.
- VT-1 `satan-patch-runner/ready-queue-runs-without-credentials`; VT-2 `satan-patch-adapter-pi/child-env-is-process-environment`. Peek-error and lost-claim tests rewritten without the credential fixture (`peek-error-claims-nothing`, `lost-claim-race-returns-nil`).
- Suite 1388 -> 1384 ran, 7 skipped throughout; runner DB tests ran.

### Learned
- The naive "child env has no refs" test is vacuous under the harness scrub. Real reds: `plist-member :env` on the tick's INPUT, and an ignored `:env` sentinel in the adapter test.
- The VA-1 sweep pattern `with-warnings` matched an unrelated local (`adapter-with-warnings`, renamed `noop-adapter-result`). Anchor sweep patterns.
- Runner `--with-fixture` now relies on the `dev/satan-test.el` env scrub until PHASE-05 removes the credential module.

### Open (for later phases)
- PHASE-05: `dev/satan-test.el` (~100-106) credential nil-backend binding and scrub; `satan/test/satan-credential-fixture.el` still used by the broker test.
- PHASE-06: `docs/patch/handover.md:97,202` and `docs/refactor/T8-pi-adapter-keys.md` still name `api-key-vars`.
