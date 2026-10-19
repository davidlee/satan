# ISS-046: Self-edit and tick patch lanes are refused after the SL-023 cutover (runner knows mode fix and repo goad-walk only; corpus producer prompts still pass old modes and absolute paths)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

After the SL-023 cutover the only patch lane that runs is the closure run's
(mode `fix`, repo `goad-walk`). SATAN's own lanes are refused. Three layers sit
between a lane and a running job; only the first is done.

```
 layer                       where                                    state (2026-10-19)
 1 room holds the clones     /srv/fleet flake.nix rooms.assistant     13 targets, clones present in /work
                                                                       (user-verified); satan, satan-corpus MISSING
 2 runner knows repo + mode  ~/flakes features/satan/runner.nix       only repo.goad-walk, mode.fix
                             → ~/.config/satan-runner/config.toml
 3 producers send what the   Emacs satan-tools-patch-modes ("fix");   prompts send old modes and repo as a path
   runner accepts            corpus prompts                           ("~/dev/satan", "~/satan-corpus", absolute)
```

Refusal sites: the tool schema's `mode` enum (layer 3) refuses first; the
runner refuses an unknown repo or mode with `invalid_request` (layer 2).

## Lanes

| mode | lane | repo (runner name) | allowed_paths |
|---|---|---|---|
| `self-edit-mech` | SATAN edits its code | `satan` | `satan/` |
| `self-edit-mind` | SATAN edits its model-facing text | `satan-corpus` | `prompts/`, `system/`, `tools/` |
| `tick-agent` | a tick delegates code work | any configured repo | narrowest per job |
| `fix` | closure-run mode | goad-walk | — |

## Rulings (user, 2026-10-19)

- Runner modes equal SATAN's lane names (one name per lane, end to end).
- No per-lane budgets yet: each `[mode.*]` table is empty; `[maxima]` applies.
- The room holds `satan`, `satan-corpus` and `notes` (`notes` already present).

## Work

1. **Fleet** (`/srv/fleet`): add targets `satan` and `satan-corpus` (each a
   tool-set flake input + `targets/<name>.nix`); `satan-corpus` needs little
   beyond git. Rebuild and restart the room; confirm the clones in `/work`.
2. **Runner config** (`~/flakes/features/satan/runner.nix`): a `repo.<name>`
   entry per room target (`path`, `guest_path = /work/<name>`,
   `default_branch`, `quarantine = /var/lib/capsule/collect/assistant/<name>.git`,
   `transfer_timeout_s`); `mode.self-edit-mech`, `mode.self-edit-mind`,
   `mode.tick-agent`. Decide whether `fix` stays. Restart `satan-runner`
   (a user act).
   - **Design point:** these values are hand-copied literals from the fleet
     (RV-029 F-8); fifteen entries is where they drift. Prefer one source: the
     fleet exports room data (repos, user, room name) that `runner.nix` reads
     at eval, or a shared data file both import. `default_branch` is
     per-repo and not in the fleet today.
3. **Producers**:
   - `satan-tools-patch-modes` (`satan/satan-tools-patch.el`, defcustom; set in
     `~/.config/emacs/apps/dl-satan.el` or the default) = the runner's modes.
   - Corpus prompts pass repo **names**: `prompts/self-edit-mech.txt`,
     `prompts/self-edit-mind.txt`, `prompts/tick/agent.txt` (`tools/patch_job_create.md`
     already says "name, not a path"). Model-facing text: user reviews.

## Done when

One job per lane (`self-edit-mech` on `satan`, `self-edit-mind` on
`satan-corpus`, `tick-agent` on another repo) reaches `needs_review` through
`patch_job_create`.
