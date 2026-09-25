# CHR-010: Rename the corpus root to ~/satan-corpus and retarget every reference

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

The corpus directory `~/satan` is renamed to `~/satan-corpus`, matching its own
remote (`github.com:davidlee/satan-corpus`) and freeing the basename `satan` for
the mechanism repo alone. Whichever jail you are in, a bare `/workspace/satan`
then means the mechanism; the mind is `/workspace/satan-corpus`. The mount is
basename-derived, so renaming the directory moves it inside every corpus jail.
`~/satan` is deleted, not symlinked (SL-015 D4: no fallback, no symlink — a
leftover link masks the move instead of failing).

Two laws this item must not break:

1. **`satan-corpus-root` is a literal with no derivation** (SL-015 D2). It is
   spelled in exactly one place — `satan/satan-custom.el` — and every other
   corpus path is a `satan-corpus-path` join. The rename is therefore one
   functional edit plus prose, not a sweep of code.
2. **The runtime jail deploys from the GitHub flake input**, not the working
   tree ([[mem.fact.satan.runtime-jail-deploys-from-github-input]]). A
   `flake.nix` edit that binds `$HOME/satan/hippocampus` converges only on push
   + flake update. Until then the deployed runtime still reads the old path.

## Already landed (2026-09-25, uncommitted at item creation)

- `~/satan` → `~/satan-corpus` on the host; the directory is the moved repo.
- Mechanism `flake.nix`: `corpusJailOptions` is now
  `(rw-bind "/home/david/satan-corpus" "/workspace/satan-corpus")`, replacing the
  `--bind "$HOME/satan" "/workspace/corpus"` raw arg.
- Corpus `flake.nix`: `ro-bind … "/workspace/satan-corpus/.pi"` (was
  `/workspace/satan/.pi`); mechanism joins `workspaceDeps` by basename and so
  still mounts at `/workspace/satan`.
- A harness reload made the new binds live.

## Remaining

### Mechanism (`~/dev/satan`, this repo)

| Ref | Kind | Change |
|---|---|---|
| `satan/satan-custom.el:86` | functional | `satan-corpus-root` default `"~/satan"` → `"~/satan-corpus"` |
| `satan/test/satan-custom-test.el:55,57,138,153,158` | functional | literal pins + default assertion |
| `satan/satan-context.el:601` | prose | docstring |
| `satan/test/goad-fixtures/README.md:3,11` | prose | corpus repo path + regeneration recipe |
| `docs/governance.md` (28), `docs/perceptual-design.md` (6) | prose | mind/mechanism tables, tool land, self-edit roots |
| `flake.nix:145` | functional | `$HOME/satan/hippocampus` → `/satan/hippocampus` runtime-jail bind |
| `flake.nix:96-100` | done | see above |

Governance inside this repo (edit via the CLI, not raw files):

- `.doctrine/project-orientation.md:27,64` — "Three roots, never mixed".
- Memories: `mem.concept.satan.three-roots` (its body is the Onboarding essay
  `doctrine boot` injects every session), `mem.signpost.satan.orientation`,
  `mem.pattern.satan.corpus-integration-skip-unless`,
  `mem.fact.satan.patch-job-contract`,
  `mem.fact.satan.runtime-jail-deploys-from-github-input`.
- `SPEC-002`: `.doctrine/spec/tech/002/diagrams.py:209,227,290` plus regenerated
  `context.html`, `end-state.html`, `composition.html`.
- `REQ-018` (`.doctrine/requirement/018/requirement-018.md:13`) cites
  `$HOME/satan/hippocampus` as the known host-fact violation.
- Historical, leave as written: `slice/015`, `slice/016`, `review/*`,
  `knowledge/decision/*`, `observations/*`.
