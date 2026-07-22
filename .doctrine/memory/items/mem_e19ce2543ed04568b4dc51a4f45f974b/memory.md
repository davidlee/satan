# SATAN ingest cursor backlog depth

# dl-satan-ingest-cursor backlog-depth API and test fixture pattern

Test recipe for the ingest cursor ([[mem.fact.satan.ingest-cursor-store]]).

## Backlog-depth fn

`(dl-satan-ingest-cursor-backlog-depth)` → `(:focus N :browser N :content N
:total N)`, emacsclient-callable (waybar surface). `cursor==head` ⇒ 0; missing
cursor ⇒ full count (from-head). Pure read. **Not auto-loaded — external
callers must `(require 'dl-satan-ingest-cursor)` first**
([[mem.fact.satan.ingest-cursor-require]]).

## Test fixture (let-bind ALL of these to temps)

- `dl-satan-tools-activity-dir` — segment day-files (`segments/<kind>-<day>.jsonl`).
- `dl-satan-tools-content-dir` — content captures.
- `dl-satan-ingest-cursor-state-file` — the cursor JSON.
- `dl-satan-tools-descriptions-dir` — `dl-satan-tools-content` schema assembly
  needs it bound (mirrors `dl-satan-tools-content-test--with-store`).

New test file must `(provide 'dl-satan-ingest-cursor-test)`
([[mem.fact.satan.batch-ert-redefined-double-load]]).

## perceive-purity spy (in dl-satan-broker-test.el)

`dl-satan-broker/perceive-is-pure` spies the forbidden-call set; it MUST include
the cursor writers `dl-satan-ingest-cursor-advance` and
`dl-satan-ingest-cursor--write` (perceive never advances the cursor — consume-only,
see [[mem.fact.satan.perceive-consume-seam]]).
