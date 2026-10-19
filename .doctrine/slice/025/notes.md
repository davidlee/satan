# Notes SL-025: Patch lanes end to end: self-edit and tick jobs through the runner, scoped per mode

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-19 · ready (plan materialised, PHASE-01 next) · b86b698

### Produced
- scope + research round (research/research.md, raw/{governance,code-map}.md; gitignored) — fceaf2c; baseline restamped after CHR-017 row correction — 2ac7137
- design run locked (rev 35): design.md §1-7; DEC-068, DEC-069 — 7a1b653
- RV-031 (GPT gpt-6-sol design review): 7 findings fix-now, integrated; pass concluded; findings answered, not raiser-verified — 5e3606d, 7a1b653
- plan.toml/plan.md, 5 phases; phase sheets materialised — 2ac7137, 0bf2ce0, f8049d9
- minted: IMP-044, RSK-019 (accepted), IDE-011
- ISS-046 body written — 000d889, e6ab173

### Learned
- mem.fact.doctrine.governance-edges-invalidate-confirmation — slice links during a design run void governance-confirmed
- mem.fact.doctrine.review-amend-replaces-response — b86b698
- runner is a store build (CHR-017 done): malebolge code and runner.nix deploy together at one home switch (design §4.6, RV-031 F-1)
- room base carries git/bash/coreutils (oubliette vm/room.nix:7-9) → satan-corpus toolsPackage null

### Open
- mem.fact.satan.patch-job-contract — stale; corrected in PHASE-02 (EX-4)
- SPEC-004 + ADR-017 ledger rows 1, 9 — via a REV at SL-025 reconcile, after SL-023's REV-007
- ISS-028 — harness jail reach-around for self-edit-mech; risk only
- ISS-046 — closes at SL-025 close

## PHASE-01 — runner mode scope (VA-1)

M = `/home/david/dev/malebolge`, base `13500bd`, uncommitted delta (orchestrator commits).
`just check` in M, 2026-10-19: format clean, `eslint . --max-warnings 0` zero warnings,
48 test files / 1276 tests passed (was 1246), lines 98% (2210/2255; gate 85%), exit 0.
`policy.ts` unchanged (`git diff --stat` empty); `grep knownMode src test` empty.
A1 applied: `"*"` as a list member is refused on both `repos` and `allowed_paths`.

## PHASE-02 — Emacs stamps the acting mode (VA-1)

