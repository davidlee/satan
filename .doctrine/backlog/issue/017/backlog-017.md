# ISS-017: Persistent run failures announce once: streak==1 notify gate silences every later failure

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Split from [[ISS-012]] (2026-09-23) — its original item 2, "a run that fails on
auth should be loud". ISS-012 keeps the credential-acquisition half.

`satan-broker--announce-failure` (`satan/satan-broker.el:331`) always writes a
`logger` line, but sends a desktop notification only when
`satan-broker--failure-streak-count` is exactly **1**. A failure that persists
is therefore announced once — at 07:47 on the first morning, possibly to an
empty room — and afterwards only to the journal. That is how ISS-012's
motd/morning failures ran ~3 weeks unnoticed.

Compounding it: the harness computes an error `class` (`classify_error`,
`satan/harness/runloop.py:115`) that the broker never reads, so an `auth`
failure is indistinguishable from any other in the announcement.

Owned by SL-017 (objectives 4 and 5).
