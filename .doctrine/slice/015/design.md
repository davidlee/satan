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
14 files.

### 2.2 The state-root clone

Those XDG hits are their own duplication. Nine defcustoms inline the same
resolution, in two spellings of the same fallback:

| File:line | Leaf | Fallback spelling |
|---|---|---|
| `satan-trace.el:37` | `satan/` | `".local/state" "~"` |
| `satan-ingest-cursor.el:52` | `satan/ingest-cursor.json` | `".local/state" "~"` |
| `satan-sensor-alerts.el:22` | `satan/notified.json` | `".local/state" "~"` |
| `satan-sensor-wpm.el:26` | `satan/sensor-wpm.json` | `".local/state" "~"` |
| `satan-sensor-curiosity.el:18` | `satan/sensor-curiosity.json` | `".local/state" "~"` |
| `satan-sensor-curiosity.el:26` | (second file) | `".local/state" "~"` |
| `satan-sensor-content.el:27` | `satan/sensor-content.json` | `".local/state" "~"` |
| `satan-patch-worktree.el:18` | `satan/patch-agent/worktrees/` | `"~/.local/state/"` |
| `satan-patch-prompt.el:28` | `satan/patch-agent/logs/` | `"~/.local/state/"` |

`~/.local/state/satan/` already exists and holds every one of those artefacts.
The convention is real and in production; only its name is missing.

### 2.3 Cohabitation costs

| Cost | Evidence |
|---|---|
| Authored corpus hidden in a runtime tree | `satan/` = 9,542 files / 145M; `satan/runs/` alone is 9.4k files / 145M and is gitignored (`~/notes/.gitignore:1 = /satan/runs`). The tracked corpus is **124 files / ~250K**. |
| denote workaround | `~/.emacs.d/org/dl-denote.el:15` sets `denote-excluded-directories-regexp` solely to stop denote's uncached tree walk from statting ~10k non-note files on every `denote:` link-follow (~10s per link, per its own comment). |
| atsatan workaround | `satan-tools-atsatan.el:32` carries `'("!**/satan/**")` to exclude SATAN's corpus from the `@satan` scan of the user's notes — an exclusion needed only because the two are nested. |
| Ownership inversion | SATAN *writes* its corpus; it only *reads* the user's notes. The write target is nested inside the read-only one, and the jail encodes exactly that inversion (`--ro-bind $HOME/notes` + a narrower `--bind` punching hippocampus back to read-write). |

### 2.4 Consumer surfaces

Eleven surfaces reference `~/notes/satan`; one is punted (§7 D5).

| # | Surface | Refs | In scope |
|---|---|---|---|
| 1 | `satan/*.el` corpus sites | 16 (§2.1) | yes |
| 1b | `satan/*.el` cloned XDG-state defcustoms | 9 (§2.2) | yes |
| 2 | `satan/test/*.el` | 6 files bind `satan-notes-root`; `satan-run-test.el:197` asserts `/tmp/nr/satan/hippocampus` | yes |
| 3 | **Authored corpus text** — 8 files name their own old path to the model: `system/scaffold.txt`, `tools/{inbox_append,hippocampus_write,proposal_stage}.md`, `prompts/{motd,morning,self-edit-mech,self-edit-mind}.txt` | 8 | yes |
| 4 | `flake.nix:134` jail bind | 1 | yes |
| 5 | `~/notes/justfile:12,14` — `build-system-prompt` cats `satan/system/scaffold.txt` + `satan/prompts/interactive.txt` into `.pi/SYSTEM.md` | 2 | yes |
| 6 | `~/.config/waybar/wpm-status.py:43` — **writes** the wpm TSV | 1 | yes |
| 7 | `~/.config/zsh/init.zsh:161` — motd read | 1 | yes |
| 8 | `~/.config/systemd/user/satan-patcher.service:9` — pins `SATAN_PATCHER_PROMPT` | 1 | yes |
| 9 | `~/.emacs.d/org/dl-denote.el:15` — exclusion regexp | 1 | yes (retire) |
| 10 | `docs/perceptual-design.md:227` + memory corpus | 3 | yes |
| 11 | `~/dev/satan-patcher` — Go defaults, nix module, 3 docs | 5 | **no** → CHR-003 |

### 2.5 Baseline

`just check` green at `043fb21`. `~/notes` working tree: 4 modified + 31
untracked under `satan/` (must be committed before any split — §5.4 S0).

## 3. Forces & Constraints

- **F1 — Live writers.** waybar's wpm logger writes every minute;
  `satan-tick.timer`, `satan-motd.timer`, `satan-morning.timer` and
  `satan-attrd.service` are active. A move with writers running strands rows in
  the old tree.
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
- **P2 — One root per ownership class.** Read-only user data, SATAN-authored
  content, and SATAN runtime state are three classes. Three roots, three joins.
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

Post-split `~/satan` carries no `.gitignore`.

### 5.4 Lifecycle, Operations & Dynamics

Cutover, ordered. F1 forces writers down first; F7 makes every move instant.

- **S0 — Quiesce and clean.** Commit the 4 modified + 31 untracked corpus files
  in `~/notes`. `systemctl --user stop satan-{tick,motd,morning}.timer
  satan-{attrd,patcher}.service`; stop the waybar wpm module. Close Emacs, or
  plan to re-eval `satan-custom` after S3.
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
- **S4 — Restart and verify.** `just check` green; restart units; one live tick
  writes under `~/.local/state/satan/runs/`; `~/notes/satan` gone.

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
  in `satan/harness/*.py` beyond a test fixture string.
