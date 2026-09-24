@.doctrine/state/boot.md
If you have NOT seen `BOOT-SENTINEL: doctrine-governance-snapshot` anywhere in your context (system prompt or preceding messages), you MUST read the file referenced above now. If you HAVE seen it, you MUST NOT — the content is already in context.

For Emacs Lisp edits:

1. Never manually balance parentheses across a whole file.
2. After changing any .el file, run:
   bin/elisp-locate-paren-error FILE
3. If it fails:
   - first inspect `error.line` if present;
   - then inspect the first item in `open_stack`;
   - restrict repairs to the reported line or `toplevel.start_line..toplevel.end_line`.
4. Re-run `bin/elisp-locate-paren-error FILE` until it returns {"ok":true}.
5. Only then run byte compilation/tests.
