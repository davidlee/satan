# Design SL-015: Corpus relocation: SATAN model-facing corpus leaves ~/notes for a standalone repo

<!-- Reference forms (.doctrine/glossary.md § reference forms): entity ids padded
     (SL-020, REQ-059, ADR-004); doc-local refs bare — OQ-1 (§6), D1 (§7),
     R1 (§10), Q1. -->

## 1. Design Problem

SATAN resolves three kinds of path off one knob. `satan-notes-root` (`~/notes`)
is the declared root of the *user's* notes corpus, and SATAN also derives its
own model-facing corpus below it as `${satan-notes-root}/satan/...` — the
`"satan/"` segment spelled as a bare literal at every site, because the thing
it denotes has no name. A third kind, runtime state, is resolved by an
eight-fold-cloned XDG expression that no module owns.

The unnamed concept is the defect. Its symptoms: a corpus that cannot move, two
workarounds that exist only to undo the nesting, and a 145M runtime tree
cohabiting with 250K of authored prompt text in a repo that is neither's proper
home.

Name the three roots, then the move is a default change.

## 2. Current State

### 2.1 The conflation, measured

`satan-notes-root` has **19 production references** (`satan/*.el`, tests
excluded):

| Class | Count | Sites |
|---|---|---|
| SATAN corpus path, spelled `"satan/<x>"` | 16 | below |
| Genuine *user-notes* consumer | 2 | `satan-tools-notes-root:37`, `satan-tools-atsatan-root:37` |
| Docstring reference | 1 | `satan-tools-notes.el:4` |

The 16 corpus sites:

| File:line | Derived path |
|---|---|
| `satan-tools-org.el:18` | `satan/motd.txt` |
| `satan-tools-org.el:23` | `satan/proposals` |
| `satan-motive.el:53` | `satan/motives.org` |
| `satan-motive.el:62` | `satan/motives.archive.org` |
| `satan-mode.el:81` | `satan/prompts/` |
| `satan-patch-prompt.el:22` | `satan/patch-agent/prompt.md` |
| `satan-tools-inbox.el:16` | `satan/inbox.org` |
| `satan-tools.el:27` | `satan/tools/` |
| `satan-sensor-wpm.el:21` | `satan/log/wpm` |
| `satan-context.el:119` | `satan/system/scaffold.txt` |
| `satan-context.el:126` | `satan/system/framing.txt` |
| `satan-context.el:535-537` | `satan/{prompts,system,tools}` (`satan-self-edit-mind-roots`) |
| `satan-run.el:19` | `satan/runs` |
| `satan-run.el:24` | `satan/hippocampus` |

Note the corrected figure. A first survey put this at 37 by grepping
`expand-file-name "satan…"`; ~18 of those hits anchor to **XDG state**, not to
`satan-notes-root`, and are already correct. The corpus surface is 16 sites in
9 files (`satan-context.el` contributes 5, `satan-run.el` /
`satan-tools-org.el` / `satan-motive.el` 2 each).

### 2.2 The state-root clone

Those XDG hits are their own duplication. **Eight** defcustoms inline the same
resolution, in two spellings of the same fallback:

| File:line | Leaf | Fallback spelling |
|---|---|---|
| `satan-trace.el:38` | `satan/` | `".local/state" "~"` |
| `satan-ingest-cursor.el:53` | `satan/ingest-cursor.json` | `".local/state" "~"` |
| `satan-sensor-alerts.el:23` | `satan/notified.json` | `".local/state" "~"` |
| `satan-sensor-wpm.el:27` | `satan/sensor-wpm.json` | `".local/state" "~"` |
| `satan-sensor-curiosity.el:18` | `satan/sensor-curiosity.json` | `".local/state" "~"` |
| `satan-sensor-content.el:29` | `satan/sensor-content.json` | `".local/state" "~"` |
| `satan-patch-worktree.el:19` | `satan/patch-agent/worktrees/` | `"~/.local/state/"` |
| `satan-patch-prompt.el:28` | `satan/patch-agent/logs/` | `"~/.local/state/"` |

`~/.local/state/satan/` already exists and holds every one of those artefacts.
The convention is real and in production; only its name is missing.

### 2.2b The `behaviour/` class — not ours (finding, 2026-08-24)

Two further defcustoms resolve off the same XDG expression but their leaf is
`behaviour/`, **not** `satan/`:

| File:line | Leaf | Spelling |
|---|---|---|
| `satan-sensor-curiosity.el:26` | `behaviour/segments` | `".local/state" "~"` |
| `satan-tools-content.el:24-28` | `behaviour/content/` | `(if xdg (expand-file-name xdg) "~/.local/state/")` — a third spelling |

A third member ignores `XDG_STATE_HOME` entirely:
`satan-tools-activity.el:35` = `(expand-file-name "~/.local/state/behaviour/")`.
Three remediation-hint string literals at `satan-sensor-alerts.el:113,117,121`
name the same tree.

This is panopticon's state — an **external producer, read-only to SATAN**
(consumed at `satan-memory-evidence.el:507`, `satan-ingest-cursor.el:137,196`;
a workspaceDep at `flake.nix:98`). It is a fourth ownership class and it is
**out of scope by ownership**: SATAN does not own the tree, so SATAN does not
name its root (§7 D1). Rewiring these to `satan-state-path` would resolve to a
nonexistent `~/.local/state/satan/behaviour/…` and silence the curiosity sensor
without an error (`satan-sensor-curiosity.el:74` returns `(0 . SINCE-TS)` when
the segment file is absent).

