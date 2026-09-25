# ISS-033: Tool results carrying nil serialise as {} on the wire, not false

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found in SL-020 PHASE-02 while fixing a leaked `:_sort` key in a tool result.
The leak was harmless **by accident**: the wire layer absorbed an Emacs time
object and rendered it as a bare integer array. Probing that path surfaced the
general defect underneath.

## The defect

`satan-jsonl-prepare` maps `nil` to an empty JSON **object**, so a false-valued
field reaches the model as `{}`:

```
(satan-jsonl-prepare '(:truncated nil))  ->  {"truncated":{}}
(satan-jsonl-prepare '(:truncated t))    ->  {"truncated":true}
(satan-jsonl-prepare '(:title nil))      ->  {"title":{}}
```

`{}` is not `false` to any reader: it is an object, and it reads as *something
present* rather than as *no*. Every tool result with a nil field is affected —
`notes_recent`'s `:title`/`:tags` for non-denote names, `notes_read`'s
`:truncated`/`:tags`, and whatever else returns nil.

## Why it is not fixable per tool

The codebase already has the markers for wire-false (`satan-broker--on-tool-call`
sends `:ok :false`), so it is tempting to have each producer emit `:false`. That
would be worse: **`:false` is a truthy symbol in elisp**, so it would break every
caller that tests the elisp-level value (`(null (plist-get p :truncated))`,
`(when (plist-get entry :title) …)`) while reading correctly on the wire. The
encoding decision belongs in one place — the shared layer that owns the wire —
where it can be applied to every record uniformly.

## Options

1. **Coerce `nil` to JSON `null` in `satan-jsonl-prepare`** (the narrowest fix):
   elisp callers keep seeing `nil`, the wire carries `null` instead of `{}`.
   Risk: `satan-jsonl--coerce-vectors`/`--plist-p` treat `nil` as an empty list,
   so the coercion must happen before that classification, and existing consumers
   that *rely* on `{}` (unlikely, but check the derived bundles) would see a
   change.
2. **Enforce an explicit-marker discipline at producers** (every nullable field
   written as `:null`/`:false`). More honest at the source, but it pushes a wire
   concern into every tool and re-opens the truthiness trap above.

Whichever is chosen, pin it with a test over a tool result carrying `nil`, `t`
and a string.

## Related

Same encoder misreading a list it should not have to interpret: **ISS-027**
(predicates → `{}`), **IMP-015** (`run_id` → `{}`). This is the third instance;
if the family keeps recurring, the shared layer is where the invariant belongs
rather than a fourth per-site patch.
