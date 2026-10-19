# Patch lanes end to end: self-edit and tick jobs through the runner, scoped per mode

## Context

SL-023 cut patch jobs over to `satan-runner` (malebolge), running in oubliette
room `assistant`. Only the closure lane works: mode `fix`, repo `goad-walk`.
SATAN's own lanes — `self-edit-mech`, `self-edit-mind`, `tick-agent` — are
refused (ISS-046). Three layers sit between a lane and a running job:

```
 layer                       where                                    state (2026-10-19)
 1 room holds the clones     /srv/fleet flake.nix rooms.assistant     13 targets, clones in /work (user-verified);
                                                                       satan, satan-corpus missing
 2 runner knows repo + mode  ~/flakes features/satan/runner.nix       only repo.goad-walk, mode.fix
 3 producers send what the   Emacs satan-tools-patch-modes ("fix");   prompts send old modes, repo as a path
   runner accepts            corpus prompts
```

Separately, mode and repo are independent policy layers in the runner
(`src/runner/policy.ts`); nothing binds a lane to its repo or paths. The
binding lives only in corpus prompts, and `allowed_paths` is whatever the model
submits, so a lane is a label, not a scope boundary (ISS-046 § Mode scope
binding).

## Scope & Objectives

1. **Room targets.** Add `satan` and `satan-corpus` as targets of room
   `assistant` in `/srv/fleet` (target file + flake input each). `satan`
   exports `packages.dev-tools`; `satan-corpus`'s flake does not yet and needs
   a minimal tool set (git-only is enough).
2. **Runner config.** In `~/flakes/features/satan/runner.nix`, a `repo.<name>`
   entry per room target (hand-copied; one-source is IMP-044) and modes
   `self-edit-mech`, `self-edit-mind`, `tick-agent`. No per-lane budgets: each
   mode falls through to `[maxima]` (user ruling 2026-10-19).
3. **Mode scope binding.** `[mode.<m>]` gains optional `repos` and
   `allowed_paths`; submit refuses (`invalid_request`) a repo outside the
   mode's `repos` or a path not contained in the mode's `allowed_paths`.
   Containment is pure, beside `classify.ts`'s path matching. Amends SL-023's
   job contract (design §5.2, DEC-059).
4. **Producers.** `satan-tools-patch-modes` equals the runner's modes (mode
   names match SATAN's lane names end to end, user ruling 2026-10-19); corpus
   prompts `prompts/self-edit-mech.txt`, `prompts/self-edit-mind.txt`,
   `prompts/tick/agent.txt` pass repo **names**.

## Non-Goals

- One source for room data shared by fleet and runner — IMP-044.
- Per-lane budgets, models or prompt fragments.
- ISS-047 (rejoin wedges the seat when a repo leaves config) — though this
  slice adds repos, it removes none.
- Packaging malebolge as a flake input — CHR-017 (SL-023).
- Host-side checks; the `clean-clone` operation.

## Dependencies

- SL-023 is in reconcile; this slice amends its job contract. Record the
  amendment against SL-023's design/DEC-059, not by editing a locked design
  in place.
- Room rebuild/restart and `satan-runner` restart are user acts.

## Affected surface (coarse)

- `~/dev/malebolge`: `src/runner/config.ts` (mode keys), `src/runner/protocol.ts`
  or `control.ts` (submit admission), `src/runner/classify.ts` (containment
  helper), tests under `test/runner/`.
- `~/flakes/features/satan/runner.nix`.
- `/srv/fleet`: `flake.nix` (inputs, `targetNames`), `targets/satan.nix`,
  `targets/satan-corpus.nix`.
- `~/satan-corpus`: `flake.nix` (`packages.dev-tools`), the three prompts.
- `satan/satan-tools-patch.el` (default of `satan-tools-patch-modes`) or
  `~/.config/emacs/apps/dl-satan.el`.

## Risks, assumptions, open questions

- **Assumption:** each target's `default_branch` is `main`; verify per repo.
- **Risk:** `satan-tools-patch-modes` is read at load (the tool schema is
  built then); a live Emacs needs a reload after the change
  (mem: removing a SATAN tool breaks the live Emacs until modes are reloaded).
- **Risk:** corpus `just commit` sweeps all dirty state; commit prompt edits
  by path.
- **Risk:** a room rebuild may recreate volumes; confirm existing clones and
  quarantines survive adding targets.
- **Open:** does `fix` stay as a mode, or go?
- **Open:** containment semantics for an exact-file mode entry vs a prefix
  submit (proposal: exact contains only itself; prefix contains anything under
  it).
- **Open:** where the lane → repo binding lives on the Emacs side — the
  model still chooses `repo`; the runner is the authoritative check.

## Verification / closure intent

- One job per lane reaches `needs_review` via `patch_job_create`:
  `self-edit-mech` on `satan`, `self-edit-mind` on `satan-corpus`,
  `tick-agent` on another room repo.
- A submit outside its mode's repos, or with a path outside its mode's
  `allowed_paths`, is refused `invalid_request` (unit tests + one live refusal).
- malebolge `just check` green; satan `just check` green.
- ISS-046 closed.

## Summary

## Follow-Ups
