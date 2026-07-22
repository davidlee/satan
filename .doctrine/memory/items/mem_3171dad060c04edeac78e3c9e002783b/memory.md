# SATAN orientation signpost

# SATAN agent orientation

SATAN is the Emacs-hosted AI agent broker. **Extracted to a standalone Elisp
package (SL-012, 2026-07-12):** code now lives at `~/dev/satan` (repo
`github.com/davidlee/satan`), not under `.emacs.d`. ~18.7k lines of elisp across
64 modules in `satan/`, plus 61 ert test files. The config loads it via
`(use-package satan …)` in `init.el`; the devshell/test harness resolves it with
an external `-L ~/dev/satan/satan`.

**Namespace:** every symbol is `satan-*`. The old `dl-satan-*` library prefix and
`my/satan-*` interactive prefix were both dropped in the extraction (two
collisions resolved to verb-first command names: `satan-renormalize-memory`,
`satan-show-migrate-status`). Entry point is `satan/satan.el` (feature `satan`).

## Start here

1. **Architecture overview**: `docs/INDEX.md` (in the satan repo — docs flattened,
   no longer `docs/satan/`) — one-line hooks into every doc chunk. Read
   `governance.md` and `architecture.md` first.
2. **Key docs**: `docs/memory/design.md` (substrate grammar + store),
   `docs/perceptual-design.md` (percept/resonance/sensors/motive),
   `docs/patch/brief.md` (patch agent), `docs/attributes/` (attribute layer).
3. **Policy**: [[POL-001]] — SATAN module extraction policy. Determines what
   stays in the broker and what gets extracted to daemons.

## Self-location + config-root decoupling (SL-012 D4/D10)

- **`satan--root`** (`satan/satan-custom.el`, `defconst` resolved from
  `load-file-name`) is the package's self-location root — the canonical ELPA
  idiom. All package code/data (`memory/migrations/`, `patterns.eld`, docs)
  resolve off it, **never** `user-emacs-directory`.
- **`satan-notes-root`** / **`satan-journal-today`** defcustoms (also in
  `satan-custom.el`, the zero-dependency leaf) replace the old config-owned
  `dl-notes-paths` / `dl-denote-journal` couplings. `satan-custom.el` owns
  `(defgroup satan …)`.

## Architecture layers (file map)

| Layer | Files | Role |
|-------|-------|------|
| Core | `satan.el`, `-broker.el`, `-mode.el`, `-protocol.el`, `-output.el`, `-jsonl.el`, `-audit.el` | Entry point, broker lifecycle, mode registry, wire protocol, output handlers, JSONL, audit log |
| Custom | `satan-custom.el` | `satan--root` self-location + `satan-notes-root`/`satan-journal-today` defcustoms (leaf; zero satan-deps) |
| Memory | `satan-memory.el`, `-store.el`, `-grammar.el`, `-canon.el`, `-evidence.el`, `-migrate.el` | Trace storage (psql), grammar, canonicalizer, evidence assembly, migrations |
| Tools | `satan-tools.el`, `-tools-{org,hippocampus,inbox,memory,bough,patch,notes,docs,notify,sway,agenda,activity,vcs,motive,atsatan}.el` | Tool registry + 15 tool modules |
| Perceptual | `satan-percept.el`, `-resonance.el`, `-motive.el`, `-sensor-{alerts,curiosity,wpm}.el` | Percept capsule, auto-resonance, motive file, sensor probes |
| Patch | `satan-patch.el`, `-store.el`, `-worktree.el`, `-runner.el`, `-adapter.el`, `-adapter-pi.el`, `-prompt.el`, `-classify.el`, `-inbox.el`, `-listener.el` | Patch job store (psql), worktree management, runner, adapters |
| Attributes | `satan-attribute.el`, `-listener.el`, `-render.el` | Broker→daemon outcome enqueue, LISTEN consumer, capsule render |
| Observer | `satan-observer.el`, `-classify.el` | Outcome classification of prior interventions |
| Intervention | `satan-intervention.el`, `-mark.el` | Intervention create/classify/lookup API + manual mark |
| Scheduling | `satan-tick.el`, `-budget.el`, `-block.el`, `-tank.el` | Tick modes, token budget, org-block writer, observation tank |
| Context | `satan-context.el` | Bundle assembly (prompt + framing + percept + resonance + motive + sensors + attributes) |

## Key invariants

- **Trust boundary stays in Emacs** (POL-001). Daemons are transports; authority over user-visible surfaces stays in the broker.
- **psql is the only DB interface**. ~10 files talk to postgres via `satan-db-*`; all via `call-process` to `psql`. No elisp PG libraries.
- **Tools are registered at load time** via `satan-tool-register`. Mode→tool allowlists are on mode specs.
- **The broker's spawn sequence** (in `satan-broker--spawn`) runs percept build → resonance → motive read → sensor alerts → curiosity/WPM probes → bundle assembly → process spawn. Order matters; it's a flat ~185-line `let*`.
- **Code lives in `~/dev/satan/satan/`; model-facing content lives in `~/notes/satan/`** (prompts, scaffolding, framing, tool descriptions, hippocampus, motives). The notes corpus stays out of the package by design (D4/POL) — corpus-integration tests `skip-unless` it is present ([[mem.pattern.satan.corpus-integration-skip-unless]]).
- **Package paths use `~` — expand before `call-process`.** `satan-notes-root`
  defaults to the literal `"~/notes"`; a subprocess base-dir/arg must be
  `expand-file-name`'d first (`call-process` does not expand `~`). Two such
  regressions shipped and were fixed post-cutover.

## DRY gotchas (post-extraction)

- **psql `--query`** cloning across `memory-store`/`patch-store`/`attribute`/`memory-migrate` and the `--prep-value` / `slugify` clones ([[DE-003]]) travelled with the code, now under `satan-*` names. Canonical homes: `satan-jsonl-prepare` (prep), `satan-memory-canon--slugify` (slugify). Re-assess DE-003's `satan-db.el` extraction against the standalone package.

## Refactoring conventions

- Rust is the target language for SATAN-orbit daemons (POL-001).
- One binary per extraction; shared types in `satan-core` crate.
- Every extraction gets a disable switch (cf. `satan-patch-runner-enabled`).
- See [[POL-001]] for the earns-the-seat test: "does it use the editor as an editor?"
- See [[mem.fact.satan.package-self-location-coupling]] for the self-location trap this extraction resolved.
