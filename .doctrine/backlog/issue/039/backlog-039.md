# ISS-039: Two patch_jobs consumers: elisp patch runner and satan-patcher both enabled, with different jailed-pi provenance

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found during the harness spec-coverage census (2026-10-14,
`.doctrine/state/coverage-map-harness.md`).

- `~/.config/emacs/apps/dl-satan.el:22` sets `satan-patch-runner-enabled t`,
  so the elisp runner (`satan-patch-runner.el` → `satan-patch-adapter-pi.el`)
  claims jobs from `patch_jobs`.
- The `satan-patcher` user service (`~/flakes/modules/home/linux/satan-patcher.nix`)
  drains the same queue.
- Provenance differs: the elisp adapter resolves `jailed-pi` on the calling
  buffer's `exec-path` (ISS-038; not on the global PATH, so it resolves only
  from devshell buffers); satan-patcher builds it per job with
  `nix build <repo>#<flake_attr>`.
- satan-patcher is believed not to be working (all 17 jobs failed, newest
  2026-05-20, per `~/flakes/SATAN.md` known gaps). Not verified whether the
  two consumers race.

Likely direction: retire one runner, probably the elisp one. Supersedes or
absorbs ISS-038. Spec coverage for the patch runner is an open question for
then; the SATAN harness spec deliberately leaves it out.

## Closed by SL-023 audit (RV-029 F-19, 2026-10-19)

One consumer: the elisp runner is deleted (01dab54), satan-patcher removed (605447d8), `patch_jobs` dropped by migration 0009; `satan-runner` is the only consumer, verified deployed (SL-023 PHASE-14 B6; audit RV-029).
