# CHR-005: Give ~/satan corpus repo a remote (SL-015 follow-up)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

SL-015 PHASE-03 made `~/satan` a standalone git repo (history split out of
`~/notes`, 32 commits). It has no remote. `~/notes` is backed up by its own
remote; `~/satan` is now only on local disk.

Creating a remote (e.g. a private GitHub repo) is outward-facing and was not
asked for, so the phase deferred it (phase D-7). Decide: private GitHub repo,
another host, or an existing backup path that already covers `~/satan`.
Then `git remote add origin … && git push -u origin main`.