- Also stale from the *previous* generation, swept here: `docs/` still carries
  `~/notes/satan` prose (CHR-006's whole scope).

### Corpus repo (`~/satan-corpus`)

- `flake.nix:60` — done (mount target).
- `iteration/collect.sh:24` — `CORPUS=${SATAN_CORPUS:-$HOME/satan}` hard
  fallback; `:11-12` comments.
- `iteration/satan-iterate.md` (8) — canonical prompt, incl. its
  `bash "$HOME/satan/iteration/collect.sh"` pre-step.
- `iteration/state.md` (14), `iteration/README.md`,
  `iteration/handover-20260925.md` (9).
- `AGENTS.md:18,43,72-73,113` — host↔jail map and traps; must state the new
  mount names (`/workspace/satan-corpus` mind, `/workspace/satan` mechanism).
- **Model-facing text — this is what changes SATAN's behaviour**:
  `system/scaffold.txt:20-24` (the system prompt's writable surfaces),
  `prompts/self-edit-mind.txt:5-7,14,19,30,64` (including `repo: "~/satan"`,
  which is the patch job's target repo), `prompts/self-edit-mech.txt:34`,
  `prompts/motd.txt:5-6`, `prompts/morning.txt:4`,
  `tools/{proposal_stage,inbox_append,hippocampus_write}.md`.
- `proposals/*.org` — dated records; leave.

### `~/notes`

- `justfile:11,13` — **functional**: `build-system-prompt` cats
  `~/satan/system/scaffold.txt` and `~/satan/prompts/interactive.txt` into
  `.pi/SYSTEM.md`; on a missing path it writes an empty prompt, silently.
- `.pi/SYSTEM.md` — generated; regenerate after the justfile.
- `.pi/agent/prompts/satan-iterate.md` — installed copy of the corpus file.
- `~/notes.skeleton-20260925/satan` — empty skeleton dir; nothing to change.

### `~/.emacs.d`

Nothing functional: `apps/dl-satan.el` pins `satan-notes-root` only, and no
config anywhere names `satan-corpus-root`, so the package default is the single
lever. `recentf`, `places`, `project-window-list` hold stale entries (self-heal).
Drive-by: `_claude/settings.local.json:33,34,49` still allowlist
`~/notes/satan/**` (dead since SL-015); `.emacs.d/.doctrine/memory/*` likewise.
`~/.pi/extensions/satan.ts` uses `$XDG_RUNTIME_DIR/satan/mcp/mcp.sock` —
unrelated, unchanged.

### `~/flakes`

- `modules/home/linux/satan-patcher.nix:33` — **functional**:
  `systemPromptFile = "%h/satan/patch-agent/prompt.md"`.
- `SATAN.md:18,70,73,107` — authoritative host facts (corpus row, jail table).
- `modules/home/linux/goad.nix:13,19` — comments.

### Not verifiable from a jail (no read of these paths)

`~/dev/satan-patcher` and `~/dev/goad` own defaults (`CHR-003` covers the
patcher's five sites); `~/.config/goad/config.toml` names the backend command
(`~/satan/goad/backend.py`) as does `~/.config/goad/env` and any hand-written
`goad.service`. Check on the host.

## Done when

- `git grep -n 'satan([^-a-zA-Z]|$)'` and `$HOME/satan` find nothing outside
  historical records (`slice/`, `review/`, `proposals/`, `knowledge/decision/`)
  in any of the four repos.
- `just check` green in the mechanism repo; `satan-custom-test.el` asserts the
  new default.
- A fresh `doctrine boot` snapshot names `~/satan-corpus` and no `~/satan`.
- The corpus jail comes up with the mind at `/workspace/satan-corpus` and the
  mechanism at `/workspace/satan`.

## Neighbours

Supersedes CHR-006 (its remaining `docs/` prose sweep is this item's, at the
newer target path). Related: CHR-003 (satan-patcher repo defaults — a separate
repo, deferred), CHR-007 (stale `dl-satan-*` names in corpus tool text, same
files), IMP-019, IMP-028, IMP-031.

## Progress — 2026-09-25

Landed, uncommitted:

| Surface | What changed |
|---|---|
| mechanism `satan/satan-custom.el` | `satan-corpus-root` → `"~/satan-corpus"` (the one functional edit) |
| mechanism `satan/test/satan-custom-test.el` | literal pins + the standalone-default assertion |
| mechanism prose | `satan-context.el` docstring, `goad-fixtures/README.md`, `docs/{governance,perceptual-design,data-collection,protocol,memory/design,patch/brief,patch/plan,at-satan/design,at-satan/plan}.md` |
| mechanism `flake.nix` | runtime-jail hippocampus bind → `$HOME/satan-corpus/hippocampus`; corpus-jail rationale comment |
| governance | `.doctrine/project-orientation.md`; 5 memories; SPEC-002 (`diagrams.py` + regenerated HTML); REQ-018 rationale |
| corpus | `prompts/*`, `system/scaffold.txt`, `tools/*`, `iteration/{collect.sh,satan-iterate.md,README.md,state.md,handover-20260925.md}`, `AGENTS.md` |
| `~/notes` | `justfile`; installed `satan-iterate.md`; `.pi/SYSTEM.md` regenerated |
| `~/flakes` | `satan-patcher.nix` (`systemPromptFile` + comment), `goad.nix` comments, `SATAN.md` (corpus table + host↔jail table) |

Evidence: `just lint` clean; suite 1132 passed / 178 skipped / 0 unexpected.
The skip set is byte-identical to the pre-change run (verified by temporarily
reverting the default) — the change adds no silent skips. `.doctrine/state/boot.md`
regenerated: it now names `~/satan-corpus` everywhere except the one deliberate
historical line in `mem.concept.satan.three-roots` that records the old root's
deletion.

### Open

1. **Mechanism posture in the corpus jail (needs a decision).** `workspaceDeps`
   now mounts `~/dev/satan` rw at `/workspace/satan` while the legacy
   `ro-bind … /workspace/satan-src` is still in the corpus `flake.nix`. That
   silently weakens the documented posture ("mechanism changes never by edit");
   the corpus `AGENTS.md` and `handover-20260925.md` now mark the mode `rw*` and
   name the open question rather than assert either.
2. **CHR-003's five sites, located and left.** `~/dev/satan-patcher` is reachable
   from the dev jail: `cmd/satan-patcher/main.go:52`, `nix/module.nix:74`,
   `README.md:126,148`, `docs/contract.md:108`, `docs/handover.md:213` — all still
   `~/notes/satan/…`, now two generations stale. Not changed: CHR-003 owns them
   and the user deferred it. The flakes pin *was* changed, so the divergence is
   now visible rather than latent.
3. **Not reachable from a jail.** `~/.config/goad/config.toml` (names the backend
   command), `~/.config/goad/env`, and any hand-written
   `~/.config/systemd/user/satan-patcher.service` pin. Check on the host.
4. **Deliberately left stale.** `.emacs.d/_claude/settings.local.json:33,34,49`
   (archived `_claude` allowlists — retargeting would re-arm dead `Read`
   permissions); `.emacs.d/.doctrine/memory/*` (that repo's own memories, already
   stale from SL-015); `.doctrine/{slice,review,backlog,knowledge,observations}`
   and `docs/{review,patch/archive,refactor}` dated records, plus the corpus's
   `proposals/` and `hippocampus/` — left as written, per the CHR-006 rule
   ("dated records may stay").

### Workflow note

Every `doctrine` write verb in this jail refuses at the reservation step
(`fetch origin` cannot exec the disabled git-ssh), needing
`DOCTRINE_RESERVATION_FALLBACK=1`. Worth a backlog item or an observation if it
keeps costing a round-trip.
