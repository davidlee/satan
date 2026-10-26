# ISS-059: satan-pattern tests read gitignored satan/patterns.eld

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

`satan-pattern/real-eld-parses-all-seeds` and
`satan-pattern/editor-commit-is-matchable` (`satan/test/satan-pattern-test.el:614,629`)
read `satan-pattern-file` → `satan/patterns.eld`, which is gitignored (private
seed data). In a fresh clone or worktree the file is absent and both fail;
in the main tree they pass. Found 2026-10-26 running the SL-032 EN-1 baseline
in a clean worktree at `eaf7d4f`.

Breaks the rule that tests must not depend on prod data
(user memory: tests-independent-of-prod-data; repo is public, data private).

## Shape

Drive both from a checked-in fixture `.eld`, or `skip-unless` the file is
present (as corpus-integration tests do,
mem.pattern.satan.corpus-integration-skip-unless).
