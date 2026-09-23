## The format was never goad's to dictate

`~/satan/goad/backend.py`, its own module docstring:

> The protocol is SPEC-001. One JSON document in on stdin, one out on stdout, one process per exchange. **The host understands none of what is below — items, sections, slots and the record format are all this file's business.**
>
> State lives in `./data/YYYY-MM-DD.toml`, one file per day, rewritten whole on every answer.

So the day file is backend.py's private persistence, and the goad host never reads it. The only other mention anywhere is `README.md:16`. Nothing else in `~/satan/goad/` — justfile, service unit, field notes — consumes it.

Research delta 8 treated the TOML as fixed and priced an elisp parser against it. The cheaper move is to stop producing a format SATAN cannot read.

## What actually changes in backend.py

Today (`:77-90`):

```python
def save(now, items):
  DATA.mkdir(parents=True, exist_ok=True)
  lines = [f"# goad — {now.date().isoformat()}", ""]
  for item_id, _section, label in ITEMS:
    entry = items.get(item_id)
    if not entry:
      continue
    lines.append(f"# {label}")
    lines.append(f"[items.{item_id}]")
    for key, value in entry.items():
      rendered = "true" if value is True else "false" if value is False else f'"{value}"'
      lines.append(f"{key} = {rendered}")
    lines.append("")
  record_path(now).write_text("\n".join(lines))
```

That is a hand-written TOML serializer — including a three-branch value renderer — plus a non-atomic whole-file write. It becomes a `json.dump` to a temp file and a `rename`. `load()` loses `tomllib`. The file gets shorter.

## Why not the sidecar

The sidecar is the conservative option and it is worse here. Two files holding the same state introduces a divergence class that then has to be detected (compare mtimes? compare contents?) and reconciled, and it buys a human-readable TOML whose reader is a human who is actually looking at the goad window. One record, one writer, one reader.

## The atomicity is not incidental

`Path.write_text` truncates and rewrites in place. SATAN will read this file from the broker process at percept-build time, on a ~30 minute tick, while the keeper may be answering. A torn read is a malformed record reaching the canon rule. Research delta 7 said *atomic tmp+rename suffices* — correct, and it is not what the code does today. This slice makes it true.

## Amendment — the record grows two fields (RV-007 F-1, F-19)

JSON and the atomic write stand. Two additions the first design did not see.

**`presented_at`.** goad replies `accepted` **before** calling the backend
(`crates/goad/src/controller.rs:735`, stated verbatim in the code comment), so
`goad-emit` exit 0 proves only that the host took the envelope. A dead
`backend.py` yields exit 0. The record therefore has to carry the delivery fact
itself, written at render time by the one process that can know it.

**Deferral provenance.** `answer()` writes the same `deferred_at` key for both
`later:` (one item) and `enough:` (every pending item), so the record cannot
distinguish *the keeper saw this and postponed it* from *the keeper cleared the
slot, quite possibly without ever seeing it* — and since only the first pending
item is rendered, the bulk case routinely defers questions nobody saw. For this
slice those are opposite signals, so they need distinct spellings.


## Amendment, 2026-09-23 — a SATAN ask is filed under its emit date (RV-007 F-29)

`backend.py` keys every write by the date of the event (`record_path(now)`), so
an ask answered after midnight split its record across two files, and one
answered at 23:40 was pending again at 00:10 and asked twice. A SATAN ask's
events (`presented_at`, deferral, answer) are filed in the day file of the ask's
`emitted_at` date, carried on its queue entry, and `pending()` reads its state
from there. The goad evidence source reads the day file of the window start's
date (for the observer, the emit date) — never the classification date. One file
per ask, nothing merged. `presented_at` is stamped on first render only (F-30).
User-accepted 2026-09-23.


## Amendment, 2026-09-23 — the emit date is local and per ask (RV-007 F-33, F-34)

The emit date is the keeper's local calendar date (`record_path`'s), always
derived from a parsed instant, never sliced from a timestamp string:
`satan-intervention-pending` returns `ts` rendered in the `satan_memory` session
zone (GMT). Queue `emitted_at`/`expires_at` carry the local offset and
`backend.py` compares them as instants. Both goad consumers read each ask's
record from that ask's own emit-date file — the percept via the queue entry,
the observer via the intervention — never by their own window's date.
Agent correction under the user-accepted emit-date filing (RV-007 F-33, F-34), 2026-09-23.
