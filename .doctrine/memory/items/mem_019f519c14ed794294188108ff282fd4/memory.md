# SATAN package self-location coupling (user-emacs-directory)

SATAN production code assumes its own code and data live under
`user-emacs-directory` (`~/.emacs.d`). It resolves package files by
`(expand-file-name "satan/…" user-emacs-directory)`. This works only while
SATAN is a subdirectory of the config; **any standalone extraction breaks it**,
and it breaks the *shipped* package (once `~/.emacs.d/satan/` is deleted, every
such path dangles).

Distinct from the `dl-notes-root` coupling (notes data, SL-012 D4) — this is the
package's *self-location*, not user data.

## The 6 sites (grep `rg 'user-emacs-directory' satan/*.el`)

- `dl-satan-memory-migrate.el:26` — `satan/memory/migrations/` (breaks DB migrate)
- `dl-satan-pattern.el:44` — `satan/patterns.eld`
- `dl-satan-context.el:535` — `satan` dir
- `dl-satan-tools-docs.el:35,129` — doc-corpus roots
- `dl-satan-broker.el:56` — repo root
- `dl-satan-tools-vcs.el:24` — hardcoded `~/.emacs.d/` (not user-emacs-directory,
  same disease)

## Symptom when extracted

In batch from the standalone repo, `user-emacs-directory` still resolves to
`~/.emacs.d` (≠ the repo), so paths point at a non-existent tree. E.g. test DBs
never migrate → `function memory_show_trace does not exist` (64 ERT failures).

## Fix (SL-012 design revision, Axis 2)

Give the package a self-location root — a `satan--root` defconst resolved from
`load-file-name` (canonical ELPA pattern) — and anchor all package path
resolution to it, not `user-emacs-directory`. The test runner already does this
(`dev/satan-test.el`, RV-010 F-1); production defcustoms must follow.

Relevant to future POL-001 daemon extractions (IMP-006..009): the same
self-location assumption will bite each extracted module. See
[[mem.fact.satan.test-db-isolation]], [[mem.fact.satan.psql-plumbing]].
