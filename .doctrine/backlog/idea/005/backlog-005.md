# IDE-005: Bounded links-of-links discovery from high-signal seed pages

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-09-29. Needs IDE-001 and a fetcher (panopticon IDE-001 revives the
unused `panopticon/ingest/extractor.py` Trafilatura path).

Follow outbound links of high-signal pages and digest the ones that look
relevant. Without bounds this is a crawler; proposed bounds:

- Seeds: bookmarks and pages linked from doctrine.engineering only.
- Depth ≤ 1.
- Daily fetch budget; per-domain politeness; robots respected.
- Score candidate against its seed (embedding) *before* digesting.
- Output is a suggestion queue, not auto-bookmarking.
