# IMP-050: pi-mcp profiles carry a thinking level, so pi_agent can replace pi-research

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

The pi-mcp profile header (`pi/mcp/profiles/*.md`) carries `filesystem`,
`model` and `tools`, but no thinking level. So the `pi_agent` tool can only
run no-thinking recon. Judgement delegation still goes through
`scripts/pi-research` (thinking on by default) and `scripts/pi-scout --think`,
as CLAUDE.md now says.

Shape: an optional `thinking:` header field (pi's `--thinking` levels),
validated at snapshot load and passed through argv construction in
`spawn.ts`. Then add a `research` profile (`filesystem: read`, thinking on)
and enable it in the operator policy.

Found while making `pi_agent` the default delegation route (2026-10-21,
after SL-029 closed).
