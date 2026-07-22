# Notes SL-012: Extract SATAN to standalone Elisp package

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## 2026-07-10 — design + plan locked, external review integrated

- Design adversarial pass (internal): 9 findings integrated (coupling facts,
  .emacs.d flake teardown, test-runner behaviour, hook symlink, SL-011 ordering
  → D9, memory staleness follow-up).
- Plan: 4 phases, copy-then-cutover (rationale in plan.md).
- External codex review on **RV-010**: 8 findings (1 blocker — Justfile `-L
  satan` hardcode; 5 major; 2 minor), all disposed `fixed`, all verified by
  raiser; ledger `done`. Key deltas: consumer-based decouple scope (13+2
  files), runner anchored off `user-emacs-directory`, git-add-before-flake-eval
  gate, EN-1 waiver requires explicit user /consult approval, PHASE-04 EX-8
  (Justfile), PHASE-02 EX-6 (timeout(1) dep).
- Workflow memory recorded: `mem.pattern.doctrine.codex-external-review`.
- SL-011 status at plan time: `ready` (not closed) — PHASE-01 EN-1 gates on it.

## 2026-07-12 — PHASE-01 executed; boundary crossing exposed a design gap

**Context state:** SL-011 closed (EN-1 ✓). DB up (supabase 127.0.0.1:54322).
Dispatch dropped — executing **inline** (no worktree), writing into
`/workspace/satan` (a separate git repo, user-confirmed writable). PHASE-01
`in_progress`, slice `started`.

### What landed (committed to the satan repo — real, keep)
- Full D1 tree copied verbatim (old `dl-satan-*` names), manifest-exact:
  `satan/*.el` ×65, `test/` ×62, harness ×9, bin ×4, memory/migrations ×7,
  protocol ×1, patterns.eld; `docs/satan/**` → `docs/**` (×39, flattened);
  `dev/satan-test.el` (runner); `bin/` + `tools/` linter; `justfile`.
- Scaffold `src/`/`test/` deleted; `.direnv` added to `.gitignore`.
- **`just lint` GREEN** (65/65).

### Design gap #1 (fixed in place) — linter not self-contained
`bin/elisp-locate-paren-error` depends on `tools/elisp-locate-paren-error.el`
(**absent from the D1 move table**) and hardcoded `.emacs.d` `-L` dirs. Fixed:
copied the tool `.el` into `tools/`, repointed the wrapper, dropped the dead
`-L` flags. **D1 move table is incomplete** — record at reconcile.

### Design gap #2 (THE design revision) — package self-location coupling
`just check` (ERT) = 64 fail / 39 LOADERR / 361 ran. Two config-root coupling
axes, but the design severs only one:

- **Axis 1 — `dl-notes-root`** (config module `dl-notes-paths`): 10 prod files
  hard-`require` it → 39 LOADERR cascade. **Design D4 / PHASE-03 owns this.** ✓
- **Axis 2 — `user-emacs-directory`** (package assumes its *own* code/data live
  under the config root): **NOT in the design.** Root cause proven:
  `user-emacs-directory` = `~/.emacs.d` = `/home/david/.emacs.d`, but the repo
  is `/workspace/.emacs.d` — different paths; `migrate-directory` resolved to a
  non-existent dir (`dir-exists=nil`) → test DBs never migrated → 64 failures
  (`function memory_show_trace does not exist`). **This breaks the SHIPPED
  package too:** PHASE-04 deletes `~/.emacs.d/satan/`, dangling every such path.

  The design half-saw this — RV-010 **F-1** noted `user-emacs-directory` is
  wrong in batch, but scoped the fix to the **test runner only** (done). It is
  endemic in **5 production defcustoms + 1 hardcode**:
  - `dl-satan-memory-migrate.el:26` — `satan/memory/migrations/`
  - `dl-satan-pattern.el:44` — `satan/patterns.eld`
  - `dl-satan-context.el:535` — `satan` dir
  - `dl-satan-tools-docs.el:35,129` — doc-corpus roots
  - `dl-satan-broker.el:56` — repo root
  - `dl-satan-tools-vcs.el:24` — hardcoded `~/.emacs.d/`

