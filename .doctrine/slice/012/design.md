# SL-012 Design: Extract SATAN to standalone Elisp package

## Decisions

### D1 — Repository boundary

Target: `/workspace/satan/` (mounted rw in the jail; `~/dev/satan` on host, also
ro-mounted into the jail for uniform path resolution).

**Everything moves:**

| Source (`.emacs.d/`) | Destination (`/workspace/satan/`) |
|---|---|
| `satan/*.el` (64 files) | `satan/*.el` (symbols renamed) |
| `satan/test/*.el` (61 files) | `satan/test/*.el` |
| `satan/harness/` (Python) | `satan/harness/` |
| `satan/bin/` (4 scripts) | `satan/bin/` |
| `satan/memory/` (SQL migrations) | `satan/memory/` |
| `satan/protocol/` (JSONL fixtures) | `satan/protocol/` |
| `satan/patterns.eld` | `satan/patterns.eld` |
| `docs/satan/**` | `docs/**` (flattened) |
| `bin/elisp-locate-paren-error` | `bin/` (**copy** — config keeps its own; D7) |
| `dev/dl-test.el` | `dev/satan-test.el` (**copy**, parameterised; D7) |

**What stays in `.emacs.d/`:**
- `.doctrine/**` (SL-002..SL-011, DE-001..DE-010 — `.emacs.d` ids; SL-011/SL-012
  and the governance entities were later copied here, 2026-07-22) — historical
  records
- `.doctrine/slice/012/**` — this slice's governance
- `.spec-driver/policies/POL-001-*` — policy remains

**No `.doctrine/` bootstrap in the satan repo** for this slice. Deferred follow-up.

**Destination scaffold already exists.** `/workspace/satan/` holds an empty
`justfile`, empty `src/` and `test/` dirs, and a copied `.emacs.d` flake
(description still "flake for doing emacs"). Cleanup is in scope: delete the
leftover `src/`/`test/` dirs, fix the flake description, replace the empty
justfile per D7.

### D2 — Layout: preserve `satan/` directory

The load-path entry is the satan repo root, so `.el` files live in `satan/`
subdirectory (unchanged structure). This avoids structural refactoring.

### D3 — Rename sweep

| From | To | Scope |
|---|---|---|
| `dl-satan-*` symbols | `satan-*` | All `.el` + `test/*.el` |
| `dl-satan` (provide/feature) | `satan` | Entry point `satan/satan.el` |
| `dl-satan-db-*` | `satan-db-*` | Internal — same module, new prefix |
| `my/satan-*` interactive | `satan-*` | Package-owned commands |
| `my/op-read-env` | **unchanged** | External soft dep (`dl-secret`) |
| `my/journal--*` | **unchanged** | External soft dep (journal) |
| `(require 'dl-satan)` in init.el | `(use-package satan …)` | Consumer |
| `dl-satan-*` in doctor.el | `satan-*` via `declare-function` | Consumer |
| `(require 'dl-notes-paths)` in 6 files | dropped | Replaced by `satan-notes-root` |

All `satan/bin/*` scripts: update emacsclient `--eval` function names (`my/satan-run` → `satan-run`, etc.).

Docs (`docs/satan/**`) — regenerate or update. Sample paths and symbol names
embedded in prose should reflect new naming. Do not rewrite entire docs; use
search-replace for mechanical name changes, hand-edit where context demands.

Harness Python (`satan/harness/`) — no *behavioural* rename. References SATAN
env vars (`SATAN_RUN_ID`, etc.) which are wire-level, not symbol names. But
its comments cite elisp artifacts by old name (`protocol.py` ↔
`dl-satan-protocol.el`, `dl-satan-audit-validate-actions`) — comment
references update with the sweep (RV-010 F-7). The rename gate
(`rg 'dl-satan-'` / `rg 'my/satan-'` → empty) runs **repo-wide**, harness and
protocol fixtures included, not just code/tests/bin/docs.

**Delta 2026-07-12 (PHASE-02 phase-plan /consult) — collision rule.** Blunt
`my/satan-X → satan-X` collides where a `dl-satan-X` lib function of the same
base name already claims `satan-X`. Repo-wide there are exactly **2** hard
collisions, both in `dl-satan-memory-migrate.el`, both the impl+interactive-
wrapper pattern (tested lib fn returns data; thin `my/` command messages/prints,
no external callers):

