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

## PHASE-05 execution (credential surface retired)

### Done
- Baseline (DB at 127.0.0.1:54322 reachable): ert 1384 ran, 1378 passed, 6 skipped (the sheet said 7); Python 55 OK.
- `satan-broker.el`: dropped the `satan-credential` require, `provider-key-vars`, `--key-var`, `--evict-on-auth` (and its `--finalize` call), the credential-policy section (`satan-credential-escalate-after`, `satan-run-attended`, `--credential-streak-age`, `--credential-policy`), `--acquire`, `--write-credential-deferred-run`, and the `:deferred`/`:unavailable` gate arms. The busy arm tests only `satan-run--spawn-running`. `--streak-transparent-reasons` is `("session_blocked" "run_busy")`. `--spawn (mode prepare dir)`; child env = `SATAN_RUN_*` + `satan-env` (`SATAN_MODEL`/`_BUDGET_TOKENS`/`_MAX_BUDGET_TOKENS`) + harness `:env` + `(default-value 'process-environment)`. No `SATAN_PROVIDER`, no scrub. `satan-broker--spawn` not reindented (CHR-009).
- OQ-1 (orchestrator): `satan-run-attended` deleted, along with its binding in `satan-run` (`satan.el`) and VT-17.
- `satan-run.el`: `credential-refs` slot gone. `satan-mode.el`: `satan-profiles` = `((deepseek-flash . (:model "deepseek-flash")))`, docstring rewritten; `--check-credential-keys` and both `:credential-policy 'prompt` lines gone.
- Deleted `satan-credential.el`, `satan-credential-test.el` (18 tests) and `satan-credential-fixture.el`. `dev/satan-test.el` lost the require, the nil-backend binding and the env scrub.
- Tests: VT-1 `satan-broker/child-env-is-global-env-plus-satan-vars` (also covers ISS-037; `base-env-ignores-buffer-local-env` deleted). VT-2 `satan-mode/profiles-carry-model-only` (shape: every shipped profile's keys are exactly `(:model)`, `deepseek-flash` present, no registered mode has `:provider`/`:credential-*`). `profile-merges-under-mode-keys` replaces the credential-key merge test. `done-run-ends-the-failure-streak` keeps the third block of `done-runs-end-both-streaks`; helpers renamed `--with-streak-runs`/`--streak-id`. `session-blocked-transparent-to-failure-streak` lost its `credential_deferred` row and gained an A2 block: a historic `credential_deferred` now ends the streak. Error-class fixture reads `LLM_GATEWAY_KEY not set`. Python `test_stray_legacy_provider_vars_are_ignored` deleted (VA-1; outside EX-3's file list).
- Reds: VT-1 gave wrong-number-of-arguments at the 3-arg call. A scratch 4-arg variant (not committed) failed on `SATAN_PROVIDER=openrouter` after the positive `SATAN_*` asserts passed. A buffer-local-base variant failed on `SATAN_TEST_BUFFER_LEAK`. VT-2 failed with `(deepseek-flash (:provider :model))`; with the profile fixed, it failed again on `("motd" :credential-policy)`.
- After: `just check` exit 0 with the DB live: ert 1346 ran, 1340 passed, 6 skipped (-38 = 18 credential + 19 broker net + 1 mode net); Python 54 OK; `just lint` clean.
- Run in isolation, `run-emits-one-tick-row-outcome-spawned` now passes: the order dependence is gone. The isolated `^satan-broker/` run passes 59/59.
- VA-1 `rg -n '_API_KEY|op://|op run|satan-credential' satan/ dev/ flake.nix` -> `flake.nix:297:          outerAbsent = ["op run"];` only. VA-2 `rg 'llm-gateway/keys|127.0.0.1:4000' satan/` -> no hits; `rg -n 'LLM_GATEWAY_URL|/run/.*llm-gateway' satan/*.el` -> no hits.

### Learned
- `(require 'satan)` in `satan-broker-test.el` is load-bearing beyond its old "attended flag" comment: it registers every tool module morning names (`manifest-tools-shape` fails without it in an isolated run). The full suite hides this, because another file loads `satan` first.
- A second `--spawn` stub, outside `--gate-run`, in `run-emits-one-tick-row-outcome-spawned`, still had a 4-arg lambda. Only the isolated broker run caught it: `rg '_cred'` is the sweep.
- `should-not (list …)` is always non-nil: wrap a diagnostic payload as `(and COND (list …))`.

### Open
- `satan-run-id-time` (`satan-run.el`) has no production caller now (only `--credential-streak-age` used it); only its VT-28 test reads it. Candidate for deletion.
- `mem.fact.satan.broker-test-credential-stub-order-dependence` is obsolete; retire or rewrite.
- The stale `satan/satan-credential.elc` from a host compile is still on disk (untracked, gitignored).

## PHASE-06 execution (docs: the gateway story)