### User decision (2026-07-12) — do it properly
"If it's to be a real package, it needs its own identity and resolution."
Scope: a **package "know thyself" root convention** — a documented
`satan--root` (resolved from `load-file-name`, canonical ELPA self-location)
that all package path resolution anchors to. Not a minimal spot-fix. This is a
**design revision** (new decision, e.g. D4b/D10, extending D4 to *both*
config-root axes), cascading to a **plan revision** (owning phase + green
invariant). Routing agreed: `/design` → `/plan` → phase-sheet update.

### Plan tension to resolve in the plan revision
PHASE-01 (and cascading PHASE-02) exit gate "**full ERT green**" is
**unsatisfiable** for a copy-verbatim / defer-decouple phase — green requires
both axes severed. Re-cut the green bar to: *lint green + suite loads & runs
across the boundary + suites not blocked by the two axes pass; coupling-blocked
suites known-red until the decouple phase*. Full green only from the decouple
phase onward.

### Open sub-decisions for the design/plan agent
1. **Axis-2 home:** fold into PHASE-03 (rename it "Decouple config-root
   assumptions", cover both axes) — my recommendation — vs a new dedicated
   phase. Both axes are semantic and belong *after* the rename (PHASE-02) so the
   sweep doesn't rewrite new call sites.
2. **`dl-secret-test.el`** requires `dl-secret` (a config-owned module, not
   SATAN). It shouldn't have moved. Recommend dropping it from the package
   (dl-secret stays config; satan only soft-deps `my/op-read-env`). Small
   scope/manifest nit, not design-tier.
3. `satan--root` naming/convention: confirm `satan--root` (private) vs a public
   `satan-lisp-directory`; document the convention so future modules use it.

### Dual-presence window (PHASE-01 EX-5)
Copy-not-move: `.emacs.d/satan/` and `/workspace/satan/satan/` now co-exist.
**No edits to the `.emacs.d` copy** until PHASE-04 cutover, or edits must be
replayed into the package (PHASE-04 EN-2 audits the window closed).

## PHASE-01 execution results (2026-07-12, resumed)

Re-cut gate run, `SATAN_DB_HOST=127.0.0.1 just check` in `/workspace/satan`
(supabase up at `127.0.0.1:54322`). Exit 0.

- **Lint**: 65/65 `{"ok":true}` (satan/*.el). GREEN.
- **ERT**: `Ran 361 tests, 294 as expected, 64 unexpected, 3 skipped`.
- **All 64 unexpected are coupling-blocked** (PHASE-03), zero boundary
  regressions:
  - 63 = **Class B** self-location (unmigrated test DBs — migration dir anchored
    to `user-emacs-directory`): memory-store/renormalize/migrate (28),
    intervention (16), pattern (14), patch-store (8), trace-ex2 (1 DB-write).
  - 1 = **Class A** dl-notes cascade: `trace-ex2` also pulls `dl-satan-context`
    which hard-`require`s `dl-notes-paths` (file-missing). Same PHASE-03 fix.
  - Histogram by module: memory 28, intervention 16, pattern 14, patch 8, trace 1.
  - **0 failures outside the 5 DB-backed modules** → non-coupling suites
    (resonance, sensor, trace-stage, context-render, tools, protocol) all pass.
    Re-cut VA-1 satisfied.
- 3 skipped = `memory-grammar/db-sync-*` (`skip-unless`, expected).
- Full log: scratchpad `gate.log` (disposable).

**T13** — `satan/test/dl-secret-test.el` dropped (`git rm`); it `require`d the
config-owned `dl-secret`. Test dir 62 → 61.

**T8 (flake gptel harness)** — re-enabled the 3 commented blocks in
`/workspace/satan/flake.nix`: `satanGptelHarness` (mkDerivation from
`./satan/harness`), `satanGptelJailOptions`, `satan-jailed-gptel-harness`
(exported via `jailPkgs`→`packages`). Diff proven **pure comment-toggle**
(every changed line token-identical modulo indent + `#`). Src `./satan/harness`
present + tracked (9 files). Config-jail defs (jailed-pi/claude/opencode/dirge)
left intact per user ownership.
- **VA-3 live `nix` eval NOT runnable in-sandbox** — no `nix` binary present
  (same class as PHASE-04 host-only steps). Static half done (pure-toggle proof
  + src-exists + tracked). **Live eval host-deferred.**

**T10 diff-audit (VA-4)** — dest tree vs D1 manifest: all counts match
(satan/*.el 65, test 61, harness 9, bin 4, memory 7, protocol 1, patterns.eld 1,
docs 39, locate-paren 1, satan-test 1). GREEN.

**`.envrc` note (reconcile/PHASE-04):** satan `.envrc` = `JAIL_WORKSPACE_DEPS`
(notes/.emacs.d/flakes) + `use flake . --impure`; lacks the config `.envrc`'s
`DOCKER_HOST`. Flag when wiring host consumer.

## Carried to PHASE-04 host / reconcile (not runnable in sandbox)
- **VA-3 live `nix` flake eval** — `nix eval --impure /workspace/satan#packages.x86_64-linux.satan-jailed-gptel-harness` (+ `satan-gptel-harness` builds from `./satan/harness`). Static-verified in PHASE-01 (pure comment-toggle, src tracked); live eval runs on host. User decision 2026-07-12.
- **Untracked memory** `mem.fact.satan.package-self-location-coupling` — git-add at reconcile.
- **`.envrc` DOCKER_HOST** gap vs config `.envrc` — resolve when wiring host consumer.

## PHASE-02 phase-plan: rename-collision design gap (resolved /consult 2026-07-12)
Blunt `my/satan-* → satan-*` (D3) hard-collides with same-base `dl-satan-*` lib
fns for exactly 2 symbols (both `dl-satan-memory-migrate.el`, impl+wrapper): the
interactive wrapper defun would clobber the tested lib fn. Rule appended to D3:
lib keeps `satan-X`; colliding command → verb-first name.
- `my/satan-memory-renormalize` → `satan-renormalize-memory`
- `my/satan-memory-migrate-status` → `satan-show-migrate-status`
Wrappers have no external callers; blast radius = 2 defuns + docstrings. Other 20
`my/satan-*` commands map cleanly. EX-2/EX-3 gates unchanged.
Surface measured: `dl-satan-` ~10719 hits (4128 prod/65 files, 5926 test/61,
655 docs, 2 bin, 2 harness) + 65+61+1 file renames; `my/satan-` 87/25 files.

## PHASE-02 executed (2026-07-12) — green
Sweep + 125 file renames + entry headers committed satan `3a31590`. Lint 65/65;
byte-compile re-cut VA-2 (25 clean / 40 blocked ONLY on dl-notes-paths, zero
rename-induced errors — pre-existing warnings verified against original);
ERT 361/64/3 identical to PHASE-01 (no regression). EX-1..6 met. Collision rule
(D3 delta) applied: satan-renormalize-memory, satan-show-migrate-status.
VA-2 re-cut into plan.toml (corollary of D10). PHASE-04 carry: post-commit
install-hint comment still cites ~/.emacs.d/satan.

## PHASE-03 executed (2026-07-12) — GREEN (satan a4fc0c0)

Both config-root axes severed. New leaf `satan/satan-custom.el` (satan--root
defconst + satan-notes-root/satan-journal-today defcustoms + satan-notes-path/
satan-notes-today helpers; owns `(defgroup satan …)`). EX-1..7 met; VT-1/VT-2
green (9 tests, satan-custom-test.el). `SATAN_DB_HOST=127.0.0.1 just check`
**exit 0 — 1033 run, 1017 pass, 0 unexpected, 16 skipped** (was 361/64 — the 40
LOADERR files now load). VA-1 full green; VA-2/VA-3 rg gates empty.

### Design/plan gaps found (reconcile carries)
- **F-1 — 3rd hidden coupling, `dl-denote-journal`.** context.el + tools-org.el
  hard-`require`'d it (config-owned, `~/.emacs.d/org/`, provider of
  `my/journal--*`). Plan decouple list named only dl-notes-paths. D4's journal
  design dictated the fix (today→`satan-journal-today` injection; weekly→soft
  `declare-function`). Both requires dropped. **Plan file-list under-counted.**
- **F-2 — latent missing `(require 'calendar)`** in satan-memory-evidence.el;
  only ever loaded transitively via dl-denote-journal→denote→calendar. Dropping
  F-1 exposed 29 `calendar-absolute-from-gregorian` void-function failures.
  Added the require (package self-containment, same class as PHASE-01 gap#1).
- **F-3 — test-side self-location bug:** satan-pattern-test.el hardcoded
  `user-emacs-directory` for patterns.eld → repointed to `satan-pattern-file`.
  (satan-tools-docs-test.el also references user-emacs-directory but passes —
  low-pri, flagged.)
- **F-4 — STALE .elc trap:** a manual batch-byte-compile left 66 `.elc` that
  `require` loaded over edited `.el`, masking F-2. `rm satan/**/*.elc` before
  re-running; the batch runner loads `.el`, never leave stray `.elc`.

### /consult resolution (user, 2026-07-12)
- **F-5 → applied:** justfile `test` recipe gains `-L ./satan/test` so a test
  file requiring a sibling test file's **macro** (`satan-intervention-test--with-db`)
  resolves at load (fixes 2 load-order failures). Pre-existing harness gap,
  surfaced only once these tests un-blocked. **Touches the harness (PHASE-02/04
  adjacent).**
- **F-6 → corpus-guard (option a):** 7 corpus-integration tests read the
  host-only `~/notes/satan/` model-facing corpus (framing/scaffold/tick-pulse +
  tool-description `.md` under `satan-tools-descriptions-dir`), by design not in
  the package (D4/POL). Added `satan-context-test--corpus-p` helper +
  `skip-unless` (mirrors the DB skip-unless idiom) → green in sandbox (skipped)
  and host (exercised). New durable test idiom.

### PHASE-04 host carries (unchanged)
Live nix eval (VA-3); satan-git-post-commit install-hint still cites
~/.emacs.d/satan; satan `.envrc` lacks DOCKER_HOST. `.emacs.d/satan/` still
untouched (dual-presence; cutover in PHASE-04).

## PHASE-04 executed on HOST — STAGE 1 done (2026-07-12), staged with user

Host-only phase. User-approved staging: stage 1 = reversible edits + machine
gates (this pass); stage 2 = home-manager switch + delete + VH-1/2/3 with human.

**Entrance:** EN-1 ✓ (PHASE-03 green, satan a4fc0c0). EN-2 ✓ dual-presence
CLEAN — config `satan/` last edit 196676e (07-11) predates package seed b2f0da1
(07-12 00:32); working tree clean under satan/. No un-replayed edits.

**Decisions locked with user:**
- **D-A2 harness provisioning (OQ-1/EX-4):** config flake fully stripped of
  satan; jailed-satan-gptel-harness provisioned via `~/flakes` home.packages
  from the `satan` flake input → `~/.nix-profile/bin` (on broker exec-path,
  direnv-independent). `~/flakes` satan input is `path:` (local-ahead; flip to
  `github:davidlee/satan` after push).
- **D-JF:** check recipe `-L` fix + `-L ~/dev/satan/satan`; dead db-init/
  check-interactive removed; hello-satan kept (user).
- **D-DT:** doctor test rewritten in-place to renamed interface.

**Landed (3 repos):**
- config `~/.emacs.d` @ **ebe4a1e** — dl-path (D5), init.el use-package satan
  :ensure nil :demand t (D4), dl-test suite dirs, doctor + doctor-test rename,
  Justfile (EX-8), flake.nix satan strip (EX-4).
- satan `~/dev/satan` @ **012097e** — .envrc DOCKER_HOST (D10 caveat),
  post-commit install-hint path (+ user's README).
- flakes `~/flakes` @ **0fc4af97** — satan input + satan.nix home.packages +
  ExecStart repoint.

**Machine gates GREEN:**
- VA-1 `just check` 10/10 (doctor suite resolves renamed pkg via external -L).
- VA-2 config flake evals clean; package set = 7 non-satan jails, both satan
  entries gone.
- VA-3 `nix build ~/dev/satan#…satan-jailed-gptel-harness` →
  `/nix/store/npr1ra9…-jailed-satan-gptel-harness` (src ./satan/harness, ruff
  check + wrapper all pass). **Closes the PHASE-01 host-deferred VA-3 carry.**

**Corrections to prior findings:**
- satan repo DOES have origin `git@github.com:davidlee/satan.git`; local-ahead
  of origin/main (a4fc0c0 unpushed) — so `github:` input would be stale; `path:`
  correct until user pushes.
- `homeModules.satan` IS imported by `modules/home/Sleipnir.nix:34` (satan.nix
  "not imported in phase 1" comment was stale — fixed).
- `emacs.nix` a non-issue: satan never in the emacsWithPackagesFromUsePackage
  scan set {core,apps,lang,lisp,editing,completion}; satan elisp self-contained
  (subr-x + own modules). No emacs.nix / extraEmacsPackages change.

**Left untouched (user WIP, not mine):** config `flake.nix` +helix hunk (staged
only my satan hunks via filtered `git apply --cached`); satan `flake.nix`
+subagents line; `~/flakes` niri/zsh/util edits.

### STAGE 2 remaining (needs human — NOT done)
1. Re-link `~/.config/git/hooks/post-commit` → `~/dev/satan/satan/bin/…` (EX-6).
2. `home-manager switch` (VH-2).
3. Delete `~/.emacs.d/satan/` + `docs/satan/`; rg 'dl-satan-' zero outside
   .doctrine/.spec-driver/CHANGELOG (EX-5/VA-3 gate).
4. CHANGELOG entry (EX-7 — deferred to keep stage-1 honest).
5. VH-1 boot + `M-x satan-run morning`; VH-3 doctor checks; VH-2 systemd +
   test-commit hook fires segment row. NB trusted-content: satan now a checkout
   dir (untrusted) — verify no breakage.
6. Then `doctrine slice status 12 audit` → /audit → /reconcile (carries F-1..F-6
   + this stage's carries: github flip after push, stale orientation memory).

### STAGE 2 COMPLETE (host, 2026-07-12)
All Stage-2 items above done on the host. Every PHASE-04 exit + verification met.

**Host actions (VH-1/2/3, OQ-1):**
1. EX-6 post-commit hook re-linked → `~/dev/satan/satan/bin/…`; `home-manager
   switch` applied; satan systemd units start on new ExecStart (VH-2). Test commit
   fired the re-linked hook → git-activity segment row appended.
2. `~/.emacs.d/satan/` + `docs/satan/` deleted (EN-2 pre-delete diff: only
   gitignored build cruft — `dl-satan-run.elc`, 2 `__pycache__/` — no stranded
   source; docs all tracked verbatim in package).
3. VH-1 boot green: `M-x satan-run` morning ran jail→model→tool→DB end-to-end.
   VH-3 doctor SATAN checks pass on the renamed interface. OQ-1 jail mount
   resolved — binds byte-identical pre/post cutover.
4. EX-7 CHANGELOG entry landed (`cfda3ee`).

**Live regression found + fixed (D4 tilde-root, NOT in plan):** two `satan-notes-root`
consumers fed the raw `~`-prefixed root straight to a subprocess (`call-process`),
which does not expand `~`. Every other consumer wraps in `(expand-file-name
"satan/…" root)` (expands the base), so blast radius = these two only.
- satan `0452f9c` — expand `~` in `@satan` scan root before `call-process`.
- satan `14963de` — expand `~` in `notes_recent` `fd` base-directory.
Live-verified post-fix: `notes_recent` returns 3 files; tick scans `~/notes/intake`
and acts on a directive (previously bailed "nothing acted on").

**EX-5 gate closure (literal exemption `.doctrine/ .spec-driver/ CHANGELOG.md`):**
- `dev/dl-test.el:7` stale comment `dl-satan-db-host-override` → `satan-db-host-override`
  (no live binding of the old name; VA-1 already green — cosmetic drift only).
- Orphaned satan review artifacts relocated to the satan repo (`8fba96e`): the
  `review/` corpus (15 files) + root `CODE_REVIEW.md`, `CODE_REVIEW_PROMPT.{ARCHITECT,RESEARCHER}.md`.
  These reviewed now-extracted code and pointed at the deleted `docs/satan/refactor/`.
- Gate now literally zero hits outside the exempt set. Config tree clean.

**History hygiene for /audit (context, not blockers):**
- Three identical `chore: delete satan (moved to davidlee/satan)` commits
  (20200c0, a03b3de, 063f5c8) — untidy but harmless.
- A full **SL-013** slice (6 commits, `6878026`..`f081cbb`) landed interleaved in
  the config repo during the PHASE-04 window — unrelated to SL-012.

**Stage-2 delta registry (cross-repo, textual — this slice spans 3 repos):**
- config `~/.emacs.d` — `ebe4a1e` (wiring) → `cfda3ee` (CHANGELOG + dl-test fix + deletes).
- satan `~/dev/satan` — `0452f9c`, `14963de` (regressions), `8fba96e` (review relocate).
- flakes `~/flakes` — Stage-1 `0fc4af97` (satan input + satan.nix + ExecStart);
  host `home-manager switch` applied it.

Carries into /audit: F-1..F-6 (see plan RV-010) + github-input flip after
`git push` of the satan repo (`path:` correct until pushed) + stale SATAN
orientation memory (post-extraction file map).
