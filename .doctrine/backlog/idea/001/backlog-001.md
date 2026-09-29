# IDE-001: Page digest layer: per-URL summary, key claims and embedding over panopticon content

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-09-29 in a brainstorm on bookmarks, history and doctrine.engineering.
This is the keystone: IDE-002..005 all consume it.

## Shape

```
 frontier                         digest (keyed by URL)          consumers
 dwell captures (content/)  ─┐    summary                  ┌─▶ SATAN reads   (IDE-002)
 bookmarks (panopticon      ─┼─▶  key claims, entities  ───┼─▶ tagging       (IDE-003)
   IDE-001)                  │    embedding                ├─▶ blog links    (IDE-004)
 outbound links (IDE-005)   ─┘                             └─▶ link frontier (IDE-005)
```

## Ground truth (surveyed 2026-09-29)

- panopticon `~/.local/state/behaviour/content/`: ~2379 pages, `articles.jsonl`
  index + `<sha>.json` (text/html) + `<sha>.md`; dedup by text SHA-256;
  heuristic `quality_score`. Written by `panopticon/ingest/content.py`.
- No summaries exist anywhere. Readability `excerpt` is the nearest thing.
- SATAN reads bodies only on demand (`satan-tools-content.el`, `content_read`);
  canon emits only `content_domain:<d>` handles (DE-005 DEC-2).

## Open decisions

- **Home.** Not the broker: POL-001 earns-the-seat — no editor use. ADR-001
  separates perception (panopticon) from cognition; a digest is cognition, so
  likely a separate worker whose output SATAN reads, not panopticon itself.
- **Model / privacy.** Summarising bodies through a remote API ships them
  off-host. panopticon `plan.local.md:180` already names "local model digests
  raw, only summary leaves the host" as the v3 intent. Local model, or an
  explicit remote allowlist.
- **Key.** URL (canonicalised) vs content SHA. Same URL, changed content →
  re-digest?
- **Retention.** Pairs with panopticon RSK-001 (content store unbounded).

## Relation to IMP-011

IMP-011 wants page-recall via memory-store traces and is blocked by the
memory-substrate carve (IMPR-007). A digest index queried directly reaches
recall without entrenching the substrate.