| Lib fn (keeps `satan-X`) | Colliding `my/` command → new name |
|---|---|
| `dl-satan-memory-renormalize` → `satan-memory-renormalize` | `my/satan-memory-renormalize` → `satan-renormalize-memory` |
| `dl-satan-memory-migrate-status` → `satan-memory-migrate-status` | `my/satan-memory-migrate-status` → `satan-show-migrate-status` |

**Rule:** when a `my/satan-X` interactive command collides with a `dl-satan-X`
lib function, the **lib keeps `satan-X`** (it is the tested public API) and the
**command takes an imperative verb-first name** (`satan-<verb>-<object>`). The
other 20 `my/satan-*` commands map cleanly to `satan-*` and are unaffected. EX-3
(`rg 'my/satan-'` empty) still holds — the 2 commands lose the `my/` prefix too,
just to a verb-first name. Feature/function name coexistence (e.g. file
`satan-tick.el` provides feature `satan-tick` while `satan-tick` is also the
command) is harmless in elisp (distinct symbol cells) and needs no rule.

### D4 — Coupling: config-root assumptions → defcustoms (Axis-1: notes)

> **Reframed 2026-07-12 (design revision).** The extraction severs config-root
> coupling along **two** axes: **Axis-1** — user *notes* data (`dl-notes-root`,
> this decision) — and **Axis-2** — the package's own *self-location* and
> config-shaped path defaults (**D10**). PHASE-01 proved Axis-2 breaks the
> *shipped* package (not just tests). Both decouple surfaces share one leaf
> module, `satan/satan-custom.el` (see D10). This decision covers Axis-1.

**Actual coupling surface (verified 2026-07-10, re-verified via RV-010 F-3):**
**13 production files** consume `dl-notes-*` symbols — 10 with a hard
`(require 'dl-notes-paths)` (`context, mode, motive, patch-prompt,
tools-atsatan, tools-hippocampus, tools-inbox, tools-notes, tools-org,
tools`) plus **3 transitive consumers with no require** (`run, broker,
sensor-wpm` — they rely on another module having loaded the feature). Symbols:
`dl-notes-root`, `dl-notes-journal-dir`, `dl-notes-weekly-dir`,
`dl-notes-inbox-file`. **2 test files** (`test/dl-satan-context-test.el`,
`test/dl-satan-integration-test.el`) also bind/reference `dl-notes-*` and
convert with the rest. The decouple gate is consumer-based
(`rg 'dl-notes-' → empty` repo-wide), not require-based.

**Delta 2026-07-12 (PHASE-03 execution, RV-012 F-1) — third config-root
coupling.** The Axis-1 coupling surface above enumerated only `dl-notes-paths`.
Execution found a *third* config-root coupling the inventory missed: `context.el`
and `tools-org.el` also hard-`require`d **`dl-denote-journal`** (config-owned,
provider of `my/journal--*`). Both requires were dropped — the *today* path
resolves through the designed `satan-journal-today` injection; the *weekly* path
degrades to a `declare-function` soft-dep. Dropping the require then exposed a
latent missing **`(require 'calendar)`** in `satan-memory-evidence.el` (only ever
loaded transitively via `dl-denote-journal → denote → calendar`; 29
`calendar-absolute-from-gregorian` void-function failures until added — same
package-self-containment class as the PHASE-01 linter fix). The decouple gate is
therefore `rg 'dl-notes-' → empty` **and** no residual `dl-denote-journal`
require, repo-wide.

Two new surfaces in the leaf module `satan/satan-custom.el` (D10 — also home to
`satan--root`):

```elisp
(defcustom satan-notes-root "~/notes"
  "Root directory of the notes corpus.
SATAN derives owned paths as ${satan-notes-root}/satan/...
and standard corpus paths (journal/, weekly/, inbox.org) below it."
  :type 'directory
  :group 'satan)

(defcustom satan-journal-today nil
  "Zero-arg function returning today's journal file path, or nil.
When non-nil, SATAN calls this to include today's journal in
context assembly.  The function must ensure the file exists
before returning its path."
  :type '(choice (const :tag "None" nil)
                 function)
  :group 'satan)

(defun satan-notes-path (&rest segments)
  "Join SEGMENTS below `satan-notes-root'."
  ...)
