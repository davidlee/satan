# IDE-010: Native Emacs client for pandaemonium over the watchEvents stream

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From CHR-012. v0 is comint over `pandaemonium-attach` (line text). A native
client would read the NDJSON event stream directly: tool calls as
collapsible sections, thinking hidden/foldable, cross-client user turns shown
(the line client omits them), `/abort` on `C-c C-c`.

Gotcha (memory `mem.fact.pi.durable-is-a-library`): an answer's text spans
`message_start`, `message_update` (deltas or whole replacements) and
`message_end`; track it, don't just append deltas.