An earlier correction in this slice moved this count the *wrong* way (8 → 9,
folding `satan-sensor-curiosity-segments-dir` into the state class). Eight is
right for the class SATAN owns.

### 2.3 Cohabitation costs

| Cost | Evidence |
|---|---|
| Authored corpus hidden in a runtime tree | `satan/` = 9,580 files / 146M; `satan/runs/` alone is 9,423 files / 145M and is gitignored (`~/notes/.gitignore:1 = /satan/runs`). The tracked corpus is **124 files / 528K** — of which 63 are `satan/log/wpm` telemetry rows (§7 D3). |
| denote workaround | `~/.emacs.d/org/dl-denote.el:15` sets `denote-excluded-directories-regexp` solely to stop denote's uncached tree walk from statting ~10k non-note files on every `denote:` link-follow (~10s per link, per its own comment). |
| atsatan workaround | `satan-tools-atsatan.el:51-52` (a `defconst`; consumer at :154) carries `'("!**/satan/**")` to exclude SATAN's corpus from the `@satan` scan of the user's notes — an exclusion needed only because the two are nested. |
| Ownership inversion | SATAN *writes* its corpus; it only *reads* the user's notes. The write target is nested inside the read-only one, and the jail encodes exactly that inversion (`--ro-bind $HOME/notes` + a narrower `--bind` punching hippocampus back to read-write). |

### 2.4 Consumer surfaces

Twelve surfaces reference `~/notes/satan`; one is punted (§7 D5).

| # | Surface | Refs | In scope |
|---|---|---|---|
| 1 | `satan/*.el` corpus sites | 16 (§2.1) | yes |
| 1b | `satan/*.el` cloned XDG-state defcustoms | 8 (§2.2) | yes |
| 2 | `satan/test/*.el` | 4 files bind `satan-notes-root` (`satan-context-test.el`, `satan-integration-test.el`, `satan-custom-test.el`, `satan-run-test.el`); `satan-run-test.el:197` asserts `/tmp/nr/satan/hippocampus` | yes |
| 3 | **Authored corpus text** — 8 files name their own old path to the model: `system/scaffold.txt`, `tools/{inbox_append,hippocampus_write,proposal_stage}.md`, `prompts/{motd,morning,self-edit-mech,self-edit-mind}.txt` | 8 | yes |
| 4 | `flake.nix:134` jail bind | 1 | yes |
| 5 | `~/notes/justfile:12,14` — `build-system-prompt` cats `satan/system/scaffold.txt` + `satan/prompts/interactive.txt` into `.pi/SYSTEM.md` | 2 | yes |
| 6 | `~/.config/waybar/wpm-status.py:43` — **writes** the wpm TSV | 1 | yes |
| 7 | `~/.config/zsh/init.zsh:161` — motd read | 1 | yes |
| 8 | **`~/flakes/modules/home/linux/satan-patcher.nix`** — the unit is a home-manager store symlink and carries **no** `systemPromptFile =`, so the daemon runs on the punted module's own default (`~/dev/satan-patcher/nix/module.nix:74`). The editable surface is the flake module, not the unit (§7 D5) | 1 | yes |
| 9 | `~/.emacs.d/org/dl-denote.el:15` — exclusion regexp | 1 | yes (retire) |
| 10 | `docs/perceptual-design.md:227` + memory corpus | 3 | yes |
| 11 | `~/dev/satan-patcher` — Go defaults, nix module, 3 docs | 5 | **no** → CHR-003 |
| 12 | **`~/flakes`** — `modules/home/linux/sway.nix:12` builds `wpm-archive-yesterday` with a hardcoded `~/notes/satan/log/wpm/<date>.tsv`; its timer is **active** (`OnCalendar=*-*-* 04:00`, `Persistent=true`). Nix derivations, so a rebuild — not an in-place edit | 2 | yes |
| 13 | **`~/dev/satan/docs/` + production docstrings** — ~111 doc lines across 17 files and 17 docstring/comment lines in `satan/*.el` name the old path | ~128 | see §7 D9 |
| 14 | **`~/nushell/config.nu:113-114`** — motd read. **Found on the ground in PHASE-03, not by this survey**, which checked zsh only; nu is the login shell. Tracked in the `~` repo, sourced by path, so no rebuild | 2 | yes |
| 15 | **`~/notes/.pi/SYSTEM.md`** — a *tracked build artefact* that inlined the old path, produced by surface 5's `build-system-prompt` recipe. **Found on the ground in PHASE-03.** Generated-and-committed files are readers too | 1 | yes |

**This table was two consumers short** (PHASE-03 F-2/F-3, added above as 14 and
15). The generalisation, and the reason R5's sweep is load-bearing rather than
belt-and-braces: a path survey must cover **every shell's config**, not the one
the surveyor uses, and **generated files that are committed**, which read as
build output and behave as consumers.
### 2.5 Baseline

`just check` green at `043fb21`. `~/notes` working tree: 4 modified + **33** untracked under `satan/` — all 33
untracked and one modified are `satan/log/wpm/*.tsv` telemetry; the genuine
corpus edits are `motd.txt`, `motives.org`, `motives.archive.org` (must be committed before any split — §5.4 S0).

