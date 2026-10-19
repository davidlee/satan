# ISS-049: Room clones have no git author identity; patch agents invent one per commit

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Observed 2026-10-19 in SL-026 PHASE-08 (job pj-01M59WZMDH8063J8RA97TSBMVF,
room `assistant`, repo `doctrine`): the agent's first `git commit` failed
with "Author identity unknown"; it retried with
`-c user.name="SATAN patch-agent" -c user.email=…` of its own choosing. Every
job therefore picks its own author. Fix in the room (guest git config per
target) or the runner (fixed identity via env on every exec).
