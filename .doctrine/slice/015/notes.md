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