## 3. Forces & Constraints

- **F1 — Live writers.** `wpm-daemon.service` writes the wpm TSV every minute;
  `satan-tick.timer`, `satan-motd.timer`, `satan-morning.timer` and
  `satan-attrd.service` are active. A move with writers running strands rows in
  the old tree. **Corrected 2026-09-11 (PHASE-02 F-1):** an earlier draft named
  "waybar's wpm logger" as the writer. Waybar's `custom/wpm` only *reads*
  `$XDG_RUNTIME_DIR/wpm.json`; the writer is a systemd user unit running
  `wpm-status.py --daemon` (`sway.nix:79-85`). Stopping waybar leaves the writer
  running — the quiesce must name the daemon. `~/.config/waybar/wpm-status.py`
  is still the correct *file* to retarget: it is what the daemon executes.
- **F2 — Model-facing text is data, not code.** Eight corpus files tell the
  model where its own corpus is. A path change that stops at the elisp leaves
  the model holding stale instructions — a silent, corpus-level lie.
- **F3 — Provenance matters for prompts.** The framing/scaffold/prompt evolution
  is the only record of how SATAN's behaviour was tuned. History must survive
  the split (user decision, 2026-08-22).
- **F4 — `~/notes` is a jail read-only mount.** `flake.nix:133` ro-binds all of
  `$HOME/notes`; the corpus is currently reachable *through* it.
- **F5 — Tilde defaults are a live trap.** `satan-notes-root` defaults to the
  literal `"~/notes"`; two shipped regressions came from handing an unexpanded
  tilde to `call-process` (`mem.signpost.satan.orientation`). Any new root
  defcustom inherits the hazard.
- **F6 — `satan-custom.el` must stay a zero-satan-dep leaf.** It is loaded
  before every other module; that is why it can own roots at all.
- **F7 — Same filesystem.** `~/notes`, `~/.local/state` and `~` are all on
  `/dev/nvme0n1p2`, so every move is an instant rename, not a 145M copy.

## 4. Guiding Principles

- **P1 — Name the concept, then move it.** The rename is the design; the
  relocation is a default value.
- **P2 — One root per ownership class *SATAN owns*.** Read-only user data,
  SATAN-authored content, and SATAN runtime state are three classes. Three
  roots, three joins. Panopticon's `~/.local/state/behaviour` (§2.2b) is a
  fourth class SATAN reads but does not own — no root, by ownership.
- **P3 — Describe the convention that exists.** `satan-state-root` documents
  `~/.local/state/satan`, already in production at 8 sites. No new layout.
- **P4 — No fallback chains.** A root that silently resolves to a second
  location hides a failed move; for framing text a wrong-but-readable path is
  worse than an error.
- **P5 — Version the authored, discard-safe the runtime.** After the split
  `~/satan` needs no `.gitignore`.

## 5. Proposed Design

### 5.1 System Model

Three roots and three joins in `satan-custom.el`, the existing leaf owner of
`satan-notes-root` / `satan-notes-path`:

```
satan-notes-root   "~/notes"                 read-only, user-owned
  └── satan-notes-path   journal/, weekly/, inbox.org, @satan scan target

satan-corpus-root  "~/satan"                 read-write, SATAN-authored, versioned
  └── satan-corpus-path  prompts/ system/ tools/ hippocampus/ proposals/
                         patch-agent/ motives.org motd.txt inbox.org

satan-state-root   "~/.local/state/satan"    read-write, runtime, discardable
  └── satan-state-path   runs/ log/wpm/ *.json tick-trace-*.jsonl
                         patch-agent/{logs,worktrees}/
```

`satan-notes-path` already exists and is unchanged. The two new joins are its
exact shape, so all three read identically at the call site.

### 5.2 Interfaces & Contracts

```elisp
(defcustom satan-corpus-root "~/satan"
  "Root of SATAN's own model-facing corpus.
Prompts, system scaffold and framing, tool descriptions, motives,
hippocampus, proposals — content SATAN reads and writes, versioned in
its own repo.  Distinct from `satan-notes-root', the user's notes
corpus, which SATAN only reads."
  :type 'directory :group 'satan)

(defcustom satan-state-root
  (expand-file-name "satan" (or (getenv "XDG_STATE_HOME")
                                (expand-file-name ".local/state" "~")))
  "Root of SATAN's runtime state.
Run bundles, sensor cursors, telemetry, patch-agent logs and
worktrees.  Discardable: nothing here is authored, versioned, or
reconstructible-from only."
  :type 'directory :group 'satan)

