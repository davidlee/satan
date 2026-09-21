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