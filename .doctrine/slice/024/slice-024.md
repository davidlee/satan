# malebolge: advertise Agent Skills in the system prompt

## Context

Interactive SATAN runs on two hosts. Under `jpi` (pi-coding-agent) it gets
**Agent Skills** (a directory holding a `SKILL.md` with YAML frontmatter that
gives a `name` and `description`). The `~/notes` flake passes them with
`--skill <path>`, and pi lists each one in the system prompt so the model can
`read` the full file when a task matches. This is progressive disclosure.

malebolge (`~/dev/malebolge`, SATAN's durable session daemon on
`@earendil-works/pi-durable`) has no skill loading: pi-durable is a library,
and coding-agent features such as skills do not come with it. So SATAN
under malebolge cannot see `goad-backend`, the goad kit's skill for writing
goad backends into `~/satan-corpus/goad/`. The corpus scaffold
(`~/satan-corpus/system/scaffold.txt`) already names that skill as SATAN's.

Origin: a goad-session handover (`~/dev/malebolge/docs/handover-skills-extension.md`,
goad slice 012). Its nix notes predate CHR-018: `jailed-malebolge` now lives
in this repo's `flake.nix`. It is on the gateway with file-held key custody
and has no `op run`, and `goadPkgs` (including `goad-kit`) is already in its
`extraPkgs`. The `~/satan-corpus/goad` directory is already bound read-write.

Reference implementation: pi's `formatSkillsForPrompt`
(`~/.local/src/pi/packages/coding-agent/src/core/skills.ts`) and pi's
`docs/skills.md` (frontmatter rules: `name` and `description` are
required, a skill without a description is skipped, and
`disable-model-invocation: true` hides a skill from the listing).

## Scope & Objectives

1. **A `skills` extension in malebolge**, shaped like `personaExtension`
   (`src/persona.ts`): one `defineExtension` with one system prompt section.
   It lists each skill's name, description and `SKILL.md` location inside
   pi's `<available_skills>` block and wording, so both hosts prompt the same
   way.
2. **Config input:** `MALEBOLGE_SKILLS`, a colon-separated list of skill
   directories, resolved in `resolveConfig` (`src/config.ts`). If it is
   unset or empty, there is no section.
3. **Frontmatter reading:** `name` and `description` only, following pi's
   rules (including `disable-model-invocation`). A malformed or missing skill
   is skipped with a stderr line; it never fails the daemon.
4. **Wiring:** the extension joins the `extensions` array in
   `src/daemon-main.ts`.
5. **Deployment:** the `malebolgeJailOptions` in this repo's `flake.nix`
   set `MALEBOLGE_SKILLS` to the `goad-backend` skill directory inside
   `goad.goad-kit`, and the `malebolge` jail-profile probe asserts that
   setenv.

## Non-Goals

- Skill discovery by scanning directories (`~/.pi/agent/skills`, project
  `.pi/skills`). Only explicit paths are in scope.
- A `/skill:name` command, or injecting a skill's body into the prompt. The
  model loads the body itself with `read`, which `CodingTools` already
  provides.
- Changing `jpi`'s skill wiring in `~/notes`.
- Re-reading skills on every turn: skills are read once at startup
  (DEC-067).

## Affected surface

malebolge (`~/dev/malebolge`, its own repo; selectors cannot fence it):

- `src/skills.ts` (new), `src/config.ts`, `src/daemon-main.ts`
- `package.json` / `package-lock.json` (`yaml`, DEC-066)
- `test/skills.test.ts` (new), `test/config.test.ts`
- `README.md` / `docs/internals.md` (env var and extension list)

satan (this repo):

- `flake.nix`: `malebolgeJailOptions` and the `jailProbes.malebolge` profile
  check

## Risks, assumptions, open questions

- **Frontmatter parser.** Settled: the `yaml` package, as pi uses
  (DEC-066). The tests still cover: no frontmatter, no description, quoted
  values, and folded or block scalars (`>`/`|`).
- **Prompt wording drift.** Copying pi's wording means pi changes can make
  the two hosts diverge. Accepted; record the pi version the wording came
  from.
- Assumption: `goad.goad-kit` lays the skill out at `kit/skills/goad-backend`,
  as `~/notes/flake.nix`'s `goadSkill` does for `jpi`.

## Verification / closure intent

1. malebolge's gate (`justfile`): tests, lint, typecheck. The pure parts
   (frontmatter reading, rendering) are tested directly, plus one test
   through `openTestHarness` showing the section reaches a turn's system
   prompt, following `test/persona.test.ts`.
2. `nix flake check` in this repo passes the `malebolge-jail-profile` check,
   including the new setenv.
3. Live (VH, verified by a human): rebuild, start the jailed daemon, attach.
   SATAN names `goad-backend` with its description when asked. Asked to write
   a trivial goad backend under `~/satan-corpus/goad/<name>/`, it reads the
   skill's `SKILL.md` first (visible in the session entries), and the result
   passes `goad-check --config config.toml`, run with a scratch
   `XDG_STATE_HOME`.

## Summary

Port pi's skill listing to malebolge as a small extension fed by an env var,
and point the jailed daemon at goad's `goad-backend` skill.

## Follow-Ups

- Once landed, `~/dev/malebolge/docs/handover-skills-extension.md` is
  consumed and can be deleted.