(defun satan-corpus-path (&rest segments) …)  ; = satan-notes-path shape
(defun satan-state-path  (&rest segments) …)
```

Call-site rewrites — the `"satan/"` literal disappears at all 16 sites:

| Before | After |
|---|---|
| `(expand-file-name "satan/system/framing.txt" satan-notes-root)` | `(satan-corpus-path "system" "framing.txt")` |
| `(expand-file-name "satan/runs" satan-notes-root)` | `(satan-state-path "runs")` |
| `(expand-file-name "satan/log/wpm" satan-notes-root)` | `(satan-state-path "log" "wpm")` |
| `(expand-file-name "satan/notified.json" (or (getenv "XDG_STATE_HOME") …))` | `(satan-state-path "notified.json")` |

**The table above is the end state, not PHASE-01.** `runs/` and `log/wpm/`
belong to the *state* class by ownership (§5.3) but they physically live under
`~/notes/satan/` until PHASE-02 S2 moves them. So in PHASE-01 all **16** corpus
sites — `satan-runs-dir` and `satan-sensor-wpm-log-dir` included — rewire to
`satan-corpus-path`, which is what keeps them byte-identical under A1 and what
EX-3/EX-7 require. Their re-pointing to `satan-state-path` happens in PHASE-02,
in the same act as the `mv`. Rewiring them to `satan-state-path` in PHASE-01
would relocate them ahead of the data and break a phase that is meant to carry
no cutover risk (finding F-12).

The two user-notes defcustoms (`satan-tools-notes-root`,
`satan-tools-atsatan-root`) keep defaulting to `satan-notes-root`. That is now
a statement rather than an accident.

### 5.3 Data, State & Ownership

| Tree | Root | Git home | Rationale |
|---|---|---|---|
| `prompts/ system/ tools/ patch-agent/prompt.md proposals/ motives*.org motd.txt inbox.org` | corpus | `~/satan` (new repo, split history) | authored; the 124 tracked files |
| `hippocampus/` | corpus | `~/satan` | SATAN-authored and currently **tracked** in `~/notes`; self-curated memory is content, not scratch — the jail's read-write bind stays |
| `runs/` | state | none | 9.4k frozen run bundles, already gitignored |
| `log/wpm/` | state | none | per-minute telemetry written by a non-SATAN process; a handful of rows are tracked today and that was never intentional (§7 D3) |

Post-split `~/satan` carries no `.gitignore` — *provisionally*. `hippocampus/`
and `proposals/` are model-written and corpus-tracked, so `~/satan` will run
permanently dirty with no commit path (today that dirt is absorbed by
`~/notes`' daily `git add .` habit, `~/notes/justfile:1-4` — which is how the
63 wpm rows and 7 hippocampus files came to be tracked at all). Decide the
`.gitignore` / commit-automation question in PHASE-03, with the repo in front
of us (§6 OQ-4).

### 5.4 Lifecycle, Operations & Dynamics

Cutover, ordered. F1 forces writers down first; F7 makes every move instant.

- **S0 — Quiesce and clean.** Commit the 4 modified + 31 untracked corpus files
  in `~/notes`. `systemctl --user stop satan-{tick,motd,morning}.timer
  satan-{attrd,patcher}.service wpm-daemon.service` — the wpm writer is that
  unit, not waybar (F1). Close Emacs, or plan to re-eval `satan-custom` after
  S3.
- **S1 — Split with history.** `git subtree split -P satan -b satan-corpus` in
  a `~/notes` clone, then `git init ~/satan` and pull that branch.
  `git subtree` is built in; `git filter-repo` is **not installed** here, so
  prefer subtree and fall back to `nix run nixpkgs#git-filter-repo` only if the
  subtree history proves unusable.
- **S2 — Place the trees.** `mv` `runs/` and `log/wpm/` into
  `~/.local/state/satan/` (rename, same fs). `git rm -r --cached satan` in
  `~/notes` and drop the `/satan/runs` gitignore line.
- **S3 — Flip the code.** Land §5.2 (defcustoms, joins, 16 + 8 call sites,
  tests), the 8 corpus text files, `flake.nix`, the `~/notes` justfile, the 3
  `~/.config` files, and retire the denote regexp + atsatan glob.
- **S4 — Restart and verify, in this order.** `just check` green → **restart
  Emacs first** → *then* start the timers. `satan-motd.timer`,
  `satan-morning.timer` and `wpm-archive.timer` are all `Persistent=true`: a
  timer started after its window has passed fires a catch-up run *immediately*.
  Timers before Emacs means that run executes against stale defcustoms and
  writes to the dead path — exactly what R4/E1 exist to prevent. Then one live
  tick writes under `~/.local/state/satan/runs/`; `~/notes/satan` gone.

**No transitional symlink.** A `~/notes/satan → ~/satan` link would keep both
paths live, so a missed consumer would keep working and go undetected — exactly
the failure the move exists to prevent. With writers down and renames instant,
the window is seconds (§7 D4).

### 5.5 Invariants, Assumptions & Edge Cases

- **I1** Every SATAN-owned path resolves through exactly one of the three joins.
  No `"satan/"` literal survives in a path expression.
- **I2** `satan-custom.el` gains no satan dependency (F6).
- **I3** `satan-corpus-root` is SATAN's only write target outside the state root
  and the notes corpus stays read-only to SATAN.
- **A1 — The jail needs no corpus bind.** Corpus assembly is entirely
  elisp-side (`satan-context.el`); the harness receives text in the bundle and
  reads no corpus file. The only jail-side corpus reference is `today_path`
  (`satan-context.el:491`), a *notes* path. So `flake.nix` changes one line —
  the hippocampus bind source — and `--ro-bind $HOME/notes` stays for notes
  reads. Verified by grep: no `SATAN_NOTES_RO` / `/satan/notes` consumer exists
  in `satan/harness/*.py` beyond a test fixture string. **Re-verified
  adversarially 2026-08-24 and upheld**: `SATAN_NOTES_RO` and
  `SATAN_HIPPOCAMPUS` are *set* at `flake.nix:130-139` and read *nowhere* in
  the repo; the harness opens only `bundle.json` / `manifest.json` from
  `SATAN_RUN_DIR` (`satan/harness/bundle.py:17,22`, `runloop.py:165-170`); the
  patch agent reads its system prompt **broker-side** and passes the contents
  as `--system-prompt <text>` (`satan-patch-adapter-pi.el:152-160`), so no
  jailed process opens a corpus path; `satan-attrd` has no on-disk state beyond
  the DB. But see §8 R7 — the `flake.nix:98` workspaceDeps entry is a
  *separate* line and a separate problem.
