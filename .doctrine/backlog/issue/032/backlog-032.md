# ISS-032: memory_mark's links schema declares string items; the handler requires {relation, target_trace_id} objects

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found during SL-020 PHASE-02's live VH-1 verification (2026-09-25). The
verifier tried to link a new trace to its predecessor and could not: **no
`links` value satisfies both the client-facing schema and the handler**, so the
argument is unusable by any caller that reads the schema. The prior trace id was
written into the payload prose instead, which is exactly the homemade workaround
the typed-hints contract exists to prevent.

## The contradiction

| site | what it says |
|---|---|
| `satan/satan-tools-memory.el:282` | `'links (list :type 'array :items 'string)` |
| `satan/satan-tools-memory.el:90-97` (`--validate-links`) | each entry must be a plist carrying `relation` and `target_trace_id`; a string entry → `links entries must be objects` |
| `~/satan-corpus/tools/memory_mark.md:28` | "array, optional. Each entry `{relation, target_trace_id}`" |

The validator and the model-facing description agree with each other; the
**args-schema is the outlier**. A client that builds its call from the schema
(the correct thing to do — it is the published contract) produces `["<trace-id>"]`
and is rejected.

## Fix

- Declare the item shape on the schema rather than `:items 'string`, following
  whatever the other array-of-object arguments use (compare `memory_resonate`'s
  `cue` shape and the `hints-shape` conventions in the same file).
- The handler validator and `memory_mark.md` are the authority; change the schema
  to match them, not the other way round.
- Correct the stale sweep note in the file header (`satan/satan-tools-memory.el:15-17`):
  it lists `links` among the fields "declared without type", but `links` **is**
  typed — with the wrong type. Untyped would at least have failed safe.
- Add a test that builds the argument *from the schema* and feeds it to the
  handler, so the two cannot drift again: that is the pair of surfaces the
  existing tests never compare.

## Related

Same species as the other schema/handler drift in that file (`topic`, `kinds`,
`cue.handles`), which the header comment already tracks.
