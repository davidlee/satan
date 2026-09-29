# IDE-002: Related reading: retrieve page digests matching the current percept

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-09-29. Needs IDE-001 (digests + embeddings).

Use the percept (current window, recent focus/browser segments, git activity)
as a query against page-digest embeddings; put the top few summaries — with
URL and when you read it — into the bundle or behind a tool.

"You read something about this three weeks ago" is the target experience.

- Nearest existing path: IMP-011 (true page-recall via memory traces), blocked
  by the memory-substrate carve. This reaches the same outcome by querying the
  digest index directly.
- Bundle budget: a capsule section vs on-demand tool — decide at design.
- Guard against echoing the page you are reading right now.
