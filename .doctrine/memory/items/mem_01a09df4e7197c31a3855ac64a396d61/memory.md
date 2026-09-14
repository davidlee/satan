# SATAN's three roots: notes, corpus, state

SATAN resolves every path from three roots with distinct owners: satan-notes-root (~/notes, the user's, read-only to SATAN), satan-corpus-root (~/satan, SATAN-authored, own repo), satan-state-root (~/.local/state/satan, runtime, discardable)

| Root (defcustom) | Default | Owner | SATAN writes? | Versioned | Join |
|---|---|---|---|---|---|
| `satan-notes-root` | `"~/notes"` | the user | **no** — reads only | user's `~/notes` repo | `satan-notes-path` |
| `satan-corpus-root` | `"~/satan"` | SATAN (mind) | yes | own repo `~/satan` | `satan-corpus-path` |
| `satan-state-root` | `$XDG_STATE_HOME/satan` or `~/.local/state/satan` | runtime | yes | never | `satan-state-path` |

All three and their joins live in `satan/satan-custom.el` (the zero-dep leaf);
the joins share `satan--join`, which expands `~` once. Every path defcustom
(`satan-prompts-dir`, `satan-system-framing-file`, `satan-tools-descriptions-dir`,
`satan-hippocampus-dir`, `satan-motive-file`, `satan-inbox-file`,
`satan-runs-dir`, …) is a join off one of them — never a hand-built
`(expand-file-name "satan/x" …)`. Package code/data is a fourth thing,
`satan--root` (self-location, not configurable).

- **Corpus:** prompts, `system/` scaffold + framing, tool descriptions,
  motives, hippocampus, inbox, proposals, patch-agent prompt. Model-facing text
  SATAN reads *and* edits (self-edit-mind). Commit with `just commit` in
  `~/satan`.
- **State:** run bundles (`runs/<date>/<id>/`), sensor cursors, `log/wpm/`,
  patch-agent logs/worktrees. Deleting it costs history, not correctness.
- **Notes:** journal, weekly, inbox.org, denote files. SATAN perceives these;
  its writes go to its own corpus, never here.

## Why the split

- **Ownership, not convenience.** Until SL-015 the corpus lived at
  `~/notes/satan`, so SATAN's authored content rode the user's daily
  `git add .` and its runtime trees had to be gitignored inside the user's
  repo. The user's notes are the thing SATAN observes; mixing its own writes
  into them blurs observation with authorship.
- **No fallback (SL-015 D2/P4).** `satan-corpus-root` is not derived from
  `satan-notes-root` and nothing falls back to the old location — for framing
  text a wrong-but-readable path is worse than an error.
- **No symlink (D4).** `~/notes/satan` does not exist; any consumer still
  reading it fails loudly.
- **Hippocampus is corpus, not state (D3)** — it is the memory trail SATAN
  writes deliberately, so it is versioned.

## Not a root

- `$XDG_RUNTIME_DIR/satan/mcp` (`satan-mcp.el`) — ephemeral sockets, a genuine
  fourth location outside all three (D10).
- Panopticon's `~/.local/state/behaviour/…` (segments, content) — SATAN reads
  it but does not own it, so it gets no SATAN root (D1).

## Consumers outside the package

The runtime jail binds `$HOME/satan/hippocampus`
([[mem.fact.satan.runtime-jail-deploys-from-github-input]]); dev jails bind
`$HOME/satan` at `/workspace/corpus`; shells read `~/satan/motd.txt`;
`~/notes/justfile build-system-prompt` cats `~/satan/system/scaffold.txt` into
`.pi/SYSTEM.md`; the satan-patcher unit sets `systemPromptFile` in
`~/flakes/modules/home/linux/satan-patcher.nix`. Moving a root means following
all of these — sweep with `grep -rIl --dereference-recursive`
([[mem.pattern.nixos.grep-misses-symlinked-dotfiles]]).
