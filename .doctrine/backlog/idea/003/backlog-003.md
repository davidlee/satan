# IDE-003: Assistive bookmark tagging and association, scored against the existing Firefox tags

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-09-29. Needs IDE-001 and panopticon IDE-001 (bookmark ingest).

Firefox (profile `ez06zp0k.default`, surveyed 2026-09-29): 417 bookmarks,
66 folders, **345 distinct tags applied 640 times across 279 URLs**, zero
keywords, zero descriptions. The hand-applied tags are a free labelled set:
suggested tags can be scored against them before anyone trusts them.

Candidate features:
- Suggest tags / folder for new and untagged bookmarks.
- Cluster and relate bookmarks ("these five are one topic").
- Normalise the tag vocabulary (345 tags for 279 URLs suggests near-duplicates).
- **Reconstruct why it was saved**: bookmarks carry no notes, but the browser
  and focus segments around `dateAdded` show what you were doing.

Writing tags back into Firefox is outward-facing; start read-only (suggest).
