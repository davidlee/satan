# Notes SL-015: Corpus relocation: SATAN model-facing corpus leaves ~/notes for a standalone repo

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Pre-execution review, 2026-08-24

Adversarial read-only review of the locked design + plan + PHASE-01 sheet,
before T1. Six soft places interrogated; two cleared, four yielded defects.
Everything below is verified by independent grep or by `emacs --batch`, not by
reasoning from the design.

### Durable — survives this slice

- **`just check` cannot run from a bare shell.** The test step aborts with
  `satan-test: refusing to run batch tests against production socket; set
  SATAN_DB_HOST or SATAN_FAILOVER_TO_SYSTEM_DB` (exit 255). The devshell sets
  neither — `SATAN_DB_HOST` appears only at `flake.nix:85`, inside
  `supabaseJailOptions`. Compounding: `just lint` is *only*
  `bin/elisp-locate-paren-error` per file (`justfile:3-8`) — paren balance, no
  byte-compile, so it cannot see a missing `require` or any other load-time
  breakage — and `justfile:18-20` warns that without the test databases ~130
  tests silently skip and still report green. **"`just check` green" is not a
  meaningful gate unless the invocation is named.**
- **`~/flakes` is a consumer surface of SATAN paths, and the hardest one.**
  Home-manager renders every `~/.config` dotfile as a `/nix/store` symlink, so
  (a) the rendered file is not editable — the flake source is the edit target,
  and (b) **`grep -r` does not follow symlinks**, so a `$HOME` sweep reports
  clean over exactly these consumers (proven: `grep -rn "notes/satan"
  ~/.config/systemd/user/` → 0 hits; with `--dereference-recursive` → 2). Any
  future path-migration sweep must use `--dereference-recursive` *and* grep
  `~/flakes` sources.
- **`Persistent=true` timers fire a catch-up run immediately on start.**
  `satan-motd.timer`, `satan-morning.timer`, `wpm-archive.timer`. Any procedure
  that stops timers, changes paths, and restarts must restart **Emacs first,
  then the timers** — otherwise the catch-up run executes against stale
  defcustoms.
- **`expand-file-name` preserves a trailing slash; a fold-based join does not.**
  `(expand-file-name "satan/prompts/" "~/notes")` keeps the `/`;
  `(satan-corpus-path "prompts")` drops it. Cosmetic in SATAN today — every
  consumer normalises, including the worktree confinement guard
  (`satan-patch-worktree.el:66-70`) — but it is the same class as the two
  `~`-expansion regressions that shipped post-cutover, so any "byte-identical"
  claim over path defcustoms must normalise before diffing.
- **A recount is not a verification.** Third count correction in this slice, and
  the second one was *wrong in the opposite direction*: it counted nine rows
  correctly and mis-classified one of them. Check what a row **means**, not how
  many there are.

### Slice-specific, threaded into design/plan

- Design **§2.2b** names the `behaviour/` class (panopticon's state: external
  producer, read-only to SATAN) and puts it out of scope by ownership. **P2 and
  D1 amended** — three roots, and exactly three, because SATAN does not name a
  root it does not own. `satan-sensor-curiosity-segments-dir`,
  `satan-tools-content-dir`, `satan-tools-activity-dir` stay put.
- **D1's stated rationale was false** and is struck: the two divergent fallback
  spellings are *not* a latent trailing-slash bug — the divergence sits in the
  fallback branch, unreachable when `XDG_STATE_HOME` is set.
- **D5's premise was false**: `satan-patcher.service` carries no
  `SATAN_PATCHER_PROMPT` pin. It is a non-editable `/nix/store` symlink and
  `~/flakes/modules/home/linux/satan-patcher.nix:26-35` declares the service
  with no `systemPromptFile =`, so the daemon runs on the punted repo's own
  default (`~/dev/satan-patcher/nix/module.nix:74`). One line in the flake
  module fixes it without touching CHR-003.
- New **D9** (prose in the code repo — ~111 doc lines + 17 docstrings — is not
  part of the cutover; F2 is about *model-facing* text) and **D10** (two live
  `satan/` path expressions survive I1 by named allowlist: `satan-mcp.el:43`,
  `satan-patch-worktree.el:52`).
- New risks **R7** (`flake.nix:98` workspaceDeps — jailed *dev* agents lose
  corpus visibility; and `/workspace/satan` is already taken by `~/dev/satan` at
  `flake.nix:131`) and **R8** (`sway.nix:12` `wpm-archive` breaks silently).
