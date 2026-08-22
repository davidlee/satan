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
`~/.local/state/satan/`, but no module owns that root: eight sites inline the
same `(or (getenv "XDG_STATE_HOME") …)` expression, in two divergent spellings
of the fallback. The relocation needs a state root regardless — `runs/` must
land somewhere — so naming it retires the clone in the same act
(design D1).

**Cohabitation costs.** The subtree holds 9,542 files / 145M — 9.4k of them
under the gitignored `runs/`. `~/.emacs.d/org/dl-denote.el` carries a
`denote-excluded-directories-regexp` prune whose sole purpose is to stop denote
walking that tree (~10s per `denote:` link-follow without it). Only 124 files
under `satan/` are tracked by the notes repo; the authored corpus is ~250K
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
   `"satan/"` prefix; the 8 cloned XDG expressions collapse into one.
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
| `~/.config/systemd/user/satan-patcher.service:9` | `SATAN_PATCHER_PROMPT` | |
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
  Nothing breaks — `satan-patcher.service:9` pins `SATAN_PATCHER_PROMPT` and
  that line *is* in scope. Tracked as CHR-003.

## Summary

## Follow-Ups

- **CHR-003** — retarget the `satan-patcher` prompt default (punted, §Non-Goals).
- **OQ-2** (design) — should `~/satan` own `build-system-prompt` rather than
  leaving the recipe in the notes justfile reading across repos?
- **OQ-3** (design) — should the `@satan` scan cover `~/satan` once the corpus
  is no longer nested inside the scanned tree?