- **A2 — Historical run bundles keep stale absolute paths.** 2,208 files under
  `runs/` embed `~/notes/satan/...`. They are frozen evidence; rewriting them
  would falsify the record. Accepted, not fixed.
- **E1** `satan-self-edit-mind-roots` is a `defcustom` whose *default* is
  computed from the root; a user who has customised it keeps a stale value.
  Same for the other 15. Setting `satan-corpus-root` after load does not
  retroactively move them — restart, don't `setq`.
- **A3 — `expand-file-name` preserves a trailing slash; the joins do not.**
  Verified: `(expand-file-name "satan/prompts/" "~/notes")` →
  `".../notes/satan/prompts/"`, while `(satan-corpus-path "prompts")` →
  `".../notes/satan/prompts"`. Five sites carry a trailing slash
  (`satan-mode.el:81`, `satan-tools.el:27`, `satan-trace.el:37`,
  `satan-patch-worktree.el:18`, `satan-patch-prompt.el:27`). Every consumer of
  those five normalises with `expand-file-name` or `file-name-as-directory`
  — including the confinement guard at `satan-patch-worktree.el:66-70` — so the
  rewire is behaviour-free, but **VA-1 must compare after
  `file-name-as-directory` normalisation** or those five read as a false defect.
- **A4 — `satan-prompts-dir` is a `defvar`, not a `defcustom`**
  (`satan-mode.el:80`). It has no `standard-value` property, so the
  `(eval (car (get 'SYM 'standard-value)) t)` idiom VT-2 mandates cannot reach
  it. Promote it to a `defcustom` — a compatible change, and it should have been
  one. The 24 sites map to **22 variables** (14 corpus + 8 state);
  `satan-self-edit-mind-roots` is one variable spanning 3 sites.
- **E2** Unexpanded tilde into `call-process` (F5): `satan-corpus-root` ships
  the literal `"~/satan"` for symmetry with `satan-notes-root`, so the join
  helpers must `expand-file-name` the root exactly as `satan-notes-path` does.

## 6. Open Questions & Unknowns

- **OQ-1 — RESOLVED 2026-08-24, subtree is fine.** `~/notes` has **36 commits
  total**, 28 touching `satan/`. `git subtree split -P satan` finishes in
  seconds and yields ≤28 trivially-inspectable commits. Message quality is the
  expected dated-snapshot granularity (`2026-07-22`, `2026-07-08`, plus two
  conventional-commit outliers `d6a7b54`, `0bd5733`) — thin, but real, and no
  available tool improves it. `git filter-repo` is confirmed absent and not
  needed. F3's provenance survives; R2 downgraded.
- **OQ-2** Should `~/satan` carry its own `justfile` owning
  `build-system-prompt`, rather than leaving the recipe in `~/notes` reading
  across repo boundaries (§7 D7 takes the conservative option)?
- **OQ-4 — RESOLVED 2026-09-14 (PHASE-03): a commit recipe, no `.gitignore`.**
  The question was whether `~/satan` would run permanently dirty (§5.3), since
  `hippocampus/` and `proposals/` are model-written and corpus-tracked and P5
  gives the repo no `.gitignore` and no commit automation — dirt absorbed today
  only by `~/notes`' daily `git add .` habit, which `~/satan` does not inherit.
  Settled the third way: `~/satan` carries **its own `justfile` with a `commit`
  recipe** (`0634e37`), and **no `.gitignore`** — P5 holds as written, because
  PHASE-02 had already moved every runtime tree out, leaving only authored
  content. Gitignoring hippocampus was rejected for D3's reason: it is the one
  memory trail SATAN writes deliberately, and dropping it from version control
  loses exactly what makes it content rather than scratch. P5 is no longer
  provisional.
- **OQ-3** `satan-tools-atsatan-root` defaults to the whole notes corpus. With
  the corpus gone, should the `@satan` scan also cover `~/satan`? Argument for:
  proposals and motives are exactly where a `@satan` marker would be dropped.
  Out of scope here; capture as backlog if wanted.

## 7. Decisions, Rationale & Alternatives

- **D1 — Three named roots, not two — and exactly three.** The move needs a
  state root anyway (`runs/` must land somewhere), and naming it retires the
  8-fold clone of §2.2 in the same act. *Alternative:* add `satan-corpus-root`
  only and leave the clones — rejected: it leaves the third ownership class
  unnamed while demonstrably in use. *Second alternative* (raised by review,
  2026-08-24): a **fourth** root for the `behaviour/` class of §2.2b, since P2
  reads "one root per ownership class" — rejected: SATAN reads that tree and
  does not own or write it, so naming its root would assert an ownership SATAN
  does not have. P2 is amended to say so explicitly. The two behaviour sites are
  excluded from the rewire, not folded into the state class.
  **Corrected rationale:** an earlier draft justified D1 partly by "the two
  divergent fallback spellings are a latent bug waiting on an `XDG_STATE_HOME`
  that ends in a slash". **That is false** — the divergence is in the *fallback*
  branch, unreachable whenever `XDG_STATE_HOME` is set, and
  `(expand-file-name "satan/x" "/tmp/xdg/")` normalises correctly regardless.
  The clone is worth retiring for DRY and for §2.2b's mis-filing hazard, not for
  a bug that does not exist. VT-1's trailing-slash `XDG_STATE_HOME` case tests
  something the two spellings cannot disagree about — keep it as a cheap
  regression guard, but not as this decision's evidence.
