# ISS-067: satan-attrd rejects outcome classification unknown and deletes the row

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Evidence (2026-11-08)

`journalctl --user -u satan-attrd`, 2026-11-08T09:15:00+11:00:

```
outcome inbox: parse failed error=classification: invalid reason for source=outcome: unknown id=4531
```

An outcome-source inbox row carried classification `unknown`. attrd's outcome reason set does not contain it, so the parse fails and the row is deleted. That is the same drop path as `ISS-011`, for a different source.

## Not yet established

- Where the broker produces `unknown` (observer/classify) and how often. The journal since 2026-11-05 showed only `content_backlog` failures before this one.
- Whether `unknown` should reach attrd at all, or be filtered broker-side. That is a contract question (`docs/attributes/outcome-semantics.md`, design-contract §6).

Found while checking SL-037 PHASE-01 EX-3; outside that slice.
