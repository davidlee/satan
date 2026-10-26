`doctrine slice record-delta 32 PHASE-07 --commit <malebolge oid>` fails with
"single_commit_boundary: <oid> does not resolve to a commit": it resolves in the
slice's own repo only. `slice phase --status` binds code_start/end to this
repo's HEAD as well.

SL-032 practice (user, 2026-10-26): complete the phase, name the foreign repo
and commit in the phase progress note and notes.md, and leave the
UNATTRIBUTABLE VTs for /audit to disposition.