```

**Path derivation, not more defcustoms.** The non-root symbols are derived
from `satan-notes-root` at the use sites via `satan-notes-path`:

| Old symbol | Replacement |
|---|---|
| `dl-notes-root` | `satan-notes-root` |
| `dl-notes-journal-dir` | `(satan-notes-path "journal")` — where not absorbed by `satan-journal-today` |
| `dl-notes-weekly-dir` | `(satan-notes-path "weekly")` |
| `dl-notes-inbox-file` | `(satan-notes-path "inbox.org")` |

This couples satan to the standard corpus layout under the root — accepted:
satan already assumes `${root}/satan/...` layout for its owned paths, and one
knob beats five. If a consumer ever needs a divergent layout, promote the
specific path to a defcustom then.

Consumer wiring in `.emacs.d/init.el`:

```elisp
(use-package satan
  :custom
  (satan-notes-root "~/notes")
  (satan-journal-today
   (lambda ()
     (my/journal--ensure-today)
     (my/journal--today-file dl-notes-journal-dir "journal"))))
```

The 10 requiring files drop `(require 'dl-notes-paths)`; all 13 consumers
(and the 2 test files) replace their `dl-notes-*` references per the table;
journal-today references (`dl-satan-context.el`, `dl-satan-tools-org.el`) use
`(funcall satan-journal-today)` when non-nil.

Weekly journal (`dl-satan-tools-org.el` line 51: `my/journal--week-file`) is a
second journal surface. Deferred — keep the soft `declare-function` pattern for
now (its dir argument becomes `(satan-notes-path "weekly")`). If satan needs
richer weekly awareness later, add `satan-journal-week`.

### D5 — Load-path wiring

`core/dl-path.el` changes:

```elisp
;; Before
(defvar my/lisp-dirs
  '("lisp" "core" "editing" "completion" "apps" "org" "dev" "lang" "satan")
  ...)

;; After
(defvar my/lisp-dirs
  '("lisp" "core" "editing" "completion" "apps" "org" "dev" "lang")
  ...)

(defvar my/checkout-lisp-dirs
  '("checkout" "elpa/org-timeblock" "~/dev/satan/satan")
  ...)
```

This puts satan on the load-path alongside other external checkouts, before
`init.el` runs. The `use-package satan` form needs no `:load-path`.

### D6 — flake.nix updates

**`/workspace/satan/flake.nix`** (the satan repo):
- Harness source `./satan/harness` resolves after `satan/` is moved in — no change
- Strip config-specific jail definitions (pi, opencode, claude, dirge)
- Keep: `satanFakeHarness`, `satanGptelHarness`, jailed wrappers, `bubblewrap`
- Devshell: keep `postgresql_18`, `supabase-cli`, `emacsclient-commands`, `just`, `doctrine`

**`/workspace/flakes/modules/home/satan.nix`** (host systemd units):
- `ExecStart` paths: `%h/.emacs.d/satan/bin/` → `%h/dev/satan/satan/bin/`
- Function names in wrapper scripts updated per D3

**`/workspace/.emacs.d/flake.nix`** (the config repo — was wrongly assumed
untouched):
- Builds `satanGptelHarness` from `src = ./satan/harness` (line ~156) — breaks
  the moment `satan/` moves. Remove.
- Also defines `satanFakeHarness`, `satanJailOptions` (jail binds + `SATAN_*`
  env), and jailed wrappers. These are exactly what D6 keeps in the satan repo
  flake — they move OUT of the config flake; any config-flake consumers of
  those outputs repoint to the satan repo flake or are removed.
- The jail bind `--bind "$HOME/dev/satan" "/workspace/satan"` already exists
  there (marked `## Migration !!`) — see OQ-1/D8.

**Other flakes unchanged.** The emacs module (`pub/emacs.nix`) doesn't mention
satan. Daemon modules (`satan-attrd.nix`, `satan-patcher.nix`) reference their
own repos unchanged.

### D7 — Test infrastructure

**`.emacs.d/`** — `dev/dl-test.el` drops `satan/test` from `dl-test-suite-dirs`,
**and** the `Justfile` `check` recipe drops its hardcoded `-L satan
-L satan/test` load-path flags (RV-010 F-8 — the batch entrypoint bypasses
`dl-path.el`, so editing dl-path alone leaves `just check` pointing at a
deleted tree). `just check` no longer runs satan tests. The config-side doctor
test (`lisp/test/dl-sleipnir-doctor-test.el`) requires
`dl-satan-memory-evidence` and binds `dl-satan-*` vars — it is rewritten
against the renamed package interface (satan on load-path via D5), or its
satan-coupled cases move into the satan repo (RV-010 F-4; decide at
phase-plan).

**Test runner moves with the tests.** A naive `mapc load-file test/*.el` recipe
regresses on behaviour `dev/dl-test.el` already owns: (a) suites that `require`
a sibling for fixture macros get loaded twice → ERT "redefined (or loaded
twice)" batch errors — dl-test skips already-`featurep`d files; (b) the
production-socket refusal preflight (no `SATAN_DB_HOST` /
`SATAN_FAILOVER_TO_SYSTEM_DB` in batch → loud error before loading any test).
So: copy `dev/dl-test.el` into the satan repo as `dev/satan-test.el`, suite
dirs parameterised to `'("satan/test")`, symbols renamed per D3. The config's
`dl-test.el` keeps `lisp/test` only. Deliberate clone — the repo boundary is
the DRY boundary now.