- **D2 — `satan-corpus-root` defaults to `"~/satan"` outright; no
  derived-with-fallback.** *Alternative:* default to
  `${satan-notes-root}/satan` and fall back, so both layouts resolve during
  cutover. Rejected per P4: a fallback that finds the old tree turns a botched
  move into a silent misconfiguration, and the content in question is the
  model's own framing.
- **D3 — `runs/` and `log/wpm/` to the state root; `hippocampus/` stays
  corpus.** Run bundles are already gitignored, so nothing is lost. `log/wpm/`
  has a few tracked rows, which reads as an accident of a `git add .` habit
  rather than intent — it is telemetry from a non-SATAN writer. Hippocampus is
  the opposite: tracked, SATAN-authored, and the thing SATAN curates about
  itself. *Alternative:* move hippocampus to state too, for a purely-static
  corpus — rejected: it is content, and dropping it from version control loses
  the one memory trail SATAN writes deliberately.
- **D4 — No transitional symlink.** See §5.4. *Alternative:* symlink for a week
  and watch for accesses — rejected: it defers the discovery of a missed
  consumer to whenever it next runs. **Corrected 2026-09-17 (RV-005 F-3):** an
  earlier draft added "and the surface inventory (§2.4) is complete enough not
  to need a net". It was not — it was two consumers short (R5, §2.4 rows 14 and
  15). The decision stands, and the misses are the argument *for* it rather than
  against: with no symlink the old path was absent, so both readers failed
  loudly and surfaced inside the phase. The net is R5's sweep, not the
  inventory.
- **D5 — `satan-patcher` punted to CHR-003** (user direction, 2026-08-22: not
  in active use, may be replaced). Its 5 refs stay stale. **Corrected
  2026-08-24: the pin this decision rested on does not exist.** An earlier
  draft claimed `satan-patcher.service:9` pins `SATAN_PATCHER_PROMPT` and is in
  scope. In fact that unit is a **symlink into
  `/nix/store/…-home-manager-files/`** and is not editable; the value there is
  the punted module's own default
  (`~/dev/satan-patcher/nix/module.nix:74` = `%h/notes/satan/patch-agent/prompt.md`),
  because `~/flakes/modules/home/linux/satan-patcher.nix:26-35` declares
  `services.satan-patcher` with **no** `systemPromptFile =`. The running daemon
  is in exactly the state this decision called the only dangling case. Fix, and
  it stays outside CHR-003's repo: add one line
  `systemPromptFile = "%h/satan/patch-agent/prompt.md";` to
  `~/flakes/modules/home/linux/satan-patcher.nix`, then home-manager rebuild +
  `systemctl --user daemon-reload`. The elisp-side reader
  (`satan-patch-prompt.el:22`) is in scope as one of the 16.
- **D6 — The 8 authored corpus files are in scope.** This narrows the slice's
  "corpus content is a non-goal": content *semantics* are untouched, but path
  strings inside model-facing text are part of the move (F2). Reconcile the
  scope doc.
- **D7 — `build-system-prompt` stays in the `~/notes` justfile, with retargeted
  sources.** Its output is `~/notes/.pi/SYSTEM.md`, consumed by jailed-pi run
  from `~/notes`; moving the recipe would separate it from its artefact. See
  OQ-2.
- **D9 — Prose inside the code repo is not part of the cutover.** ~111 lines
  across 17 files under `docs/` (`docs/governance.md` 31,
  `docs/data-collection.md` 20, `docs/at-satan/design.md` 12) and 17
  docstring/comment lines in `satan/*.el` name `~/notes/satan`. F2's objection
  is about **model-facing** text — the corpus tells the model where the corpus
  is, and a stale path there is an operative lie. A docstring is not read by the
  model. Retargeting ~128 prose lines is real, unestimated work; PHASE-04's
  sweep gains an explicit "prose in the code repo" allowlist instead, and the
  residue goes to backlog. *Alternative:* fix them all in PHASE-04 — rejected as
  unscoped, but the 17 docstrings are the defensible subset if a smaller batch
  is wanted.
- **D10 — Two live `satan/` path expressions survive I1, by allowlist.**
  `satan-mcp.el:43` (`(expand-file-name "satan/mcp" xdg)` under
  `XDG_RUNTIME_DIR` — a genuine fourth location, outside all three roots) and
  `satan-patch-worktree.el:52` (`(format "satan/%s/%s-%s" …)` — the job-id and
  branch prefix, joined under the worktree root at :56). Both are path
  expressions, so a path-expression-scoped VT-3 flags them. The guard is
  written as "no `satan/` literal in an `expand-file-name` whose DIR argument is
  a `satan-*-root`", with these two named in an explicit allowlist. Narrow and
  honest, which is less than I1's letter — see §9.
