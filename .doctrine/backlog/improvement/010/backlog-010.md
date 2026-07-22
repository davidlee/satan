
# Interactive SATAN: inject last percept + attributes at startup

The interactive SATAN agent (the PI/MCP dev harness from [[DE-007]], now run with
its pwd moved out to `~/notes`, commit `ec28bc8`) boots with an appropriate system
prompt but **no perceptual or affective context**: no percept capsule, no attribute
capsule, none of the quintessential startup data a real tick run carries.

Root cause: that startup data is minted by a full harness run (`dl-satan-run-prepare`
→ broker → percept build → attribute capsule render). The interactive session does not
go through that path, so it starts cold.

## Proposed improvement

We cannot mint fresh percept/attributes without a harness invocation. But we can give
the interactive agent the **last available** snapshot instead of nothing — inject or
expose the most recent run's:

- `bundle.json` (run bundle — context the last tick assembled)
- `percept.json` (last percept capsule)

from the most-recent run directory. Runs live at
`~/notes/satan/runs/<YYYY-MM-DD>/<run-id>/` (`dl-satan-runs-dir`,
`dl-satan-run-dir-for-id`); percept is written there by `dl-satan-percept-persist`.
There is no `most_recent` symlink today — the resolver would pick the newest bucket/run,
or one could be maintained on run completion.

Two delivery options (DR to choose):
1. **Inject** the last bundle+percept into the interactive system prompt at session start.
2. **Expose** a read tool so the agent can pull the last bundle/percept on demand.

Caveat to capture in design: the snapshot is **stale** — it describes the moment of the
last tick, not now. Must be labelled as last-known, not current, so the agent does not
treat it as a live percept (vision §13 "did I overuse recent-run prose instead of current
evidence?").

## Status

Idea. Small, self-contained; depends only on the existing run-dir layout and the
interactive harness ([[DE-007]]).
