# IMP-035: content_read exposes panopticon page digests

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-10-16. panopticon's `panopticon-digest` (its SL-006..008) writes
per-SHA digest records to `~/.local/state/behaviour/digest/<sha[:2]>/<sha>.digest.json`
(summary, claims, entities, private_surface, model, digested_at). Nothing in
SATAN reads them. At raise time: 1442 digests over 2745 captures.

## Agreed sketch (user, 2026-10-16)

```
content_read
  recent / filter / search rows ── + :summary   (when a digest exists)
  digest  (new scope, hash) ────── summary, claims, entities,
                                   private_surface, digested_at, model
  get     ── unchanged
```

- `satan-tools-content-digest-dir` defcustom beside `satan-tools-content-dir`.
- Missing digest = absent field / error for `digest` scope; never fatal for rows.
- No `private_surface` filtering: `get` already exposes the body; flag passes through.
- Tool description in `~/satan-corpus/tools/content_read.md` updated.
- Out of scope: bundle/capsule injection and percept-matched retrieval
  (IDE-002); searching digest text.

## Done 2026-10-16

- `satan/satan-tools-content.el`: `satan-tools-content-digest-dir`,
  `--read-digest` (absent/unparseable → nil), `--with-summary` on
  recent/filter/search rows, `digest` scope; sidecar + digest paths share
  `--shard-path`.
- Tests: `satan/test/satan-tools-content-test.el` § digest tests (rows carry
  summary iff digested across all three scopes; record round-trip; missing;
  malformed). `just check` green, 1357/1363 (6 pre-existing skips).
- Corpus: `tools/content_read.md` documents the scope, the `summary` field
  and `private_surface`.
- Live smoke: filter on a digested domain returns summaries; `digest` scope
  returns the record.

## Found while here (not fixed)

- No `panopticon-digest` unit/timer is installed on the host; the last
  digest is 2026-10-02, so none of the newest 200 captures has a summary.
  Exposure is only as fresh as that job — enabling its timer is a
  `~/flakes` change.
- 70 stale, gitignored `satan/*.elc` files sit beside the sources and shadow
  them when loaded without `load-prefer-newer` (bit this session's ad-hoc
  test run; `just test` is unaffected).
