# IDE-004: Suggest doctrine.engineering link candidates from bookmarks and history

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-09-29. Needs IDE-001; better with IDE-003.

doctrine.engineering (`~/dev/www/doctrine.engineering`) publishes `kind: link`
entries in `.src/stream/`, created by `just link <url> ["Title"]`. Links
started 2026-09-27 (2 published). Only declared tag: `doctrine` (`site.yml`).

Rank bookmarks/history digests by affinity to the published articles and the
`doctrine` theme; emit ready-to-run `just link <url> "Title"` lines, perhaps
with a one-line gloss draft.

Constraints from the blog's own decisions:
- `new.rb` is offline by design (DEC-009) — the suggester supplies the title;
  the generator stays unchanged.
- Suggest, never write: publishing is the author's call.
- Don't re-suggest what is already in `.src/stream/` (match on `target`).
