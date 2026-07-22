# SATAN elc stale cache void-function

# stale .elc cache causes void-function after adding functions

## Summary

When you add a new `defun` to an existing elisp module, stale `.elc`
byte-compiled cache files can cause `void-function` errors even though
the source file is correct.

## Fix

```bash
find satan/ -name '*.elc' -delete
```
Then re-run tests. This happened during DE-003 when `dl-satan-db-parse-pg-array`
was added to `dl-satan-db.el` — stale `dl-satan-db.elc` didn't contain the
new function, causing `dl-satan-memory-store-test.el` to fail with
`void-function` even though `dl-satan-memory-store.el` correctly required
`dl-satan-db`.

## When to do it

- After adding any new `defun` to a module that already has a `.elc`
- Before running test suites that transitively depend on the modified module
- As first troubleshooting step for unexplained `void-function` errors

## Related

- [[DE-003]]
