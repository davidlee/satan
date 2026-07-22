# SATAN slugify nil return

# dl-satan-memory-canon-slugify returns nil for empty strings

## Summary

`dl-satan-memory-canon--slugify` returns `nil` for empty strings or
all-symbol input. The old private slugify functions in
`dl-satan-tools-hippocampus` and `dl-satan-tools-org` returned `"untitled"`
instead.

## What to do

When using `dl-satan-memory-canon--slugify` in callers that need a string
(such as file naming):
```elisp
(or (dl-satan-memory-canon--slugify s) "untitled")
```
The memory canonicalizer already filters nil slugs with `(delq nil ...)`.

## Context

DE-003 routed hippocampus and org slugify through the canonical function
(commit bfc17a7). Thin wrappers preserve backward compat with `or` fallback.

## Related

- [[DE-003]]
- `satan/dl-satan-memory-canon.el` — canonical slugify
- `satan/dl-satan-tools-hippocampus.el` — hippocampus wrapper