- **A2 — Historical run bundles keep stale absolute paths.** 2,208 files under
  `runs/` embed `~/notes/satan/...`. They are frozen evidence; rewriting them
  would falsify the record. Accepted, not fixed.
- **E1** `satan-self-edit-mind-roots` is a `defcustom` whose *default* is
  computed from the root; a user who has customised it keeps a stale value.
  Same for the other 15. Setting `satan-corpus-root` after load does not
  retroactively move them — restart, don't `setq`.
- **E2** Unexpanded tilde into `call-process` (F5): `satan-corpus-root` ships
  the literal `"~/satan"` for symmetry with `satan-notes-root`, so the join
  helpers must `expand-file-name` the root exactly as `satan-notes-path` does.

## 6. Open Questions & Unknowns

- **OQ-1** Does `git subtree split -P satan` produce usable history over this
  repo's log, or does the daily-blob commit style (`git add .` per §justfile
  `commit`) make it near-worthless? Resolve empirically at S1 before committing
  to it; filter-repo is the fallback.
- **OQ-2** Should `~/satan` carry its own `justfile` owning
  `build-system-prompt`, rather than leaving the recipe in `~/notes` reading
  across repo boundaries (§7 D7 takes the conservative option)?
- **OQ-3** `satan-tools-atsatan-root` defaults to the whole notes corpus. With
  the corpus gone, should the `@satan` scan also cover `~/satan`? Argument for:
  proposals and motives are exactly where a `@satan` marker would be dropped.
  Out of scope here; capture as backlog if wanted.

## 7. Decisions, Rationale & Alternatives

- **D1 — Three named roots, not two.** The move needs a state root anyway
  (`runs/` must land somewhere), and naming it retires the 9-fold clone of §2.2
  in the same act. *Alternative:* add `satan-corpus-root` only and leave the
  clones — rejected: it leaves the third ownership class unnamed while
  demonstrably in use, and the clone's two divergent fallback spellings are a
  latent bug waiting on an `XDG_STATE_HOME` that ends in a slash.
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
  consumer to whenever it next runs, and the surface inventory (§2.4) is
  complete enough not to need a net.
- **D5 — `satan-patcher` punted to CHR-003** (user direction, 2026-08-22: not
  in active use, may be replaced). Its 5 refs stay stale. Nothing breaks:
  `satan-patcher.service:9` pins `SATAN_PATCHER_PROMPT` explicitly and *that
  line is in scope*, so the running daemon keeps resolving. Only an unpinned
  default — fresh install, manual invocation, nix module without `prompt =` —
  would dangle. The elisp-side reader (`satan-patch-prompt.el:22`) is in scope
  as one of the 16.
- **D6 — The 8 authored corpus files are in scope.** This narrows the slice's
  "corpus content is a non-goal": content *semantics* are untouched, but path
  strings inside model-facing text are part of the move (F2). Reconcile the
  scope doc.
- **D7 — `build-system-prompt` stays in the `~/notes` justfile, with retargeted
  sources.** Its output is `~/notes/.pi/SYSTEM.md`, consumed by jailed-pi run
  from `~/notes`; moving the recipe would separate it from its artefact. See
  OQ-2.
- **D8 — Retire both nesting workarounds** (denote regexp, atsatan glob). They
  have no remaining referent, and the denote regexp would otherwise silently
  exclude any future legitimately-named `satan/` note directory.

## 8. Risks & Mitigations

| id | Risk | Mitigation |
|---|---|---|
| R1 | Writers strand rows in the old tree mid-move | S0 quiesce; verify with `systemctl --user list-timers` before S1 |
| R2 | `git subtree split` yields useless history (OQ-1) | Evaluate at S1; `nix run nixpkgs#git-filter-repo` fallback; both before any `git rm` |
| R3 | Dirty `~/notes` tree (4 M + 31 ??) loses uncommitted corpus edits in the split | S0 commits first — hard gate |
| R4 | A running Emacs holds old defcustom values, writes to the dead path | Restart Emacs at S4; E1 says restart, never `setq` |
| R5 | A consumer missed from §2.4 | Post-cutover `grep -rIl "notes/satan" ~ --exclude-dir=.git` over `$HOME` config trees as a VA check; the old path must not exist, so any surviving reader errors loudly (D4) |
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
- **VT — no `"satan/"` literal survives.** A grep-shaped assertion over
  `satan/*.el`: no path expression contains a `"satan/"` segment. This is I1
  made executable and is the recurrence guard (cf. IMP-017's standing
  duplicate-definition check).
- **VT — state root honours `XDG_STATE_HOME`,** including a trailing-slash
  value, closing the §2.2 spelling divergence.
- **VA — corpus text sweep.** No file under `~/satan` names `~/notes/satan`.
- **VA — surface sweep.** R5's `$HOME` grep returns only historical run bundles
  (A2) and closed-slice prose.
- **VH — one live tick** writes under `~/.local/state/satan/runs/` and the model
  receives framing from `~/satan/system/framing.txt`.

Regression watch: `satan-integration-test.el:42` and
`satan-context-test.el:199,221` build fixture trees as
`${temp}/satan/...` — they must follow the same rename or they will pass
against a layout that no longer exists.

## 10. Review Notes
