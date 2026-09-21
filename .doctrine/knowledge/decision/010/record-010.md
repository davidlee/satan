## Why provenance turned out to be the wrong criterion

Research delta 7 handed the decision to provenance once concurrency was ruled out. But DEC-005 had not been taken yet. Once the intervention row is the record and the file is a projection, there is no provenance in the file to design for — `run_id`, `mode`, `ts`, `related_motive_id`, `cue_handles` and the eventual verdict all live on the row, queryable, and none of them is better expressed as a filename.

What remains is a merge-shape question, and there the answer is plain.

## The reaping argument

A file per question needs someone to delete files. Deletion has to happen on answer, on expiry, and on withdrawal, from at least two processes. Every missed case is a question that keeps being asked after it was answered — the projection silently disagreeing with the record, which is the exact failure DEC-005 was structured to make impossible.

A whole rewrite has no such case. The file is a pure function of the open rows at write time.

## Symmetry with what is already there

`backend.py:77-90` already rewrites the day record whole on every answer. Under DEC-009 that write becomes a `json.dump` through tmp+rename. The queue file is the same shape from the other direction — written whole by SATAN, read whole by backend.py — so the merge introduces no idiom the file does not already contain.