### Done
- T1 baseline sweeps at 55f9507 matched the sheet's hit list. One sheet claim was wrong: the governance file map is rooted at `~/dev/satan/satan/`, so `harness/...` rows are correct paths; only the providers row's content was stale.
- `docs/governance.md`: § Key resolution (op://) replaced by § Model access: the LLM gateway (two-client table naming `keys/satan` and `keys/pi`; launcher passes `LLM_GATEWAY_KEY` by fd and sets `LLM_GATEWAY_URL`; broker reads no key file or gateway path; refused launch = `spawn_failed` + `broker spawn-failed` with status, code, 2 KiB stderr tail; gateway error classes; `llm-gateway issue/list`; DEC-043 budgets as insurance, figures cited to `~/flakes/SATAN.md` § Secrets; the `harness-jail-profile` guard; one historical line). Also rewritten: § Jail and runtime governance (gateway key, not provider key; network reach), file-map rows for broker, patch adapter, harness providers; profiles carry `:model` only; tick default profile; spawn-contract paragraph (no key; SPEC-003 still says "key" until reconcile); open thread 5 (no provider selector); thread 12's "op popup count" marked obsolete; `just check-jails` added to Operations.
- `docs/architecture.md`: gateway arrow in the centre-of-gravity diagram; Harness adapter paragraph (gateway, satan/pi split, no provider key, `spawn_failed`), pointing to governance for detail.
- `docs/patch/handover.md`: frontmatter `status: historical`, description marked as a May-2026 record; top banner with current state (gateway, satan/pi split, adapter keyless, `api-key-vars` deleted); inline markers on § Op-cache path port and open item 3.
- `docs/patch/plan.md`: model-access note under the intro (gateway, satan/pi split); §2.2 jailed-pi paragraph rewritten; risk 2 marked historical/resolved.
- `docs/refactor/T8-pi-adapter-keys.md`: status `abandoned` (the refactor plan's enum has no `obsolete`), banner, "Current shape" heading renamed historical; `docs/refactor/plan.md` row and open question 5 updated.
- `docs/review/`: identical historical banner on 04, 05, 06, 12, 99, THEMES; CODE_REVIEW's frozen note extended.
- Jail network reach verified, not assumed: `specDev` and `research` profiles carry jail.nix `network` (shared host network); `offline` has none (`~/flakes` 8b0206dd `agents/jailed-agents.nix` `profileOptions`). The gateway is a loopback service, not a network filter.
- Verify: `just check` exit 0, DB live (ert 1346 ran, 1340 passed, 6 skipped; Python 54 OK). `just check-jails` exit 0.

### Learned
- Sweep hygiene again: the new guard sentence named `SATAN_PROVIDER` as asserted-absent, tripping the secondary sweep; reworded to "no provider selector".

### Open
- governance.md § Tick mode family still describes pre-SL-022 tick defaults (3000 tokens / 4 calls / 30 s, three-tool surface); `satan-tick.el` registers 100000 / 10 / 120 s and a wider tool list. Not gateway-related; left for a docs chore.

## PHASE-08 execution (2026-10-18, in-session with the user)

- EX-1: user pushed satan (main = origin/main @ 5c0e2d9) and restarted Emacs onto it.
- EX-2: user removed `satan-credential-function` (apps/dl-satan.el) and `my/satan-credential` + tests (lisp/dl-secret.el, lisp/test/dl-secret-test.el) in ~/.config/emacs; its `just check` green; user committed. Agent then removed the leftover "1Password backend" comment in apps/dl-satan.el at the user's request (emacs ceb3062, path-limited commit).
- VH-4: running Emacs (uptime ~6 min): `satan-credential-function` unbound, feature `satan-credential` not loaded, no satan-credential / void-variable lines in *Messages* or *Warnings*. A native-comp warning `dl-secret.el:59 notifications-notify not known to be defined` predates the edit (function-body `require`); not SL-022.
- VH-1: `satan-run motd` → 20261018T142127-motd-280fae `done`, no 1Password prompt path left in the broker. `llm-gateway list`: satan spent $0.0515 of $20 (was $0.0187 at PHASE-07).
- VH-2: during a live tick, argv of the launcher (jailed-satan-gptel-harness, pid 3767857) and the harness python (pid 3768154) scanned for the literal key: absent. bwrap is exec'd in the launcher's pid; its argv is covered by the flake check's `argvAbsent` probe (PHASE-07 VH-1 on the deployed launcher).
- VH-3: keys/satan renamed aside for one tick → 20261018T143609-tick-pulse-a7d140.FAILED, final.json reason `spawn_failed`; transcript has `broker spawn-failed` {process-status exit, code 1, stderr = launcher's "gateway key … is missing, empty or unreadable" message}; key restored (mode 600).
- Observed: the launcher's refusal hint names the alias `satan-gptel-harness` (the jail name), not the issued alias `satan` — cosmetic, owned by ~/flakes/agents.
