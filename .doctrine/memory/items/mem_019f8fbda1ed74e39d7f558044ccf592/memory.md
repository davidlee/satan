# Use rg, not ugrep, to verify zero-hit renames across satan elisp

## Summary

When an exit criterion is a zero-hit grep over `satan/**/*.el` (verifying a
rename or deletion touched every site), use `rg`, not `ugrep`. `ugrep`
silently mishandles `--include='*.el'` — the invocation returns zero hits
without actually searching the files it claims to, so the check reports
success while never having run.

## Context

Discovered during SL-013 PHASE-02: the first VA-1 run used `ugrep` with
`--include='*.el'` and came back clean, but the exit criterion had not
actually been checked. Re-confirmed relevant in PHASE-03, whose runtime
phase sheet flagged the same trap up front.

The danger is specifically the silence: a broken invocation and a genuinely
passing check produce the identical zero-hit output. There is no error to
notice.

## Mitigation

Always include a **live positive control** in the same grep invocation style
— a name known to still exist in the tree. If the control also comes back
zero, the tool/invocation is broken, not the codebase. Do not reuse a name
that a prior phase already zeroed (it will read as a false positive for
"the grep works"); pick one confirmed still-live at the time of the check.

## See also

- [[mem.pattern.satan.rg-json-path]] — a different `rg` gotcha (JSON output
  path-field nesting), same tool, unrelated failure mode.