**Runner anchor (RV-010 F-1):** `dl-test.el` expands suite dirs under
`user-emacs-directory`, which in batch resolves to `~/.emacs.d` — wrong repo.
`satan-test.el` must anchor to the repo root instead (resolve relative to
`load-file-name` / `default-directory`), or the justfile must pass
`--init-directory "{{justfile_directory()}}"`. Do both belt-and-braces is
unnecessary — anchor the runner to its own location; no Emacs init implied.

**Linter script:** `bin/elisp-locate-paren-error` lives in `.emacs.d/bin/` and
is not in the D1 move table. Copy it into the satan repo's `bin/` (self-
contained script; config keeps its own copy).

**`/workspace/satan/`** — `justfile` (replaces the empty scaffold one):

```justfile
check: lint test

lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in satan/*.el; do
        bin/elisp-locate-paren-error "$f"
    done

test:
    #!/usr/bin/env bash
    set -euo pipefail
    emacs --batch -L ./satan -L ./dev \
      -l satan-test --eval "(satan-test-run-batch)"
```

No `SATAN_DB_HOST` default baked into the recipe — the runner's preflight
fails loud without it, matching the existing refusal pattern
(`mem.fact.satan.test-db-isolation`; `dl-satan-db.el` additionally guards the
production socket in batch).

PSQL/supabase: the satan repo's devshell already provides `postgresql_18` and
`supabase-cli`. Tests that need a DB self-isolate via the existing
`SATAN_DB_HOST` pattern; suites skip DB tests when the DB is unreachable.

**Flake tracked-file trap (RV-010 F-2):** nix flake evaluation sees only
git-tracked files. The copied tree must be `git add`ed in the satan repo
before any flake eval/build gate runs — untracked `.el`/`harness` files are
invisible to the build and fail silently as "missing path".

**Runtime dependency note (RV-010 F-5, from SL-011):** SL-011 makes
`timeout(1)` (coreutils) a runtime dependency of the package. Package docs /
`Package-Requires` commentary must record it (elisp can't declare a binary
dep; a README/Commentary note + devshell coverage is the mechanism).

### D8 — flake mount paths (jail)

The host does `~/dev/satan` → jail at `/workspace/satan` (rw) and `~/dev/satan` (ro).
This lets both `/workspace/satan/satan` and `~/dev/satan/satan` resolve in the
jail. `dl-path.el` uses `~/dev/satan/satan` which works everywhere.

Implementation: add a ro bind mount for `~/dev/satan` in the jail's flake config
OR a symlink on the host (`~/dev/satan → /workspace/satan`). Exact mechanism
determined during phase planning. Note the rw bind
`$HOME/dev/satan → /workspace/satan` already exists in `.emacs.d/flake.nix`
(marked `## Migration !!`); only the `~/dev/satan`-shaped path is missing
inside the jail.

### D9 — Ordering: SL-011 lands first

`slice-012.toml` carries `after = SL-011`. SL-011 (SATAN tick performance:
observe and bound) is still in design and adds new surface into the same tree
this slice moves and renames: `dl-satan-trace.el`, `dl-satan-trace-call`, five
timeout defcustoms, tick/subprocess JSONL trace rows.

