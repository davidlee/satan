# ISS-051: content_read passes the model's query to rg without a -- terminator

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`satan/satan-tools-content.el:300` (search scope) calls
`rg --json --fixed-strings -i QUERY -g *.md` with the model's `query` as a bare
positional. A query beginning with `-` is parsed as a flag: `--files` lists the
corpus's filenames instead of searching; `-v`, `--no-ignore`, `-L` etc. change
the search. Every sibling rg call (`notes`, `hippocampus`) puts `--` before
the pattern.

Not an egress or exec path (SL-027 PHASE-06 egress audit, 2026-10-20): one
argv element cannot pair `--pre=CMD` with a pattern, and rg then refuses
("requires at least one pattern"); tested. Fix: add `"--"` before `query`, with
a test for a query starting with `-`.
