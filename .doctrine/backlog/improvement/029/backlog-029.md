# IMP-029: Evidence assembly re-parses ISO dates per row and per sort comparison

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`satan-memory-evidence--git-commits-status` and `--segments-status` call
`date-to-time` (which goes through iso8601-parse and encode-time) on every
segment row, in both `satan-memory-evidence--filter-segments` and the `sort`
comparator, so each comparison parses dates again. They also re-read the JSONL
segment files on every call. Profiled 2026-09-24 via the tank's 5s timer: these
two paths were about 47% of CPU while the user was typing, with heavy GC.

Mitigated, not fixed: satan `ad1a5a3` stops the tank refreshing while it is
hidden. The emacs.d config now byte-compiles SATAN (`8752fe9`). The same
evidence assembly still runs per broker spawn and whenever the tank is visible.

Fix: parse each row's timestamp once, filter and sort on that parsed value,
and consider caching segment reads by file modification time.
