# SATAN batch ERT redefined double-load

# batch ERT redefined error from sibling require + suite re-load

## Summary

`ert.el:155`: `ert-deftest` errors `Test 'X' redefined (or loaded twice)`
**only when `noninteractive`** (batch). Interactive (emacsclient) silently
redefines.

Trigger: some `satan/test/*` files `(require 'dl-satan-FOO-test)` to reuse
fixture macros. If the requiring sibling sorts earlier in `directory-files`,
its `require` loads FOO-test (defines every `ert-deftest`, `provide`s the
feature) before the suite loop reaches FOO-test.el; the loop then `load`s it
again → first deftest redefines → error aborts that file's load.

## Fix / invariant

`dl-test-run-suite` skips files whose feature is already provided:
`(unless (featurep (intern (file-name-base f))) (load f ...))`. Each test file
must `(provide 'dl-satan-FOO-test)` (basename) for this to hold. A re-aborted
load also corrupts the file's other tests → spurious "flaky" failures.

This was masked for a long time because `just check` used to be emacsclient
(interactive); DE-006 renamed `check` to batch and surfaced it. See
[[mem.fact.satan.test-db-isolation]].

## Context