- **Surface: 24 sites / 22 variables** (16 corpus + 8 state;
  `satan-self-edit-mind-roots` is one variable spanning three sites;
  `satan-prompts-dir` is a `defvar` and gets promoted).

### Cleared — do not re-investigate

- **A1 holds — the jail needs no corpus bind.** `SATAN_NOTES_RO` and
  `SATAN_HIPPOCAMPUS` are set at `flake.nix:130-139` and read **nowhere**; the
  harness opens only `bundle.json` / `manifest.json` from `SATAN_RUN_DIR`
  (`satan/harness/bundle.py:17,22`, `runloop.py:165-170`); the patch agent reads
  its system prompt broker-side and passes the contents as
  `--system-prompt <text>` (`satan-patch-adapter-pi.el:152-160`, since Pi 0.75.x
  dropped `--system-prompt-file`), so no jailed process opens a corpus path;
  `satan-attrd` has no on-disk state beyond the DB; `satan/bin/satan-run*` are
  emacsclient shims. `flake.nix:134` is the one line — `flake.nix:98` is a
  separate line and a separate problem (R7).
- **OQ-1 resolved — subtree split is fine.** `~/notes` has 36 commits total, 28
  touching `satan/`. The split runs in seconds; history is dated-snapshot
  granularity, thin but real, and no available tool improves it.
  `git filter-repo` is absent and not needed. R2 downgraded.
- **The PHASE-02 → PHASE-03 span is clean.** No expression joins a corpus path
  to a state path; the three jail binds are independent; `satan-context.el`'s
  display paths follow their roots; and `satan-broker.el:405-417` stores the
  `most-recent` symlink target **relative**, so the `runs/` move does not dangle
  it. With timers stopped at S0 there is no mid-cutover firing window — the
  hazard is at restart (see above).

## PHASE-01 (2026-08-26)

### Durable — survives this slice

- **`just check` exits 0 no matter what.** `ert-run-tests-batch` (not
  `…-and-exit`) plus `--eval`'s discarded return value. Three invocations, two
  with failures, all exit 0. **Never trust `$?` from this suite** — grep stdout
  for `unexpected`. Filed ISS-008. Together with "lint is paren-balance only"
  and "~130 tests skip silently without DBs", that is three independent ways
  this repo reports green while broken.
- **The working suite invocation on this machine** is
  `SATAN_DB_HOST=/run/postgresql/ just check` — 1026/1030 at the EN-1 baseline
  vs 892 with no DB reachable. The trailing slash is what slips past the
  production-socket guard (`equal` against the bare literal). Filed as ISS-009
  because a guard defeated by a trailing slash is a defect even when the
  bypass is convenient. **Fixing ISS-009 invalidates this invocation** — they
  have to move together.
- **One test defaults to the production database**:
  `satan-memory-grammar-test.el:23` is a grammar drift detector and reads
  `satan_memory` directly. SELECT-only, verified. Worth knowing before pointing
  the suite anywhere.
- **`getenv` returns `""`, not nil, for a set-but-empty variable** — so
  `(or (getenv "XDG_STATE_HOME") fallback)` takes the empty string. Filed
  ISS-010. Check the same shape wherever `getenv` meets `or`.
- **A count can be right and still wrong.** Fourth correction in this slice,
  and the last two were not miscounts at all: F-2 counted nine rows correctly
  and *classified* one wrongly; F-12's table was arithmetically fine and
  *temporally* wrong (it described the end state while being read as a phase
  instruction). Recounting does not verify. Ask what a row means, and when it
  is true.
- **Prove a guard fails before trusting it.** VT-3 was run against synthetic
  violations — both the single-line and multi-line spellings — and against the
  expressions it must not flag, before being accepted as passing. A guard whose
  red has never been observed is indistinguishable from a guard that cannot
  fire.

### Slice-specific

- The corpus/state split is by **ownership**, not by location: `runs/` and
  `log/wpm/` are state-class but live under the corpus root until PHASE-02
  physically moves them. PHASE-01 wires them to `satan-corpus-path`; PHASE-02
  flips them to `satan-state-path` in the same act as the `mv`. Doing it
  earlier relocates a tree ahead of its data.
- Derivation chains have a subtlety worth carrying into PHASE-02: a default
  that reads `satan-corpus-root`'s *current value* does not move when
  `satan-notes-root` is rebound, because the notes root only feeds the corpus
  root's *standard value*. Any test that rebinds a root to check propagation
  must rebind the root that is actually one link away.
