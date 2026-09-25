# IMP-034: Drop every broker-cwd read from evidence (fs_state, git_state, cwd.project) and retire its consumers

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Split out of [[IMP-013]] (2026-09-25) as its smallest, repo-local move.

## Why drop rather than promote

`:fs_state` (`satan-memory-evidence--fs-state`) lists recently modified files
under the broker's cwd. That cwd is Emacs's incidental `default-directory`, not
the user's active project (the root cause [[ISS-004]] names), so the key is
unreplayable **and** usually wrong even when it is read live. Nothing upstream
can make it replayable: no producer observes "recent files in the user's
project", and the compositor's IPC does not expose per-window cwd (every
terminal window shares one pid). An active-project signal, once one exists,
is the replacement (see IMP-013 on window titles).

## Fan-out to retire

| consumer | site | disposition |
|---|---|---|
| assembler | `satan/satan-memory-evidence.el` (`--fs-state`, `--recent-files`, `:fs_state` key, cue-only docstring) | delete |
| canon `cwd.file_kind` | `satan/satan-memory-canon.el:449` | delete the rule; `file_kind` stays a grammar-v1 namespace until [[IMP-016]]'s grammar-v2 |
| canon `cwd.project` | `satan/satan-memory-canon.el:387` | drop the `fs_state.cwd` fallback; the `git_state.remote` source stays until IMP-013's git move |
| observer `:fs_recent_delta` | `satan/satan-observer-classify.el:207-230`, `:577` | delete the predicate; ambient kinds keep `:editor_edit_in_window` and `:git_commit_observed` |
| resonance defaults | `satan/satan-resonance.el:36` (`cwd.file_kind`) | remove from the default cue rules |
| tank | `satan/satan-tank.el:163,181` | drop the `cwd:` line (or source it elsewhere) |
| tests | canon, evidence, observer, resonance, tank, tools-memory tests; `rich_window.json` fixture | update with the code |
| corpus | `~/satan-corpus/tools/motive_replace.md`, `iteration/state.md` mention `file_kind`/`fs_state` | sweep |

## Decision to make at scoping

Whether the observer loses real positive-outcome coverage without
`:fs_recent_delta`. Its cwd bug means it rarely fired on the right tree; check
recent verdicts' `:predicate` distribution before deleting rather than asserting.

## Scope widened at pickup (2026-09-25)

The user's call: the broker cwd is near-useless as a signal, and would only
earn its keep if most project editing happened in Emacs, which it does not.
So IMP-034 dropped **every** cwd read, not only `:fs_state`: `:git_state`
(live `git` in the same cwd) and `cwd.project` went too. `project:*` is
now sourced only from `vcs.recent_commit` — panopticon's commit feed, which
carries `repo / slug / remote / sha / subject / author / files_changed` and
is cwd-independent. That is the signal the cwd was a bad proxy for.

## Resolution (2026-09-25)

- **Evidence** (`satan-memory-evidence.el`): removed `--git-state`,
  `--fs-state`, `--recent-files`, the `:cwd` opt and
  `satan-memory-evidence-recent-files-limit`. The module now runs no
  subprocess. `--temp-path-p` stays (the commit feed uses it).
- **`--git-output` moved** to `satan-tools-vcs.el` as
  `satan-tools-vcs--git-output` (its only remaining caller), with its
  timeout as `satan-tools-vcs-git-timeout-seconds`; ledger label
  `evidence.git` → `vcs.git`. `satan-tools-vcs` no longer requires the
  evidence module.
- **Canon**: removed `cwd.project`, `cwd.file_kind`, the file-kind helpers and
  extension map. The `file_kind` grammar namespace stays (stored handles),
  retired with the bough namespaces by [[IMP-016]]'s grammar-v2.
- **Observer**: removed P3 `:fs_recent_delta` and `--abs-recent`;
  `--after-state` no longer takes MOTIVE. Ambient kinds keep P1
  (editor edit) and P2 (commit observed). Motive `:project_cwd` is
  unrelated (a motive-declared path) and stays.
- **Resonance**: exclusion list is now `ctx.mode` + `time.day_week`.
- **Tank**: `cwd:` line gone. Percept docstring updated.
- **Docs**: `docs/memory/design.md` and `docs/perceptual-design.md` carry
  an IMP-034 banner / `[removed IMP-034]` markers (the SL-002 convention).
  Corpus `tools/motive_replace.md` corrected.

The "decision to make at scoping" (does the observer lose real coverage
without P3?) was settled by the same call: P3 read `recentf-list` under
the broker cwd, so it rarely looked at the right tree.

### Tests

- Gate: `satan-memory-evidence/assemble-reads-no-cwd` — no cwd keys, no
  subprocess (`satan-trace-call` is a failing spy), `:cwd` inert.
- `satan-memory-canon/fixture-rich-window` — fixture input still carries
  `git_state`/`fs_state` (as stored traces do); expected handles no longer
  include `project:satan` / `file_kind:source`. This is also what
  `satan-renormalize-memory` will now do to stored traces: their
  cwd-derived handles drop on re-canonicalisation.
- `satan-observer/ambient-predicates-read-no-cwd`; multi-fire rebuilt on
  P1 + P2.
- `satan-resonance/gate-admits-project-from-commit-feed`.
- `satan-tools-vcs/git-output-*` (moved from the evidence suite).
- Removed tests of removed behaviour (P3, A12, cwd rules, file-kind,
  cwd gate-skips, `git-state-*`); stripped dead `git_state`/`fs_state`/
  `:cwd` fixture fields.
- `SATAN_TEST_ALLOW_NO_DB=1 just check`: 1301/1322 pass, 21 skipped, 0
  fail; byte-compile of touched files adds no new warnings.

### Left open (not this item)

- `memory_resonate`'s cue derivation (`:cue_only`) skips the commit feed,
  so a resonate cue now carries no `project:` handle at all. Noted on
  IMP-013.
- The motive validator's admitted namespaces (`satan-motive.el`) exclude
  `project`, while the resonance gate now admits `project:*` from the
  commit feed (it always did for that rule). The asymmetry predates this
  item; not changed.