**Contract:** SL-011 is implemented and closed before SL-012 execution begins.
The rename sweep is glob-driven (`satan/*.el`, `rg 'dl-satan-'`), not
count-driven, so it absorbs SL-011's new module mechanically — no design
change here, but file/test counts cited in this document are design-time
snapshots, not gates. If SL-011 is descoped or stalls, `/consult` before
reordering: running SL-012 first invalidates SL-011's design (paths, symbol
names) and forces its rewrite.

### D10 — Package self-location + config-root defaults (Axis-2)

**Added 2026-07-12 (design revision).** PHASE-01 crossed the repo boundary and
exposed a second config-root coupling axis the design missed. The package
resolves its *own* code and data via `(expand-file-name "satan/…"
user-emacs-directory)`. That holds only while SATAN is a subdirectory of the
config; standalone it points at a non-existent tree — and it breaks the
**shipped** package (PHASE-04 deletes `~/.emacs.d/satan/`, dangling every such
path). Proven symptom: batch tests never migrate their DBs
(`user-emacs-directory` = `~/.emacs.d` ≠ the repo) →
`function memory_show_trace does not exist` → 64 ERT failures. See
`mem.fact.satan.package-self-location-coupling`. RV-010 **F-1** half-saw this
but scoped the fix to the test runner only; it is endemic in production.

**Taxonomy.** The 6 sites (`rg 'user-emacs-directory' satan/*.el` + one `~/.emacs.d/`
hardcode) split by *meaning*, and only the first group is genuine self-location:

- **Axis-2a — self-location** (data/source shipped *inside* the package).
- **Axis-2b — config-shaped defaults** that merely *point at* the config root;
  each needs a distinct call, not a blind re-anchor.

Not in Axis-2: `dl-satan-self-edit-mind-roots` (`dl-satan-context.el:542`) rides
`dl-notes-root` — that is model-facing notes content = **Axis-1 (D4)**. The
mind/mech split is deliberate: *mech* = the package's own machinery
(self-location, D10), *mind* = the notes corpus (D4). Doc-comment `.emacs.d`
references (`attribute-render.el:12`, `memory.el:7`, `context.el:611`, …) are
prose, not defaults — they sweep with the PHASE-02 docs pass, not here.

**Mechanism — self-location root.** A new leaf module `satan/satan-custom.el`
(zero satan-deps) is the home for **both** decouple surfaces — D4's notes
defcustoms *and* D10's `satan--root`:

```elisp
(defconst satan--root
  (file-name-directory
   (or load-file-name buffer-file-name (locate-library "satan-custom")))
  "Directory holding SATAN's elisp and shipped data (memory/migrations, patterns.eld).
Package plumbing — internal, resolved at load; not user-configurable.")
```

`load-file-name` for any satan module resolves to `…/satan/satan-custom.el`, so
`satan--root` is the **elisp directory** (`…/satan/`) — the canonical ELPA
self-location idiom. Data files ship as subdirs of it (`memory/`, `patterns.eld`)
and travel with an ELPA install; `docs/` is a repo-root sibling, reached
`../docs`. The `(or load-file-name buffer-file-name …)` chain covers batch/`require`
load, interactive `eval-buffer`, and a `locate-library` fallback.

**Naming.** `satan--root` (double-dash, `defconst`) — internal package plumbing,
read across modules but never set. `defconst` signals not-configurable, `--`
signals not-user-facing. Convention documented in `satan-custom.el` commentary
so future modules anchor to it rather than reintroducing `user-emacs-directory`.

**Load ordering.** defcustom defaults evaluate at module load, so `satan--root`
must exist first. Every anchoring module gains `(require 'satan-custom)`.

**Axis-2a — re-anchor to `satan--root` (mechanical):**

| Site | From | To |
|---|---|---|
| `dl-satan-memory-migrate.el:26` (`…-migrate-directory`) | `(expand-file-name "satan/memory/migrations/" user-emacs-directory)` | `(expand-file-name "memory/migrations/" satan--root)` |
| `dl-satan-pattern.el:44` (`…-pattern-file`) | `(expand-file-name "satan/patterns.eld" user-emacs-directory)` | `(expand-file-name "patterns.eld" satan--root)` |
| `dl-satan-context.el:535` (`…-self-edit-mech-roots`) | `(list (expand-file-name "satan" user-emacs-directory))` | `(list satan--root)` |

