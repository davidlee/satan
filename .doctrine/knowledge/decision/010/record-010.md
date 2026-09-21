## Why provenance turned out to be the wrong criterion

Research delta 7 handed the decision to provenance once concurrency was ruled out. But DEC-005 had not been taken yet. Once the intervention row is the record and the file is a projection, there is no provenance in the file to design for — `run_id`, `mode`, `ts`, `related_motive_id`, `cue_handles` and the eventual verdict all live on the row, queryable, and none of them is better expressed as a filename.

What remains is a merge-shape question, and there the answer is plain.

## The reaping argument

A file per question needs someone to delete files. Deletion has to happen on answer, on expiry, and on withdrawal, from at least two processes. Every missed case is a question that keeps being asked after it was answered — the projection silently disagreeing with the record, which is the exact failure DEC-005 was structured to make impossible.

A whole rewrite has no such case. The file is a pure function of the open rows at write time.

## Symmetry with what is already there

`backend.py:77-90` already rewrites the day record whole on every answer. Under DEC-009 that write becomes a `json.dump` through tmp+rename. The queue file is the same shape from the other direction — written whole by SATAN, read whole by backend.py — so the merge introduces no idiom the file does not already contain.

## Amendment — the projection needs a maintenance trigger (RV-007 F-11)

"Total by construction" was true of each rewrite and false of the file over time.
Only the ask handler was specified to rewrite the queue, while the observer
retires rows independently at classification (`satan/satan-observer.el:424`). So
a matured, retired ask kept its queue entry until some later ask happened to
rewrite the file, and `backend.py` would keep re-presenting it. After state loss
nothing regenerated until the next ask.

The rewrite is now triggered at **classification time as well as at emit**. That
is also what makes the regenerability property [[DEC-005]] leans on actually
hold, so it earns the test this decision already promised it.