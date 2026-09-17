# Corpus relocation: SATAN model-facing corpus leaves ~/notes for a standalone repo

## Context

SATAN's model-facing corpus (prompts, system framing/scaffold, tool
descriptions, motives, hippocampus, patch-agent prompt, proposals) lives at
`~/notes/satan/`, a subtree of the personal notes corpus. SL-012 separated
*code* from the Emacs config and introduced `satan-notes-root` as the one
config-root knob (D4, Axis-1); it explicitly declared model-facing content
"already separated; not moving" (`slice-012.md` §Non-Goals).

That separation is incomplete in two ways.

**One knob, two concepts.** `satan-notes-root` serves both the user's notes
corpus *and* SATAN's own corpus. 16 production sites resolve owned paths as
`(expand-file-name "satan/<x>" satan-notes-root)` — the `"satan/"` segment
spelled as a bare literal, with no name for the thing it denotes. Two consumers
(`satan-tools-notes-root`, `satan-tools-atsatan-root`) legitimately mean the
*user's* notes and default off the same symbol, so the conflation is not
merely cosmetic: the two roots have opposite ownership (SATAN writes one, only
reads the other) and `satan-tools-atsatan` already carries an
`!**/satan/**` exclude glob to undo the nesting at scan time.

A **third** ownership class is unnamed too. Runtime state already lives at
`~/.local/state/satan/`, but no module owns that root: eight defcustoms inline
the same `(or (getenv "XDG_STATE_HOME") …)` expression, in two divergent spellings
of the fallback. The relocation needs a state root regardless — `runs/` must
land somewhere — so naming it retires the clone in the same act
(design D1).

**Cohabitation costs.** The subtree holds 9,542 files / 145M — 9.4k of them
under the gitignored `runs/`. `~/.emacs.d/org/dl-denote.el` carries a
`denote-excluded-directories-regexp` prune whose sole purpose is to stop denote
walking that tree (~10s per `denote:` link-follow without it). Only 124 files
under `satan/` are tracked by the notes repo; the authored corpus is 528K
hiding inside a 145M directory.

Destination: `~/satan`, a new standalone git repo — corpus provenance carried
over by `git filter-repo --subdirectory-filter`. Runtime run transcripts split
off to `~/.local/state/satan/runs`, beside the patcher state dirs that already
live there.

## Scope & Objectives

1. **Name the roots.** New `satan-corpus-root` and `satan-state-root`
   defcustoms in `satan-custom.el` (the zero-dep leaf that already owns
   `satan-notes-root`), plus `satan-corpus-path` / `satan-state-path` join
   helpers mirroring `satan-notes-path`. The 16 corpus sites lose their literal
   `"satan/"` prefix; the 8 cloned XDG expressions collapse into one
   (a further two resolve off the same expression but their leaf is
   `behaviour/` — panopticon's state, read-only to SATAN, out of scope by
   ownership; design §2.2b).
   `satan-notes-root` survives unchanged for the two genuine user-notes
   consumers and the journal/weekly/inbox derivations.
2. **Split runtime from authored.** `satan-run`'s two directory defcustoms
   (`runs`, `hippocampus`) re-anchor: run transcripts to a run-state root under
   `~/.local/state/satan`, hippocampus stays authored corpus. `~/satan` then
   needs no `.gitignore`.
3. **Move the corpus.** Subtree-split `~/notes:satan/` into `~/satan` with
   history; remove it from the notes repo.
4. **Follow every consumer** — the inventory below is the scope boundary.
5. **Retire the workarounds** the nesting forced: the denote exclusion regexp
   and the atsatan `!**/satan/**` exclude glob.

### Consumer inventory (survey 2026-08-22)

| Surface | Refs | Note |
|---|---|---|
| `satan/*.el` corpus sites | 16 | via new `satan-corpus-path` |
| `satan/*.el` cloned XDG state sites | 8 | via new `satan-state-path` |
| `satan/test/*.el` | 6 files bind `satan-notes-root` | some become `satan-corpus-root` |
| `flake.nix:134` | jail `--bind $HOME/notes/satan/hippocampus`; `--ro-bind $HOME/notes` → `/satan/notes` | corpus currently reachable *through* the notes mount — needs its own bind |
| **authored corpus text** — 8 files name their own old path to the model | 8 | `system/scaffold.txt`, 3 `tools/*.md`, 4 `prompts/*.txt` |
| `~/notes/justfile:12,14` | 2 | `build-system-prompt` cats corpus into `.pi/SYSTEM.md` |
| ~~`satan-patcher` (separate repo)~~ | 5 | **out of scope** → CHR-003 |
| `~/flakes/modules/home/linux/satan-patcher.nix` | add `systemPromptFile` (the unit is a non-editable /nix/store symlink and carries no pin) | |
| `~/flakes/modules/home/linux/sway.nix:12` | `wpm-archive-yesterday` hardcoded TSV path; timer active | |
| `~/.config/zsh/init.zsh:161` | motd read | |
| `~/.config/waybar/wpm-status.py:43` | **writes** the wpm TSV | live writer |
| `~/.emacs.d/org/dl-denote.el:15` | exclusion regexp | delete |
| `docs/perceptual-design.md:227` | motives path | |
| memory corpus | satan orientation, `mem.pattern.satan.corpus-integration-skip-unless` | |

## Non-Goals

- **`satan-notes-root` itself.** The user notes corpus stays at `~/notes`; its
  root knob, journal/weekly/inbox derivations, and the two user-notes consumers
  are untouched except where they stop meaning "SATAN's corpus".
- **Corpus content semantics.** No prompt, framing, or tool description changes
  what it *says*. Path strings inside model-facing text are in scope, though —
  8 authored files name `~/notes/satan/...` to the model and would otherwise
  become lies (design D6).