- **D8 — Retire both nesting workarounds** (denote regexp, atsatan glob). They
  have no remaining referent, and the denote regexp would otherwise silently
  exclude any future legitimately-named `satan/` note directory.

## 8. Risks & Mitigations

| id | Risk | Mitigation |
|---|---|---|
| R1 | Writers strand rows in the old tree mid-move | S0 quiesce; verify with `systemctl --user list-timers` before S1 |
| R2 | ~~`git subtree split` yields useless history (OQ-1)~~ **DOWNGRADED 2026-08-24** | OQ-1 resolved: 36 commits total, 28 touching `satan/`; split runs in seconds, history is thin-but-real. No fallback needed |
| R3 | Dirty `~/notes` tree (4 M + 31 ??) loses uncommitted corpus edits in the split | S0 commits first — hard gate |
| R4 | A running Emacs holds old defcustom values, writes to the dead path | Restart Emacs at S4; E1 says restart, never `setq` |
| R5 | **FIRED** — a consumer missed from §2.4. Two, found on the ground in PHASE-03: `~/nushell/config.nu` (the survey checked zsh; nu is the login shell) and `~/notes/.pi/SYSTEM.md` (a tracked, generated build artefact inlining the old path). Both are now §2.4 rows 14 and 15. Neither broke anything, because D4 left the old path absent and they failed loudly; the mandated sweep is what caught them | Post-cutover sweep as a VA check — **`grep -rIl --dereference-recursive`**, because plain `grep -r` does **not** follow symlinks and every home-manager dotfile under `~/.config` is a store symlink (proven: 0 hits vs 2 with `--dereference`). The sweep must also cover `~/flakes` *sources*, which is where the two hardest consumers actually live (surfaces 8 and 12). The old path must not exist, so any surviving reader errors loudly (D4) |
| R7 | `flake.nix:98` lists `/home/david/notes/` among `workspaceDeps`, bind-mounted at `/workspace/notes` for jailed-pi / jailed-claude / jailed-opencode / jailed-dirge (`~/flakes/pub/README.md:310`). After the cutover a jailed *dev* agent can no longer see a prompt or `system/framing.txt` — a dev-workflow regression, not a runtime one (A1). Adding `~/satan` collides: basename `satan` is already claimed at `flake.nix:131` by `--bind "$HOME/dev/satan" "/workspace/satan"` | **SETTLED 2026-09-14 (PHASE-03):** no `workspaceDeps` entry — the `satan` basename collision stands and that list joins on basename. The dev jails instead get a raw read-write bind at `/workspace/corpus`, via a named `corpusJailOptions` list added to `jailed-pi-research`, `jailed-dirge` and `jailEnvOptions` (`flake.nix:96`, `8a49d16`). Dev-agent corpus visibility is restored under a non-colliding name; no runtime path was involved (A1) |
| R8 | `wpm-archive.timer` (active, `Persistent=true`, 04:00) fails **silently** after PHASE-02 — `~/flakes/…/sway.nix:12` hardcodes the old TSV path, so the script takes its `if [ ! -f "$file" ]` branch, prints "nothing to archive" and exits 0. Hourly WPM bucketing stops permanently with no error | PHASE-02 gains an exit criterion for `sway.nix:12`; it is a nix derivation, so a flake edit + rebuild, not a `sed` |
| R6 | The 145M move is slower than assumed | F7: same filesystem, `mv` is a rename |

## 9. Quality Engineering & Validation

New / changed ERT coverage, extending `satan-custom-test.el` (which already
tests `satan-notes-path`) and `satan-run-test.el` (which already asserts
defcustoms derive from a root, not a literal — the exact invariant this slice
generalises):

- **VT — three joins.** `satan-corpus-path` / `satan-state-path` join below
  their roots and expand a tilde root, mirroring the existing
  `satan-notes-path` cases.
- **VT — derivation, not literals.** Rebinding each root moves every dependent
  default. Extends `satan-run-test.el:186`'s pattern to the corpus and state
  roots; the wpm, sensor, trace and patch-worktree paths are the new cases.
- **VT — no `"satan/"` literal survives *in a root-anchored join*.** A
  grep-shaped assertion over `satan/*.el`: no `expand-file-name` whose DIR
  argument is a `satan-*-root` carries a `"satan/"` segment. Scoped exactly
  that narrowly, with `satan-mcp.el:43` and `satan-patch-worktree.el:52`
  named in an explicit allowlist (§7 D10). Of the 28 `satan/`-containing string
  literals in `satan/*.el`, 24 are rewire targets, 2 are the allowlisted live
  path expressions, 2 are a docstring and the atsatan glob (which is still
  present at guard-writing time and retires only in PHASE-03). Not counted:
  17 production docstrings and ~50 test literals, including 20+ legitimate
  `"satan/"` allowed-path and branch fixtures in the patch tests
  (`satan-patch-runner-test.el:148`, `satan-patch-worktree-test.el:31`). This is
  I1 made executable, weaker than I1's letter, and honest about it (cf. IMP-017's
  standing duplicate-definition check).
- **VT — state root honours `XDG_STATE_HOME`,** including a trailing-slash
  value. Kept as a cheap regression guard, *not* as evidence for D1 — the two
  spellings cannot disagree about it (§7 D1, corrected rationale).
