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
   exports `packages.dev-tools`; `satan-corpus` takes `toolsPackage = null`
   (the room base already has git, bash, coreutils).
2. **Runner config.** In `~/flakes/features/satan/runner.nix`, a `repo.<name>`
   entry per room target (hand-copied; one-source is IMP-044) and modes
   `self-edit-mech`, `self-edit-mind`, `tick-agent`, `interactive`. No per-lane budgets: each
   mode falls through to `[maxima]` (user ruling 2026-10-19).
3. **Mode scope binding.** `[mode.<m>]` requires `repos` and
   `allowed_paths`, each a list or `"*"` (unbounded; DEC-069); submit refuses (`invalid_request`) a repo outside the
   mode's `repos` or a path not contained in the mode's `allowed_paths`.
   Containment is the existing `disallowedPaths` matcher. Amends SL-023's
   job contract (design §5.2, DEC-059).
4. **Producers.** Emacs stamps `mode` from the run's acting mode (DEC-068);
   `mode` leaves the tool schema and `satan-tools-patch-modes` is deleted;
   MCP sessions submit as `interactive`; no run ctx → refused. Corpus prompts
   `prompts/self-edit-mech.txt`, `prompts/self-edit-mind.txt`,
   `prompts/tick/agent.txt` pass repo **names** and drop `mode`/`checks`.
   Mode names match SATAN's lane names end to end; `fix` is dropped.

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
- `~/satan-corpus`: the three prompts, `tools/patch_job_create.md`.
- `satan/satan-tools-patch.el` and its test.

## Risks, assumptions, open questions

- ~~Assumption: every default branch is `main`~~ — false for `doctrine`
  (`edge`); research.
- **Risk (ISS-028):** the harness jail binds `~/dev/satan` read-write, so
  self-edit-mech can bypass the patch lane; mode scope is not a complete
  boundary for that lane until ISS-028 closes.
- **Risk:** the tool schema is built when `satan-tools-patch.el` loads; a
  live Emacs needs a reload after the change
  (mem: removing a SATAN tool breaks the live Emacs until modes are reloaded).
- **Risk:** corpus `just commit` sweeps all dirty state; commit prompt edits
  by path.
- **Risk:** a room rebuild may recreate volumes; confirm existing clones and
  quarantines survive adding targets.
- Settled in design: `fix` dropped (DEC-068); containment by the existing
  matcher (DEC-069); the runner is the sole scope check, Emacs supplies
  identity only (DEC-068).
- **Accepted risk (RSK-019):** `interactive` is unbounded; any MCP client can
  submit on any configured repo.

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