- **Module extraction.** This is not a POL-001 seat decision and moves no
  authority item (ADR-017 §3 ledger unaffected). Rust daemons out of scope.
- **Closed-slice prose.** SL-002 / SL-012 notes and plans cite
  `~/notes/satan/...` as historical record; they are not rewritten.
- **Patcher log/worktree roots.** Already under `~/.local/state/satan`; they
  re-anchor to `satan-state-root` but do not move.
- **`satan-patcher` itself** (separate repo — Go default, nix module, 3 docs).
  Punted at the user's direction 2026-08-22: not in active use, may be replaced.
  Tracked as CHR-003. **Correction 2026-08-24:** the claim that "nothing breaks
  because `satan-patcher.service:9` pins `SATAN_PATCHER_PROMPT`" was false — the
  unit is a non-editable `/nix/store` home-manager symlink carrying no pin, so
  the daemon runs on the punted module's own stale default. The fix is one line
  in `~/flakes/modules/home/linux/satan-patcher.nix`, which is *outside* the
  punted repo and *is* in scope (design D5, PHASE-03 EX-10). Also newly in
  scope: `~/flakes/modules/home/linux/sway.nix:12` (design R8).

## Summary

Delivered. SATAN now resolves every path it owns through one of **three named
roots**, and the corpus lives in its own repo.

```
~/notes (user's, read-only)    ~/satan (SATAN's, versioned)    ~/.local/state/satan
  journal/ weekly/ inbox.org     prompts/ system/ tools/         runs/ log/wpm/
                                 hippocampus/ proposals/         sensor *.json
                                 motives.org motd.txt            tick-trace-*.jsonl
  satan-notes-root               satan-corpus-root               satan-state-root
  satan-notes-path               satan-corpus-path               satan-state-path
```

The split is by **ownership**, not by location: SATAN reads the first, authors
the second, and discards the third. A fourth class — panopticon's
`~/.local/state/behaviour/` — is read but not owned, so it deliberately gets no
root (§2.2b / D1).

What landed, by phase:

1. **PHASE-01** named the roots. Two defcustoms and two join helpers in
   `satan-custom.el` (still a zero-dependency leaf), 24 call sites rewired
   across 22 variables — the 16 that spelled `"satan/"` as a bare literal below
   the notes root, and the 8 that each inlined their own copy of the
   `XDG_STATE_HOME` expression in two divergent spellings. Pure refactor:
   both new defaults resolved to the existing on-disk locations, and every one
   of the 24 paths came out byte-identical.
2. **PHASE-02** split runtime from authored. `runs/` (9.4k files, 145M) and
   `log/wpm/` moved to the state root by rename; `hippocampus/` stayed corpus,
   because it is the memory trail SATAN writes deliberately (D3). Two external
   writers followed — `wpm-status.py` and `sway.nix`'s archive timer.
3. **PHASE-03** cut the corpus over. `~/notes:satan/` became `~/satan`, a
   standalone repo carrying its history through `git subtree split`, with the
   8 authored files that name their own path to the model retargeted in the
   same act (D6/F2). No transitional symlink (D4), so a missed consumer would
   fail loudly rather than quietly keep working — and two did, within the
   phase. Both nesting workarounds retired: the denote exclusion regexp and the
   atsatan `!**/satan/**` glob (D8).
4. **PHASE-04** swept the record — docs, docstrings rewritten to name the
   defcustom rather than the path, the memory corpus, and a whole-`$HOME` sweep
   that classified 2835 hits with none left unaccounted.

`~/notes/satan` no longer exists. Nothing stands in for it.

**Out of scope, on the record:** prose inside the code repo (D9, residue in
CHR-006), historical run bundles that embed the old absolute path as frozen
evidence (A2), and the `satan-patcher` repo (D5, CHR-003) — whose one live
consequence, the daemon's prompt path, was fixed at its real editable surface
outside that repo.

## Follow-Ups

Filed during execution and audit. None blocks closure.

| id | kind | status | what |
|---|---|---|---|
| CHR-003 | chore | open | Retarget the `satan-patcher` prompt default (punted at the user's direction, D5) |
| CHR-004 | chore | open | Self-edit prompts' `allowed_paths` and check globs still describe the pre-SL-012 layout — model-facing text, the same class F2 exists to prevent |
| CHR-005 | chore | **resolved** | `~/satan` needed a remote. Done: `satan-corpus`, pushed |
| CHR-006 | chore | open | 16 `docs/` files still name `~/notes/satan` — the D9 residue |
| ISS-008 | issue | open | `just check` exits 0 with any number of failures |
| ISS-009 | issue | open | The production-socket batch guard is defeated by a trailing slash. **Coupled to design §9.2** — fixing it invalidates this slice's documented invocation |
| ISS-010 | issue | open | Empty `XDG_STATE_HOME` is treated as set, defeating the state-root fallback |
| ISS-011 | issue | open | `satan-attrd` rejects the sensor outcome reason `content_backlog` |
| ISS-012 | issue | open | motd and morning runs fail at turn 0 on an expired API key; tick runs succeed |
| ISS-013 | issue | open | Concurrent `just check` runs clobber the shared test databases (found in audit) |
| IMP-019 | improvement | open | Should the `@satan` scan cover `~/satan` now that the corpus is outside the scanned tree? (design OQ-3) |

**OQ-2 — settled, no item.** Should `~/satan` own `build-system-prompt` rather
than leaving the recipe in the `~/notes` justfile reading across repos? No: D7
stands. The recipe's artefact is `~/notes/.pi/SYSTEM.md`, consumed by jailed-pi
run from `~/notes`; separating the recipe from its artefact buys nothing and
costs a second cross-repo read.
