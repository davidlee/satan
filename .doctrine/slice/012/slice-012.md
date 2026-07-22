# Extract SATAN to standalone Elisp package

> **Imported 2026-07-22** from the `.emacs.d` doctrine corpus, frozen for SATAN.
> Ids cited below resolve in that corpus unless they also exist here; `DE-`/`DR-`
> have no doctrine equivalent, and `IMPR-NNN` / `ISSUE-NNN` are pre-doctrine
> prefixes for `IMP-NNN` / `ISS-NNN`.

## Context

SATAN is ~18,761 lines of elisp across 64 files in `satan/`, plus 989 ert tests
across 61 test files. It is loaded inline from `init.el` via `(require 'dl-satan)`
and treated as part of the config directory by Nix's `emacsWithPackagesFromUsePackage`.

POL-001's "earns the seat" policy has already identified individual modules that
should eventually leave elisp for Rust daemons (IMP-006..009), but those are
*selective* extractions of modules that don't use the editor as an editor. The
immediate need is coarser: move the entire SATAN codebase into a proper
standalone Elisp package as a prerequisite to future selective extractions.

## Scope & Objectives

### In scope

1. **Move all SATAN artifacts** out of `.emacs.d` into `/workspace/satan/`:
   - `satan/` → `/workspace/satan/satan/` (elisp, harness, bin, memory, protocol, data)
   - `docs/satan/` → `/workspace/satan/docs/` (architecture docs)

2. **Rename the `dl-` and `my/` prefixes** throughout. SATAN as a standalone
   package owns its namespace:
   - `dl-satan-*` → `satan-*`
   - `dl-satan-db-*` → `satan-db-*` (already shared; renames with the rest)
   - Interactive `my/satan-*` commands → `satan-*` (or keep `my/` per naming
     convention — design-time decision)
   - `my/op-read-env` and `my/scrub-op-refs-env` usage (from `dl-secret`) →
     becomes a soft dependency with `declare-function` + `fboundp` guard (already
     soft, just rename)

3. **Resolve `dl-notes-paths` hard coupling.** SATAN's 10 files require
   `dl-notes-paths` for `dl-notes-root`, `dl-notes-journal-dir`,
   `dl-notes-weekly-dir`, and `dl-notes-inbox-file`. Replace with a
   `satan-notes-root` defcustom (paths derived below it), set by the
   consuming config.

   *(Axis-1 of the config-root decoupling — user notes data.)*

3b. **Resolve config-root self-location coupling (Axis-2, design D10).** SATAN
   resolves its own code/data via `(expand-file-name "satan/…"
   user-emacs-directory)` — which breaks the moment it is standalone (and breaks
   the shipped package once `~/.emacs.d/satan/` is deleted). Introduce a
   `satan--root` self-location defconst (resolved from `load-file-name`) and
   re-anchor package-owned paths to it; re-default the config-shaped path knobs
   (`tools-docs-roots` drops `docs/emacs`, `direnv-dir` → repo root). Proven by
   PHASE-01 (64 ERT failures from unmigrated test DBs). See
   `mem.fact.satan.package-self-location-coupling`.

4. **Add proper ELPA package boilerplate:**
   - `satan.el` entry point (renamed from `dl-satan.el`)
   - Package headers (`;;; satan.el --- ...`), `Package-Version`, `Package-Requires`
   - `satan-pkg.el` (if needed for ELPA compatibility)
   - `(provide 'satan)` at the bottom

5. **Move all tests** (`satan/test/`) with the code. The test infrastructure
   (`dev/dl-test.el`) stays; it already discovers suites by directory.

6. **Wire into the config** without Nix magic:
   - Add the package repo or symlink to `load-path`
   - Add `(use-package satan …)` in `init.el` (or equivalent file)
   - Remove the old `(require 'dl-satan)` and all satan-related config dirs
   - Update `dl-sleipnir-doctor.el` references (soft `declare-function`, rename)

7. **Update `just check`** so the full test suite (including moved satan tests)
   still passes.

8. **Update docs** — `docs/satan/INDEX.md`, `governance.md`, `architecture.md`,
   and any references to the `satan/` directory structure in memory/CHANGELOG.

### Out of scope

- **Selective module extraction per POL-001** (IMP-006..009). This is the
  packaging prerequisite, not the daemon extraction itself. Those backlog items
  should become *easier* after the package boundary exists.
- **Rust/Go rewrites.** The code stays Elisp.
- **Architectural refactoring.** Renaming for namespace ownership is a mechanical
  transformation, not a redesign. No restructuring of modules, split/merge, or
  API changes except where the `dl-notes-paths` coupling demands a new defcustom.
- **Model-facing content** (`~/notes/satan/`). Already separated; not moving.
- **Updating `emacs.nix`** for the new package. User indicated Nix is unnecessary
  here; use `load-path` + `use-package`.

## Non-Goals

- Publishing to MELPA or any public package archive
- Changing SATAN's behaviour, invariants, or test expectations
- **Full** defcustom consolidation (130 scattered → `satan-custom.el`) — deferred.
  D10 creates `satan-custom.el` as a leaf home for the *decouple* surfaces only
  (`satan--root`, `satan-notes-root`, `satan-notes-path`, `satan-journal-today`);
  the wholesale consolidation of the other ~126 defcustoms stays out of scope.

## Summary

Extract SATAN into `/workspace/satan/` (`~/dev/satan` on host) as a standalone
Elisp package with its own namespace (`satan-*`), its own tests and test
runner, and a `satan-notes-root` defcustom replacing the `dl-notes-paths` hard
coupling. Wire it as a `use-package` with a `load-path` entry. The config's
existing `(require 'dl-satan)`, its satan flake outputs (gptel/fake harness,
jail options), and the config-dir reference are removed. `just check` remains
green in both repos. Runs after SL-011 closes (design D9).

## Follow-Ups

- IMP-006..009 (selective daemon extractions) — easier now that SATAN is a package
- Deferred: **full** defcustom consolidation (`satan-custom.el` now exists for the decouple surfaces only)
- Deferred: rename `my/` interactive commands inside SATAN (may be design-time decision)
- `/reviewing-memory` pass + boot-sector re-seat after the move (17 memories
  reference `dl-satan-*` / `.emacs.d/satan` paths)
- `.doctrine/` bootstrap in the satan repo (deferred from design D1)