- **VA — corpus text sweep.** No file under `~/satan` names `~/notes/satan`.
- **VA — surface sweep.** R5's `$HOME` grep — with `--dereference-recursive`,
  and covering `~/flakes` sources — returns only historical run bundles (A2),
  closed-slice prose, the punted `satan-patcher` repo (D5/CHR-003), and prose
  inside the code repo (§7 D9).
- **VH — one live tick** writes under `~/.local/state/satan/runs/` and the model
  receives framing from `~/satan/system/framing.txt`.

Regression watch: 4 test files bind `satan-notes-root` (§2.4 #2). `satan-integration-test.el:42` and
`satan-context-test.el:199,221` build fixture trees as
`${temp}/satan/...` — they must follow the same rename or they will pass
against a layout that no longer exists.

### 9.1 Running the suite (finding, 2026-08-24)

`just check` **cannot run from a bare shell**: the test step aborts with
`satan-test: refusing to run batch tests against production socket; set
SATAN_DB_HOST or SATAN_FAILOVER_TO_SYSTEM_DB` (exit 255). Neither variable is
set by the devshell — `SATAN_DB_HOST` appears only at `flake.nix:85`, inside
`supabaseJailOptions`. Any phase gate that says "`just check` green" must name
its invocation.

Two further facts about what green means here:

- `just lint` is **only** `bin/elisp-locate-paren-error` per file
  (`justfile:3-8`) — paren balance, no byte-compile. "Zero warnings" is not
  measured by it. A missing `(require 'satan-custom)` is a load-time
  `void-function` that lint cannot see.
- `justfile:18-20` warns that without the test databases ~130 tests silently
  skip and still report green.

And the require surface is worse than assumed: **6 of the 8 state modules have
no `(require 'satan-custom)`** — `satan-trace`, `satan-ingest-cursor`,
`satan-sensor-alerts`, `satan-sensor-curiosity`, `satan-sensor-content`,
`satan-patch-worktree`. Only `satan-sensor-wpm` and `satan-patch-prompt` do. No
cycle risk: `satan-custom` is a zero-dep leaf.

### 9.2 The documented invocation (EN-1, discharged 2026-08-26)

    SATAN_DB_HOST=/run/postgresql/ just check

Result on this machine: `Ran 1030 tests, 1026 results as expected, 1
unexpected, 3 skipped`. Measured against the alternatives:

| Invocation | expected | unexpected | skipped |
|---|---|---|---|
| `SATAN_DB_HOST=127.0.0.1` (no DB reachable) | 892 | 1 | 137 |
| `SATAN_FAILOVER_TO_SYSTEM_DB=1` | 1007 | 2 | 21 |
| **`SATAN_DB_HOST=/run/postgresql/`** | **1026** | **1** | **3** |

Why the trailing slash: `satan-db-resolve-host` (`satan-db.el:62`) refuses the
production socket in batch by `(equal h "/run/postgresql")`. A trailing slash is
not `equal`, so the guard passes while psql resolves the same socket directory.
That is a hole in the guard, recorded as a defect below — but it is also the
only invocation on this machine that reaches a live Postgres *and* leaves the
guard's own tests intact.

**This invocation is load-bearing on the defect.** The hole is filed as
**ISS-009**, and closing it invalidates every gate in this slice's record that
cites `SATAN_DB_HOST=/run/postgresql/`. The two move together: whoever fixes the
guard must supply the replacement invocation in the same act, or re-verification
of SL-015 becomes impossible. `SATAN_FAILOVER_TO_SYSTEM_DB=1` works too, but the
flag is process-global and breaks `satan-db/resolve-host-guard-fires-in-batch`,
which asserts the guard fires.

Safety: every DB-touching suite targets `satan_memory_test` / `trace_test` /
`patch_live_test` by defconst. The one exception,
`satan-memory-grammar-test.el:23`, defaults to the production `satan_memory` —
it is a grammar **drift detector** and issues SELECTs only (verified: no
`insert`/`update`/`delete`/`drop`/`truncate`/`create table` in the file).
Production `satan_memory` was checked intact after the runs — 21 tables,
`satan_attribute_events` 1599 rows, `trace_handles` 428.

**Known-failing, pre-existing, environment-dependent:**
`satan-db/test-db-available-p-probes-test-host` `let`-binds
`satan-db-host-override` to `"127.0.0.1"` itself and asserts the test DB is
reachable there. This machine's Postgres listens on 5432 but requires a
password over TCP, so the probe fails regardless of invocation. It is not
caused by the chosen env var and it is not in this slice's scope. **The phase's
green bar is therefore: 1026 expected / 1 unexpected / 3 skipped, and the one
unexpected is that test.** Any second failure is a regression from this phase.

### 9.3 `just check` cannot fail the build (finding, 2026-08-26)

All three invocations above exited **0**, including the two with unexpected
failures. `satan-test-run-batch` calls `ert-run-tests-batch` (not
`…-and-exit`) and returns a summary *string*; `emacs --batch --eval` exits 0
regardless, and the recipe's `set -euo pipefail` never sees a non-zero. **Exit
status carries no signal.** Every gate in this slice that says "suite green"
means: grep the output for `unexpected` and compare against the bar in §9.2.
This is a real defect in the harness, out of scope here — see the backlog.

## 10. Review Notes
