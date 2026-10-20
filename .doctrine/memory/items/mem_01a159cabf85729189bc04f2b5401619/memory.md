Chartering `capsule-orchestrator` with `async: false` gives the child a hard 30-minute wall. When it fires, the run reports `terminated: timed-out` with the partial output, and any nested worker it had spawned is cancelled.

Observed on SL-029: a charter of PHASE-04..06 got two phases committed and died inside the third (no partial code in the tree); a four-repair charter died after landing the repairs but before its ledger disposals. Both were recovered by re-chartering the same phases fresh.

Practical rule: charter ≤3 phases, and give a big phase its own charter. Before re-chartering, always inspect the tree — `git log`, `git status`, the phase tomls — because the child may have committed and merely failed to hand back.
