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

## Done 2026-10-22

Agreed sketch, implemented:

- Profile headers take an optional `thinking:` field with one of pi's levels
  (`THINKING_LEVELS` in `pi/mcp/profiles.ts`). `Profile.thinking` is absent when
  the field is omitted, and `buildArgv` emits `--thinking <level>` right after
  `--model` only when it is set. Profiles without it get the same argv as before.
- `thinking` is the one place a level is set. A `model` ending in pi's
  `:<level>` shorthand refuses at start-up; a colon that names no level, as in
  `ollama/llama3:8b`, is part of the id. This came from review: two ways to set
  the same knob, with no documented precedence.
- A header field with an empty value now refuses as "has no value" instead of
  "this line is neither" (also from review).
- `read.md` and `write.md` pin `thinking: off`, which makes CLAUDE.md's "no
  thinking" true. Before this, the child ran at pi's settings default (`medium`
  unless set), clamped by the model's capability (`clampThinkingLevel`, pi
  `core/sdk.ts`).
- New `profiles/research.md`: the read form, `thinking: low`.
- The "Document format" prose, once written out in each profile document, now
  lives only in the `profiles.ts` header comment. The documents point there.
- CLAUDE.md routes judgement work to `pi_agent(profile: research)` once the
  policy enables it.
- Suites: 258 pass, 0 fail (254 before).

**Operator act outstanding:** add `"research"` to `profiles` in
`~/.config/pi-mcp/policy.json`, then restart the session. Until then a
`research` call refuses `profile-not-allowed`.

Dogfood: a pi `dispatch-worker` in a fork made by `doctrine worktree fork`, and
one `pi_agent` `read` reviewer (6 requests, final). Friction: the fork reported
"provisioned … 0 copied". The repo has no `.worktreeinclude`, so `.pi/agents/`
(gitignored) and its symlink target `.doctrine/agents/pi/` were missing and had
to be copied in with `cp -rL`. The operator plans to add them to
`.worktreeinclude` upstream.