**Axis-2b — config-shaped defaults, per-site (approved "fix all"):**

| Site | From | To | Rationale |
|---|---|---|---|
| `dl-satan-tools-docs.el:35` (`…-docs-roots`) | `'("docs/satan" "docs/emacs")` rel. `user-emacs-directory` | `'("docs")` rel. `(expand-file-name "../docs" satan--root)` | pkg docs only; **`docs/emacs` is config-owned — dropped**. `--resolve-roots` (l.129) re-anchors its `expand-file-name` base accordingly |
| `dl-satan-broker.el:56` (`…-direnv-dir`) | `(expand-file-name user-emacs-directory)` | `(file-name-directory (directory-file-name satan--root))` (pkg repo root) | the jailed harness sources the *package* repo's `.envrc`, not the config's |
| `dl-satan-tools-vcs.el:24` (`…-search-roots`) | `'("~/dev/" "~/.emacs.d/" "~/flakes/")` | **unchanged**; docstring notes user-tunable | user's repo-*search* list, not self-location; `~/.emacs.d/` still resolves post-extraction |

**Adversarial review (2026-07-12).**
- *direnv-dir default* — verified the satan repo root carries an `.envrc`
  (`use flake . --impure` + `JAIL_WORKSPACE_DEPS`), so the repo-root default
  resolves and `envrc--export` fires. **Caveat:** the config `.envrc` also
  exports `DOCKER_HOST` (podman socket) which the satan repo `.envrc` lacks; if
  the jailed harness needs it, add it to the satan repo `.envrc` at PHASE-04
  wiring / reconcile. Design default stands.
- *`../docs` anchor is not ELPA-relocatable* — from a real ELPA package dir,
  `../docs` resolves to the ELPA parent, not the corpus. Accepted: D5 installs
  via load-path checkout (`~/dev/satan/satan`), not ELPA, and doc indexing is a
  dev/runtime feature, not shipped-package-critical. `satan--root`-anchored
  *data* (migrations, `patterns.eld`) *is* ELPA-safe; docs is the lone exception,
  recorded so a future ELPA push relocates the corpus under `satan--root`.
- *count-pinning* — the "64 failures" is a PHASE-01 measurement, not an exit
  gate; the gate is behavioural (migrate paths resolve → test DBs migrate).

**Manifest note (not design-tier).** `test/dl-secret-test.el` requires
`dl-secret` — a config-owned module SATAN only soft-deps (`my/op-read-env`). It
should not have moved into the package; drop it during the plan/PHASE re-scope.

