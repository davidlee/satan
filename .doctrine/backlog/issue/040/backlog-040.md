# ISS-040: satan-trace-call merges child stderr into stdout; psql warnings corrupt parsed query results

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Symptom (2026-10-14)

`satan-attribute-listener` logged `bad JSON in row N: could not parse JSON
stream: 1, nil, 1` for every inbox row during a ruminate run (rows
5063–5088 claimed but never processed or deleted; left unrecovered by choice).

## Cause

- `satan-trace-call` (`satan/satan-trace.el` ~258–260) calls
  `call-process` / `call-process-region` with destination `t`, which merges
  the child's stderr into the stdout buffer.
- A glibc upgrade (2.42 → 2.44) made Postgres emit a collation-version
  mismatch `WARNING/DETAIL/HINT` on stderr for every connection. Merged, it
  prefixed each `satan-db-query` result, so the JSON parse failed at char 1.
- Environment fixed the same day (`REINDEX DATABASE` + `ALTER DATABASE …
  REFRESH COLLATION VERSION` on `satan_memory`, `satan_memory_test`). The code
  defect remains: any future stderr chatter (warnings, notices, deprecation
  messages) silently corrupts every parsed psql result.

## Blast radius

Every `satan-db-query` caller that parses output (attribute listener, memory
store, patch store, memory-migrate, …), and any other `satan-trace-call`
consumer that treats `:stdout` as data.

## Proposed fix

- `satan-trace-call` captures stderr separately (destination `(t FILE)` with
  a temp file), returns it as `:stderr`, and keeps `:stdout` pure.
- `satan-db-query` uses `:stderr` for its `(error . MSG)` text on non-zero
  exit; success output is stdout only.
- Red test first: a child that writes to stderr and exits 0 must yield clean
  `:stdout`.

## Related

- ISS-025 — another psql-output parsing fragility (`|` splitting).
