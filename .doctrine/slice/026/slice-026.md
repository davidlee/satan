# malebolge coding layer: project context, cwd, ripgrep grep

## Context

RFC-019 D7. Malebolge (`~/dev/malebolge`) runs two agents on pi-durable: the
interactive daemon (`src/daemon-main.ts`) and the patch runner's jobs
(`src/runner/`). Both use pi-durable's `CodingTools` (read, write, edit, bash),
which share pi coding agent's lineage. Against the coding agent
(`~/.local/src/pi/packages/coding-agent/src/core/system-prompt.ts`) they lack:

| part | pi coding agent | malebolge today |
|---|---|---|
| project context (`AGENTS.md` / `CLAUDE.md` up the tree) | yes | no: neither `persona.ts` nor `runner/prompt.ts` loads it |
| cwd section | yes | no (daemon) |
| `grep` over ripgrep (`--json`) | optional tool | none; bash only |
| `bash` timeout parameter | yes | **yes already** (pi-durable 1.3.0 `tools/bash.ts:8-13`) |

Consequence today: a patch job on a repo never sees that repo's own
instructions.

Scope was reshaped after the research round (`research/research.md`, user
agreement 2026-10-19): the bash timeout exists upstream, and the shared
env module has no second consumer until vm mode.

## Scope & Objectives

1. **Project context, read once.** Discover `AGENTS.md` / `CLAUDE.md` from the
   conversation's cwd upward (pi's names and order, ancestors first; no global
   file), size-capped, and render it as a constant `project_context` section.
   - Runner: fetched during `preparing`, through the room shell that already
     runs there, from the job's clone; held with the job so prompt composition
     stays a pure function of its inputs (SPEC-004 §Components).
   - Daemon: fetched at session open from its env, as skills are (DEC-067).
   - Never read per request: per-request remote reads cost round trips, can
     mark a job paused (`env.ts:88-124`, `pause.ts:28-39`) and leave stale
     text on failure (`pi-durable prompt.ts:36-43`).
2. **`cwd` section** from the conversation's env cwd (constant per
   conversation).
3. **`grep` tool.** pi's parameter shape (pattern, path, glob, ignoreCase,
   literal, context, limit); `rg --json` through `env.exec` with an argv, so
   it runs in the room over pi-env; line scanning across chunks, exit 1 = no
   matches, pi's caps (100 matches, 500-char lines, 50 KB). Read-only:
   replay-safe, unguarded, like `read`.
4. **Prompt guidance in the corpus, not malebolge.** At most a few bullets
   (show paths clearly; set bash `timeout` on commands that may hang; prefer
   `grep`) in the corpus persona and `prompts/patch-agent.md`. No default
   `rules` text in malebolge (DEC-056).
5. **Governance.** SPEC-004 revision: tools offered gain `grep` (replay-safe);
   prompt composition gains the prefetched project context as an input. One
   DEC: repo-authored project context is instruction to the model, not policy;
   it cannot change scope, paths, ceilings or mode ("the repo itself authors
   no policy", SPEC-004 §Job contract).

## Non-Goals

- Shared room-env module: deferred to the vm-mode slice (RFC-019 D1), where
  the daemon becomes its second consumer (POL-001 cutover rule).
- A bash timeout wrapper or cap: exists upstream; the job deadline is the
  wall-clock authority (REQ-030).
- vm mode, the daemon's tools in the room (RFC-019 D1).
- SATAN tools in patch jobs (RFC-019 OQ-2/OQ-3).
- `find` / `ls` tools: bash with `fd` covers them; revisit after the eval.
- The pi-vs-malebolge eval (RFC-019 OQ-9).
- Fixing the daemon's `~/notes` cwd (CHR-020).

## Affected surface (coarse)

`~/dev/malebolge`:

- New: project-context discovery + section; `grep` tool.
- `src/runner/prepare.ts`, `src/runner/shell.ts`: fetch project context at
  `preparing`.
- Job store (`src/runner/store.ts` and its rows): hold the fetched context.
- `src/runner/prompt.ts` or a section beside it: render it.
- `src/runner/tools.ts`, `src/runner/start.ts`, `src/runner/run.ts`: add
  `grep`, select the extension.
- `src/daemon-main.ts`, `src/session.ts`: daemon fetch at open; select.
- `test/`, incl. `test/runner/tools.test.ts` (pins the four-tool set).

`~/satan-corpus`: persona and `prompts/patch-agent.md` guidance bullets.

`~/dev/satan`: SPEC-004 revision; the new DEC.

## Risks, assumptions, open questions

- **Where context lives for a job.** A job-row field, or a durable document
  beside the conversation; must survive restart and be fixed for the job's
  life (a mid-job `AGENTS.md` edit by the agent does not change its prompt).
- **Which files, how capped.** pi's names (`AGENTS.override.md`, `AGENTS.md`,
  `AGENTS.MD`, `CLAUDE.md`, `CLAUDE.MD`; first per directory); walk stop
  (repo root or `/`); a per-file and total cap (pi has none).
- **Section order** against persona, skills (SL-024) and the job prompt.
- **Daemon before CHR-020** discovers context from `~/notes`; acceptable, or
  land CHR-020 first.
- **pi-durable API churn** (experimental; malebolge pins 1.3.0).
- **Assumption:** `rg` is on the PATH the in-room pi-env daemon inherits via
  `session` (room base has `search` → `ripgrep fd`: `oubliette/vm/room.nix:50-56,
  122`, `/srv/fleet/flake.nix:147`, oubliette DEC-052) — verify live.

## Verification / closure intent

- VT: `grep` against an env (argv shape, `--json` across chunk boundaries,
  caps and line truncation, no-match, rg error); project-context discovery
  (nearest-last order, absent omitted, caps, read through the env); runner
  prompt renders the stored context with no env reads at request time; daemon
  renders `cwd` and context.
- VT: `just check` in malebolge (lint, format, typecheck, tests).
- VH (live, with the user): one patch job on `goad-walk` whose prompt shows
  the repo's `AGENTS.md` and whose `grep` runs in the room.

## Summary

## Follow-Ups

- RFC-019 D1 vm mode (takes the shared env module).
- RFC-019 OQ-9 eval (uses this layer).
