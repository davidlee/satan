# malebolge coding layer: project context, cwd, coding rules, bash timeout, ripgrep grep

## Context

RFC-019 D7. Malebolge (`~/dev/malebolge`) runs two agents on pi-durable: the
interactive daemon (`src/daemon-main.ts`) and the patch runner's jobs
(`src/runner/`). Both use pi-durable's `CodingTools` (read, write, edit, bash),
which share pi coding agent's lineage. What they lack against the coding agent
(`~/.local/src/pi/packages/coding-agent/src/core/system-prompt.ts`) is mostly
prompt, plus two tools:

| part | pi coding agent | malebolge today |
|---|---|---|
| coding rules (concise, show paths, per-tool guidelines) | yes | persona only (daemon); job prompt conventions (runner) |
| project context (`AGENTS.md` / `CLAUDE.md` up the tree) | yes | no: neither `persona.ts` nor `runner/prompt.ts` loads it |
| cwd section | yes | no (daemon) |
| `bash` timeout parameter | yes (`tools/bash.ts:42`) | no |
| `grep` over ripgrep (`--json`) | optional tool | none; bash only |

Consequence today: a patch job on a repo never sees that repo's own
instructions.

## Scope & Objectives

1. **Shared environment module.** Lift the room execution-environment
   construction out of `src/runner/env.ts` into a module both agents can use
   (RFC-019 D1 needs it from the daemon in a later slice). Behaviour unchanged.
2. **`coding` extension** (pi-durable `defineExtension`), selected by both
   agents, carrying sections:
   - `rules`: the subset of pi's `buildRules` that fits SATAN;
   - `project_context`: `AGENTS.md` / `CLAUDE.md` discovered from the
     conversation's cwd upward, **read through the call's `ExecutionEnv`** (in
     a job, the clone in the room, never the host checkout);
   - `cwd`: `input.env?.cwd`.
3. **`bash` timeout.** A model-settable `timeout` (seconds, bounded), by
   wrapping or hooking pi-durable's `bash`.
4. **`grep` tool.** pi's parameter shape (pattern, path, glob, ignoreCase,
   literal, context, limit); runs `rg --json` via `env.exec` with an argv, so
   it works in the room over pi-env (room has `rg`/`fd`: oubliette
   `fragments.nix` extra `search`). Output capped and truncated as pi does.

## Non-Goals

- vm mode, the daemon's tools in the room (RFC-019 D1; next slice).
- SATAN tools in patch jobs (RFC-019 OQ-2/OQ-3).
- `find` / `ls` tools: bash with `fd` covers them; revisit after the eval.
- The pi-vs-malebolge eval (RFC-019 OQ-9): uses this slice, separate work.
- Persona or corpus prompt changes beyond what the rules section needs.

## Affected surface (coarse)

All in `~/dev/malebolge`:

- `src/runner/env.ts` → a shared module (e.g. `src/env/` or `src/room-env.ts`).
- New: the coding extension and the `grep` tool (e.g. `src/coding/`).
- `src/daemon-main.ts`, `src/runner/start.ts`: select the extension.
- `src/persona.ts`, `src/runner/prompt.ts`: only if section order or overlap
  with job conventions needs it.
- `test/`: new tests for grep, project context, timeout.

## Risks, assumptions, open questions

- **Wrap or own `bash`.** A wrapper (`wraps`, or a `beforeTool` rewrite) is
  cheaper and survives pi-durable upgrades; owning it duplicates pi-durable's
  184 lines. Lean: wrap. Check pi-durable 1.3.0 offers a hook that can impose
  a deadline on a running call.
- **Rules vs persona and job conventions.** Where `rules` sits against the
  SATAN persona; whether job prompts take it at all, given
  `prompts/patch-agent.md` conventions. Avoid two voices saying the same thing.
- **Which files are project context.** `AGENTS.md` only, or `CLAUDE.md` too
  (the user's repos use both); how far up the tree; size cap.
- **Prompt cache.** Sections are re-rendered each request and only changes are
  resent; project context read per request through a remote env costs a round
  trip per request. Cache per conversation and cwd, or accept it.
- **pi-durable API churn** (experimental; malebolge pins 1.3.0).
- **Assumption:** `rg` is on the room's base PATH for `env.exec` (the `search`
  extra is in the base, DEC-052) — verify live.

## Verification / closure intent

- VT: `grep` against a fake env (argv shape, `--json` parsing, caps and
  truncation, no-match, rg error); project-context discovery (nearest wins,
  absent omitted, read via env not host fs); timeout (range refused, deadline
  enforced); env module extraction keeps runner tests green.
- VT: `just check` in malebolge (lint, format, typecheck, tests).
- VH (live, with the user): one patch job on `goad-walk` whose prompt shows the
  repo's `AGENTS.md` and whose `grep` runs in the room; the daemon's prompt
  shows `cwd` and project context.

## Summary

## Follow-Ups

- RFC-019 D1 vm mode (uses the shared env module).
- RFC-019 OQ-9 eval (uses this layer).