**Ownership & ordering (plan-facing).** Both axes are semantic and belong
**after** the PHASE-02 rename (so the sweep doesn't rewrite fresh call sites).
Recommendation: fold Axis-2 into the current PHASE-03, renamed "Decouple
config-root assumptions" covering both axes. The plan revision also re-cuts the
PHASE-01/02 **green gate**: "full ERT green" is unsatisfiable for a
copy-verbatim / defer-decouple phase (green needs both axes severed) → *lint
green + suite loads & runs across the boundary + suites not blocked by the two
axes pass; coupling-blocked suites known-red until the decouple phase*. Full
green only from the decouple phase onward.

## Current vs target behaviour

**Before:**
- `init.el` → `(require 'dl-satan)` loads from load-path (satan/ dir via `my/lisp-dirs`)
- SATAN is a subdirectory of the config, not a package
- Symbols: `dl-satan-*`, interactive: `my/satan-*`
- Hard requires `dl-notes-paths`

**After:**
- `dl-path.el` adds `~/dev/satan/satan` to `my/checkout-lisp-dirs`
- `init.el` → `(use-package satan :custom …)`
- SATAN is a standalone package in its own repo
- Symbols: `satan-*`, interactive: `satan-*`
- Two defcustoms (`satan-notes-root`, `satan-journal-today`) replace `dl-notes-paths` (Axis-1)
- `satan--root` self-location defconst; package data/source/docs resolve off it, not `user-emacs-directory` (Axis-2, D10)
- `satan/satan-custom.el` leaf module homes both decouple surfaces

## Verification

- `just check` green in `.emacs.d` (lisp tests, doctor checks)
- `just check` green in `/workspace/satan` (full ERT suite — count unpinned per
  D9, lint, byte-compile)
- `dl-sleipnir-doctor` SATAN checks pass (mode registry, budget, memory DB, sensors, patch)
- Self-location decoupled (D10):
  - `rg 'user-emacs-directory' satan/*.el` empty in satan repo (doc-comments swept too)
  - `satan--root` resolves to the elisp dir; `memory-migrate`/`pattern`/`self-edit-mech` paths resolve under it
  - `tools-docs` default excludes `docs/emacs`; the migrate-driven ERT failures clear (the "64" is a PHASE-01 snapshot, not a gate)
- Symbol rename complete:
  - `rg 'dl-satan-' satan/` empty in satan repo
  - `rg 'my/satan-' satan/` empty in satan repo
  - `rg 'dl-satan-'` zero hits in `.emacs.d` outside `.doctrine/`, `.spec-driver/`, `CHANGELOG.md`
- `M-x satan-run RET morning` works from Emacs
- `satan/bin/*` scripts work (emacsclient calls resolve new function names)
- Byte-compilation clean — `emacs --batch -L ./satan --eval "(batch-byte-compile)" satan/*.el`
- `~/.config/git/hooks/post-commit` symlink resolves (re-linked to
  `~/dev/satan/satan/bin/satan-git-post-commit`) and a test commit appends a
  segment row
- `.emacs.d` flake evaluates (`nix flake check` or equivalent) after satan
  outputs removed

## Risks

- **Test regressions across repo boundary.** satan tests currently run in-process
  with the full config. After extraction they run in batch with only satan on
  the load-path. Some tests may implicitly depend on config-level setup
  (defcustoms, helper functions). Mitigation: run satan test suite in isolation
  early, fix leaks. Phase exit criterion: `just check` green in the satan repo.
- **flakes breakage.** The satan repo's flake was copied, not exercised. Harness
  build may fail until paths settle. Mitigation: flake build is separate phase
  with its own VT gate.
- **Bin scripts call emacsclient.** If Emacs server isn't running or the package
  isn't loaded, `satan-run` fails. Existing behaviour unchanged.
- **Rename completeness.** One missed `dl-satan-` reference in a require form
  breaks loading. Verification gate: `rg 'dl-satan-' satan/` returns empty in
  the satan repo.
- **`satan/bin/satan-git-post-commit`** may reference `.emacs.d/satan/` paths
  internally. Audit during implementation.
- **Global git hook symlink breaks on move.**
  `~/.config/git/hooks/post-commit → ~/.emacs.d/satan/bin/satan-git-post-commit`
  is manual machine setup (global `core.hooksPath`); the move invalidates the
  target and silently kills the git-activity sensor feed. Mitigation: re-link
  step in the move phase + verification line above.
- **Memory corpus / boot snapshot staleness.** 17 memory files reference
  `dl-satan-*` symbols or `.emacs.d/satan` paths; the boot sector's SATAN
  orientation says code lives in `~/.emacs.d/satan/`. Docs-update scope covers
  `docs/satan/**` only. Mitigation: `/reviewing-memory` pass + boot-sector
  re-seat as a closure step (see Follow-ups).

## Follow-ups

- `/reviewing-memory` pass over the 17 satan-referencing memories + boot-sector
  re-seat (`doctrine reseat` / `infra boot`) once the move lands — paths and
  symbol names in the corpus go stale at merge.

## Open questions

1. **Flake jail mount mechanism.** How exactly to ensure `~/dev/satan` resolves
   in the jail. The rw bind `$HOME/dev/satan → /workspace/satan` already exists
   in `.emacs.d/flake.nix`; missing piece is a `~/dev/satan`-shaped path inside
   the jail. Options: (a) add second ro bind in flake, (b) host-side symlink.
   Decision deferred to phase planning — verify during implementation.
2. **`satan-journal-today` vs per-mode journal access.** Current code uses
   `my/journal--today-file` in context assembly and `my/journal--week-file` in
   `tools-org`. The defcustom covers today; weekly is YAGNI for now. Add when
   needed.
3. **`patterns.eld` data file.** Does it contain any `dl-` or `my/` keys that
   need renaming? Verify during implementation; likely no (it's SATAN-internal
   data, not symbol references).