- `satan-trace-dir` is the state root itself, not a subdirectory of it.

### Cleared — do not re-investigate

- All 9 corpus modules already required `satan-custom`; only the 8 state
  modules were short, 6 of them (F-3, confirmed).
- The leaf invariant (A5) held throughout — `satan-custom.el` gained no
  `require`.
- VA-1 came out empty on the first attempt and stayed empty through the T9
  refactor. The trailing-slash class (A6) is confined to exactly the 5
  predicted sites.

## PHASE-02 (2026-09-11)

### Durable — survives this slice

- **`home-manager switch` starts every enabled-but-inactive unit, changed or
  not.** Activation's `reloadSystemd` step reported `Starting units:
  satan-attrd.service, satan-morning.timer, satan-motd.timer,
  satan-tick.timer, wpm-archive.timer, wpm-daemon.service` — the exact set
  EN-2 had stopped. A stopped unit is indistinguishable from one that needs
  starting. Any cutover that quiesces writers and then rebuilds must **rebuild
  after the Emacs restart, or re-stop the timers immediately after the
  rebuild** — PHASE-03 EX-10 (`satan-patcher.nix`) hits this with a live
  corpus move in flight. This time nothing fired only because every
  `Persistent=true` window had already passed for the day.
- **The wpm TSV writer is `wpm-daemon.service`, not a waybar module.** Waybar's
  `custom/wpm` only `cat`s `$XDG_RUNTIME_DIR/wpm.json`. Stopping waybar leaves
  the writer running. (Design F1 / §5.4 S0 carry the mislabel.)
- **Every scheduled SATAN run since late August ends `.FAILED` with `API key
  expired` (401), and nothing raised it.** `status: invalid` is silent (cf.
  IMP-005). Any "a live run works" acceptance must be read as a path claim
  unless the key is renewed first.
- **`~/flakes` is a directory of the `~` repo (`davidlee/nix-config`), not its
  own.** So are `~/.config/*` regular files. One repo, one commit each.
- **Nix `''`-string edits must not pass through a Python string literal.**
  `''${` collapses to `${` (empty-string concatenation) and nix then
  interpolates. Re-read the line and `nix-instantiate --parse` before building.
- **Numbers in criteria rot; shapes do not.** Tracked wpm rows 63 → 98 between
  the design survey and execution, because the `~/notes` daily `git add .`
  kept importing them. A criterion that says "the few tracked rows" stays
  true; one that says "63" does not. PHASE-03 EN-2 quotes 33 / 4 — re-measure.

### Slice-specific

- `satan-runs-dir` and `satan-sensor-wpm-log-dir` now derive from
  `satan-state-root` (`aab4b83`); `satan-hippocampus-dir` stays corpus.
  Trees renamed 2026-09-11 17:14 (11047 / 116 files, counts equal before and
  after); `~/notes/satan` is 308K of authored content only. Notes repo
  `08927b5` untracked 98 rows and dropped the gitignore line. `~` repo
  `abbc3746` (wpm-status.py) and `186bdf5c` (sway.nix); rebuilt archive
  script verified to carry the state path.
- Both external writers honour `XDG_STATE_HOME` with empty-as-unset semantics
  (`or` / `:-`), which is what ISS-010 wants the elisp to do.
- Closed 2026-09-14: Emacs restarted, timers armed (three catch-up runs
  fired immediately against the fresh Emacs — the order held), one manual
  tick wrote a complete bundle with status `done` under the new root;
  `most-recent` repointed; wpm rows and the hourly archive land on the new
  path; nothing recreated under `~/notes/satan`. The tick genuinely
  succeeded; the morning and motd catch-up runs still `.FAILED` at turn 0 on
  `API key expired` (401) — the key is not renewed, and the tick mode must
  use a different provider or key. Worth a backlog item.
- Plan amendments proposed, not applied: PHASE-02 VT-2 keywords (vacuous —
  passes before the change) and PHASE-01 VT-3 keyword
  (`directory-files-recursively` → `directory-files`). PHASE-01 VT-3 fails
  the mechanical gate today while its test is real.

## PHASE-03 (2026-09-14)

Corpus cutover executed: `~/notes/satan` → `~/satan`, a standalone repo with
history. Live system consistent again as of 12:54 (home-manager generation 713).

```
~/notes (user notes, SATAN reads)     ~/satan (SATAN corpus, repo)     ~/.local/state/satan
  journal/ weekly/ inbox.org            prompts/ system/ tools/          runs/ log/wpm/
                                        hippocampus/ motives …
  satan-notes-root                      satan-corpus-root               satan-state-root
```

### Durable — survives this slice

- **The runtime jail is deployed from GitHub, not from `~/dev/satan`.**
  `jailed-satan-gptel-harness` on Emacs' PATH comes from `inputs.satan`
  (`github:davidlee/satan`) in `~/flakes`, locked seven weeks behind the tree.
  A `flake.nix` bind change ships only via push + `nix flake update satan` +
  home-switch. The binds are raw `--bind`, which bwrap fails hard on when the
  source is missing — so in any relocation the deploy is on the critical path.
  Memory `mem.fact.satan.runtime-jail-deploys-from-github-input`.
- **Moving a subtree out of a repo with history, as a rename:** `git subtree
  split -P satan -b satan-corpus` (check `satan-corpus^{tree}` = `HEAD:satan`),
  `mv` the directory, then in it `git init` + `fetch <old> satan-corpus` +
  `update-ref refs/heads/main FETCH_HEAD` + `reset` (mixed). Inode and working
  tree untouched; status clean; then `git rm -r --cached` in the old repo.
- **Corpus-gated tests skip silently when a test re-derives the corpus path.**
  Four context tests built `<notes>/satan/prompts` by hand; after the move they
  would have skipped and the suite stayed "green". Tests must use the defcustom
  joins (`satan-prompts-dir` …), and a relocation must compare the skip *set*,
  not just the unexpected count (T3 went 3 → 10 skips while corpus was absent).
- **Inventories miss consumers the survey did not think to look for.** Two
  found on the ground: `~/nushell/config.nu` (nu is the login shell; the survey
  checked zsh) and `~/notes/.pi/SYSTEM.md`, a tracked build artefact that
  inlined the old path. A path sweep must include generated-and-committed
  files and every shell's config.
- **`satan-tick.timer` is `OnBootSec=5min` only** — `list-timers` shows it
  `elapsed` with no NEXT all day. Not a fault of any rebuild.

### Slice-specific

- Commits. satan: `8c444b3` (`satan-corpus-root` default `"~/satan"`,
  standalone, atsatan exclude glob retired), `cc291bc` (plan VT keyword
  amendments, user-approved), `8a49d16` (flake: hippocampus bind +
  `/workspace/corpus` for dev jails), pushed `4ecc741..8a49d16`. `~/satan`:
  30 split commits + `c02b2b2` (8 self-naming corpus files) + `0634e37`
  (justfile `commit`, OQ-4). `~/notes`: `f4ecccf` (untrack), `fbd668c`
  (build-system-prompt + SYSTEM.md). `~`: `76c28893` (zsh + nu motd),
  `92b82a39` (patcher `systemPromptFile`), `1aea39ad` (lock). `.emacs.d`:
  `46da1d6` (denote exclusion dropped).
- OQ-4 settled: `~/satan` has its own `justfile commit` recipe; no
  `.gitignore` (P5 holds — PHASE-02 left only authored content).
- R7 settled: no `workspaceDeps` entry (basename collision); dev jails
  (`jailed-pi-research`, `jailed-dirge`, `jailEnvOptions`) get a raw rw bind at
  `/workspace/corpus` via a named `corpusJailOptions` list.
- Verification: suite 1044/1040/1 (db probe)/3; verify-vt P01 ×4, P02 ×2,
  P03 VT-3 PASS, P03 VT-1/2 attribution by conformance range at completion.
  Manual `tick-pulse` 12:55 and human-triggered `tick-agent` 13:10 (`done`,
  real model turn) and `motd` 13:09 (401, key) — all bundles take mode prompts
  and 100% of tool descriptions verbatim from `~/satan`, 0 `notes/satan`.
  `denote:` link-follow in `~/notes`: human reports no slowdown.
- VH-1 caveat: no pi/MCP interactive session left a footprint
  (`.pi/SYSTEM.md` mtime predates the check); the human-triggered broker runs
  are the evidence. SYSTEM.md itself carries `~/satan` (3) and `notes/satan`
  (0).
- Residue for PHASE-04: 15 package `.el` comments/docstrings, 2 test
  comments, 13 `docs/` files still say `~/notes/satan`. Nothing live.
- Follow-ups filed: CHR-004 (self-edit prompts describe the pre-SL-012
  layout — F-5/A6), CHR-005 (`~/satan` has no remote — D-7), ISS-011
  (`satan-attrd` rejects sensor reason `content_backlog`, 22× since 09-11).
  ISS-012 (motd/morning 401 on the expired key while tick passes — PHASE-02).

### Cleared — do not re-investigate

- The `satan-attrd` `content_backlog` parse error predates the cutover.
- `.emacs.d/.direnv/flake-inputs/*` hits for `notes/satan` are stale nix
  store snapshots, not consumers.

## PHASE-04 (2026-09-14)

Paper trail closed. Whole-$HOME sweep: 2835 hits, 0 unclassified, no missed
consumer.

### Durable — survives this slice

- **In the Claude Code agent shell, `grep` is ugrep with `--ignore-files`.**
  The bash snapshot shadows `grep`/`find` with an embedded ugrep
  (`-G --ignore-files --hidden -I --exclude-dir=.git …`), so every plain
  `grep -r` skips gitignored paths — where untracked consumers live — and the
  PHASE-03 mini-sweep ran under it. With `--dereference-recursive` it also
  walked `~/.wine/dosdevices/z:` into `/`. For a sweep whose result is a
  claim: `rg -l -F --no-ignore --hidden -L -g '!**/<bulk>/**'` (32 s over
  `$HOME`; exit 2 there is dangling symlinks/loops — classify the errors, do
  not trust the status) or GNU grep by absolute path. Folded into
  `mem.pattern.satan.rg-not-ugrep-for-rename-verification`.
- **Docstrings should name the defcustom, not the path.** The 17 stale lines
  became `satan-system-framing-file`, `satan-tools-descriptions-dir`,
  `satan-corpus-root` … — text that cannot rot on the next move.
- **Three-root model is now a concept memory** (`mem.concept.satan.three-roots`)
  linked from the orientation signpost and surfaced in the boot snapshot.

### Slice-specific

- Commits: `566969e` (17 docstring/comment lines, D9 subset), `b6c5845`
  (perceptual-design 7 lines, EX-1), `72dfcb2` (CHR-006: 16 docs/ files /
  104 lines residue), `ee3dfd3` (three-roots concept; orientation +
  skip-unless memories, EX-2/EX-3), `d1ce1ec` (ugrep memory).
- VA-1 buckets (rg, `--no-ignore --hidden -L`, bulk caches/games/containers/
  VCS internals excluded; `~/.claude` and `jail.nix` agent homes swept
  separately): 2292 run bundles (a); 118 doctrine/governance prose — this
  repo's closed slices, SL-015's own record, backlog/RFC evidence, frozen
  `.emacs.d` corpus and pre-split tree (b); 10 satan-patcher + `sloptower`
  (its successor repo, same stale default) (c); 16 `docs/` (d); the rest
  history of some kind — 341 agent session transcripts, 20
  shell/editor/clipboard histories and backups, 36 old nix generations
  (current profile-229 and home-manager-713 are clean), 1 panopticon commit
  record, 1 intentional CHR-003 comment in `satan-patcher.nix`.
- Fixed outside the repo: `~/.claude/projects/-home-david-notes/memory/
  bough-removal-rn2.md` told agents to edit `~/notes/satan/prompts/`.
- Left for the user: `~/.emacs.d/_claude/settings.local.json:33,34,49` grants
  Claude `Read(//home/david/notes/satan/**)` — dead permission entries, not a
  reader; the equivalent for `~/satan` is absent.
- Open doctrine prose still citing old paths, left as record: IMP-010
  (`runs/` path, pre-SL-012 names), RFC-016 §evidence.
- EX-4: `git diff e324794..HEAD -- .doctrine/slice/002* .doctrine/slice/012*`
  empty. VA-2: `memory validate` clean; retrieve on "satan orientation corpus
  root" ranks three-roots then the signpost.
- Suite 1044/1040/1 (db probe)/3; verify-vt 9/9 PASS. `doctrine check gate`
  needs a `gate` recipe this justfile lacks — `just check` is the gate.
- Lifecycle: slice sat at `plan` through all four phases (never flipped to
  `started`); advanced `plan → started [skip] → audit` at close (`5ef5546`).

## Audit (2026-09-17) — RV-005

Reconciliation ledger **RV-005**: 11 findings, no blockers, all terminal.
6 → `/reconcile` (all documentation), 1 fixed in audit scope, 2 tolerated with
rationale, 2 aligned. Suite at the documented invocation: 1044 / 1040 / 1 / 3.

### Durable — survives this slice

- **Two `just check` runs at once corrupt each other.** The DB suites target
  fixed database names by defconst (`satan_memory_test`, `trace_test`,
  `patch_live_test`) and each runs `reset-and-migrate` at setup — no
  namespacing, no lock. Overlapping runs produced **14 phantom failures**
  (`duplicate key … (typname)=(schema_migrations)`,
  `relation "satan_interventions" does not exist`); the serial re-run of the
  identical command was clean. Filed **ISS-013**; folded into
  `mem.fact.satan.green-is-not-green`, which now names five ways this repo
  reports a false result. The others hide a defect; this one manufactures one,
  and it costs an audit round chasing it.
- **An allowlist that suppresses nothing should be re-purposed as a liveness
  check** (PHASE-01 F-14, not previously lifted). Narrowing VT-3 to
  `expand-file-name` with a `satan-*-root` DIR argument already excluded both
  D10 exceptions — `satan-mcp.el:43` joins under `xdg`, and
  `satan-patch-worktree.el:52` is a `format`, not a join — so the allowlist
  was documentary. It was kept as a second test asserting both expressions
  still exist, so the entry fails when its subject is finally rewired instead
  of quietly outliving it.
- **Require-cleanliness is provable where lint is not** (PHASE-01 F-16, not
  previously lifted). Each rewired module was `require`d in its own fresh
  `emacs --batch`; 15/15 loaded clean. That is the check `just lint`
  structurally cannot perform, and it is cheap. Use it whenever a refactor
  moves a symbol between modules.
- **A record that stops moving is the failure mode of a self-correcting
  slice.** This slice corrected itself five times in flight and wrote every
  correction into the design, in place, dated, with evidence — which is why
  the audit found nothing broken. The gap is at the *end*: OQ-1 got its
  resolution written into §6; OQ-4 and R7 were settled just as firmly and
  still read as open. F1 still names waybar as the wpm writer four weeks after
  PHASE-02 disproved it on the ground. §2.4 is still called "the scope
  boundary" though it was two consumers short. In every case the truth is in
  `notes.md` — the right place during a slice, the wrong place after one.
  `design.md` is what the next migration reads.
- **The `design-target` selector registry is not optional bookkeeping.** This
  slice declared 2 paths and edited 28, so `slice conformance` reported 59
  undeclared / 2 conformant for its whole life — the one check that does not
  take the slice's word for its own scope was inert. Declare design targets
  when the design locks, not at audit.

### Slice-specific

- Fixed in audit scope: **CHR-005** → `resolved`/`done`. `~/satan` has remote
  `git@github.com:davidlee/satan-corpus.git`, `HEAD == origin/main` at
  `0634e37` — the item's own acceptance condition, already met.
- Filed: **ISS-013** (concurrent suite runs clobber the shared test DBs).
- Tolerated, on the record: **`doctrine check gate` does not run here** — no
  `gate` justfile recipe. Adding `gate: check` would manufacture a gate that
  cannot fail while ISS-008 stands (`just check` exits 0 regardless), which is
  worse than its absence. Revisit when ISS-008 lands.
- Ground truth re-derived independently at `7f8969d`, not read from these
  notes: `~/notes/satan` absent with no symlink; `satan-corpus-root` =
  `"~/satan"`; corpus repo 832K / 32 commits / pushed; state root holds
  `runs/`, `log/`, 4 sensor JSONs, 70 tick traces; `flake.nix` binds
  `$HOME/satan/hippocampus` (:141) and `/workspace/corpus` (:96); both
  workarounds gone; 6/6 state modules carry `(require 'satan-custom)`;
  `satan-prompts-dir` is a defcustom; `behaviour/` untouched at all 3 sites;
  D10 allowlist survives exactly twice; corpus and package prose name no old
  path; `memory validate` clean; `verify-vt` 9/9.
- Governance untouched as declared: zero `notes/satan` references under
  `.doctrine/{adr,policy,standard}` — POL-001 and the ADR-017 §3 authority
  ledger unaffected.
- Reconciliation brief in `review-005.md`: 6 per-slice direct edits
  (selector registry; design F1/§5.4, §2.4/R5, §6 OQ-4, §8 R7, §9.2;
  `slice-015.md` §Summary and §Follow-Ups). No governance REV. OQ-2 and OQ-3
  need a call at reconcile — file or drop, not left live on a closed slice.
