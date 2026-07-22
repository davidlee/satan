# SATAN JSONL arity trap

# SATAN jsonl-read-file byte-compiled arity trap

## Summary

RESOLVED 2026-05-31: root cause fixed by changing `defun` to `cl-defun`.
Stale `.elc` must be deleted after the change.

## Resolution

The function was changed from `defun` to `cl-defun` which correctly handles
`&key` lambda-list keywords in Emacs Lisp.  `cl-lib` is already required by
the module.  The byte-compiled `.elc` was deleted so the next compilation
picks up the corrected arity.

## Legacy Workaround (no longer required)

Before the fix, callers had two workarounds:

`dl-satan-jsonl-read-file` is defined as `(defun dl-satan-jsonl-read-file (path &key null-object) ...)`.
In Emacs Lisp, regular `defun` does not support `&key` — it's treated as a positional parameter name.
When byte-compiled by the Nix-wrapped `emacs-unstable-pgtk-30.2`, the resulting function has arity `(3 . 3)`,
requiring all three arguments (`path`, `&key`, `null-object`). Calling with just `(path)` errors.

Workaround: use `dl-satan-tools-content--read-jsonl-lenient` or always pass 3 args.
The existing `dl-satan-tools-activity` has the same latent bug (its tests also fail in batch mode).
