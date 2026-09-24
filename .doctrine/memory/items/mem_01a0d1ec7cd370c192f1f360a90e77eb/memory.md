`satan-memory-migrate-status` compares the sha256 of each on-disk file in
`satan/memory/migrations/` with the checksum recorded when it was applied.
Any byte change — a comment included — makes that migration `tampered`, and
`satan-memory-migrate-apply` then **refuses to apply anything**.

Bit us 2026-09-24: SL-012's `dl-satan-*` → `satan-*` rename sweep edited
comments in 0003/0004/0006; nothing noticed until SL-016 needed 0008 on the
live `satan_memory`. Fixed by restoring the applied bytes
(`git show <pre-sweep-sha>:path > path`), commit `4ec6198`.

How to apply:
- Rename/format sweeps must exclude `satan/memory/migrations/`.
- Changing an applied migration's behaviour = a new migration.
- Diagnose `tampered`: `git log -- <file>`, then hash the pre-change blob
  (`git show SHA:path | sha256sum`) against the recorded checksum.
- Test DBs re-migrate per test, so tests never catch this; only the live DB does.