This repo, HEAD `74ae9af`, uncommitted delta (orchestrator commits):
`satan/satan-tools-patch.el`, `satan/test/satan-tools-patch-test.el`, memory items dir.
`just check` (plain), 2026-10-19: ert 1309 ran, 1305 as expected, 0 unexpected,
4 skipped (same four as PHASE-01 baseline); luau ok; python harness 55 OK; exit 0.
Byte-compile of `satan-tools-patch.el` (temp .elc): no warnings after fixing one docstring width.
EX-3 read as tracked code outside `.doctrine/` (history citations stay):
- `git grep -n satan-tools-patch-modes -- . ':!.doctrine'` -> empty (rc 1)
- control `git grep -n 'defun satan-tools-patch--submit-fields' -- satan` -> `satan/satan-tools-patch.el:43`
- `grep -rIn satan-tools-patch-modes ~/.config/emacs --exclude-dir=.git` -> empty (rc 1)
- control `grep -n 'use-package satan' ~/.config/emacs/apps/dl-satan.el` -> `15:  (use-package satan`
Memory corrected: `mem.fact.satan.patch-job-contract` (new title: "patch_job_create: repo is a runner
name, mode is the acting run mode, scope is the runner's"); not verified: dirty tree.
Paths changed by `memory edit`: `.doctrine/memory/items/mem_01a0ae3334d77601b434d10108d73464/{memory.md,memory.toml}` only (no index).

## PHASE-03 — room holds satan and satan-corpus (VA-1)

F = `/srv/fleet`, base `f5fcecc`, uncommitted delta (orchestrator commits). EN-1: `just check` at base, exit 0.
Staged (A5, not committed): `targets/satan.nix` (toolsPackage "dev-tools"), `targets/satan-corpus.nix` (toolsPackage null).
Modified: `flake.nix` (+15: inputs satan [follows nixpkgs, doctrine], satan-corpus [git+ssh, follows nixpkgs]; targetNames appended), `flake.lock`.
Lock (`nix flake lock`, BatchMode ssh, rc 0): root inputs `changed: []`, `added: ["satan","satan-corpus"]`.
satan rev `cc26eeb53df8004ece5fcdfe7a7bc502ccc1b8c8` (origin/main pin, design §7); satan-corpus `git`, `ssh://git@github.com/davidlee/satan-corpus`, rev `21b64ead5be1ab6a8dc74ddf039bf85d6db6915e`.
No path/file: sources (jq guard true). Follows: satan.nixpkgs=["nixpkgs"], satan.doctrine=["doctrine"], satan-corpus.nixpkgs=["nixpkgs"].
Every pre-existing `locked` object survives unchanged (0 missing); the 84 deleted diff lines are node renumbering/reordering.
Eval probe: `.#roomImages.drvPath` `4625lij9…` -> `s3s5lj3lr5y0qx132nvx6q219skgg5v0-capsule-room-images.drv`; `nix-store -qR | grep satan-dev-tools` -> `68jihp5lca7vnn8qwd0rnd54xpgb33yg-satan-dev-tools.drv`. toolsPackage=null accepted (S3 not hit). No build.
`just check` in F: parse ok, alejandra clean, exit 0. `git status --short`: `M flake.lock`, `M flake.nix`, `A targets/satan-corpus.nix`, `A targets/satan.nix`.
EX-4/VH-1 pending: user system switch in ~/flakes + room reboot.
Committed F `f23f469`. Post-charter (driver, with user): satan pushed; F `0a8c82d` re-locked satan at `5eee5c8`;
F `8e3cba2` adds `satan.inputs.goad.follows = "goad"` and bumps F's goad `a64e310` -> `04147ca` (satan's pin, goad origin/main;
without the bump the follows would downgrade satan's goad by 2 commits). Lock back to 313 nodes; root changes vs `f23f469`: goad, satan only.
Correction to the charter hand-back: ~/flakes reads F via `git+ssh` (GitHub), not git+file — F must be pushed and `nix flake update fleet` run in H.
EX-4/VH-1: user switched H, rebooted room assistant, confirmed `/work/satan`, `/work/satan-corpus`, goad-walk clone + quarantine intact (2026-10-19). PHASE-03 completed.

## PHASE-04 — cutover (driver, with user, 2026-10-19)

- EX-1 / VA-1: H `338beea1` — `features/satan/runner.nix` (`roomRepo` helper, 15 repos: doctrine `edge`, nix-config at `~`; modes self-edit-mech, self-edit-mind, tick-agent computed via `lib.subtractLists`, interactive `"*"`; `mode.fix` dropped; header comment) and `SATAN.md` (§ Modes and their scope; smoke is `interactive`). `just home-build` ok; rendered config.toml: 4 modes with §4.3 scopes, 15 repos, `enabled = true`, no mode.fix.
- EX-2 / VH-1: drain query before the switch: jobs `promoted|1`, `rejected|3`; queued/preparing 0.
- EX-3 / VH-2: user `just home-switch` + restart 18:15:46; unit active; ExecStart store build `wxhqgy5v…-satan-runner-0.0.0` contains `withinModeScope`; live config.toml has the 4 `[mode.*]`; no `refusing to start`.
- EX-4: C `b2bae94` (after the restart) — the three lane prompts drop `mode`/`checks`, `repo` is a runner name, each states its mode's scope and the `invalid_request` refusal; `tools/patch_job_create.md` drops `mode`, says the job runs under the caller's mode. Beyond §4.5: self-edit-mech's checks advice was stale (`SATAN_DB_HOST` prefix, "exits 0 whatever happens") — replaced by "tell the agent to run `just check`, report counts; `SATAN_TEST_ALLOW_NO_DB=1` only if the test DBs are unreachable, and say so".
- User filled the new room clones `/work/satan`, `/work/satan-corpus` by `capsule assistant push` per `/srv/fleet/PROVISION.md`.
- H `flake.lock` (user's `nix flake update fleet`) left uncommitted for the user.
- EX-5 / VH-3: user restarted Emacs; `satan-tools-patch.elc` 18:17 (newer than .el); `satan-tools-patch-modes` unbound; live `patch_job_create` `:args-schema` keys: directive repo allowed_paths base_ref tags source context — no mode.
