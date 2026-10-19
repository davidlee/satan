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

Settled in design (run dr-01a152b2, 2026-10-19): DEC-070..DEC-073.

1. **Project context, read once** (DEC-072). Sources in render order, each
   capped at 64 KiB with a marker: `.pi/APPEND_SYSTEM.md` at cwd; for patch
   jobs in a repo with `.doctrine/`, doctrine's boot (DEC-071); pi's
   five-name chain (`AGENTS.override.md`, `AGENTS.md`, `AGENTS.MD`,
   `CLAUDE.md`, `CLAUDE.MD`; first readable regular file per directory,
   symlinks followed) from cwd up to the nearest git root, ancestors first.
   No global files; never `.pi/SYSTEM.md`. One renderer, pi's format.
   - Runner: read during `preparing`, the last step inside `readyRoom`'s retry
     loop, from the clone's working tree through the room shell; composed into
     the job's first input message before the job block (DEC-070), so the
     conversation holds it. Doctrine boot: `doctrine prompt resolve --role
     orchestrator` in the clone, from the repo's own tool set (DEC-071), only
     when `git check-ignore` confirms `.doctrine/state/boot.md` is ignored;
     60 s timeout and output caps enforced in the room (`RoomShell` gains
     optional per-call limits). Binary missing, non-zero exit, timeout, empty
     output or boot not ignored → `context_degraded` job event, omitted; room
     lost is retried as readiness; a clone doctrine left dirty fails
     `preparing` (`dirty_clone`; never cleaned). Every exec in `preparing`,
     the existing `checkRoomClone` / `ensureJobBranch` git calls included, carries a timeout and output caps, since the repo's
     tool set may supply the binaries; degradations are data, recorded once
     by `admit`.
   - Daemon: read once at startup with node fs; constant `project_context`
     section; sections persona → project_context → skills → cwd.
   - Never read per request (round trips, pause marks, stale text on failure).
2. **`cwd`**: daemon section (path, tagged); runner job block gains
   `Working directory:`.
3. **`grep` tool.** pi's parameters plus an additive `noIgnore`
   (`--no-ignore --glob '!.git'`); `rg --json` through `env.exec` with an
   argv; `--context N` from rg itself; abort at the match limit or at 50 KB
   of output; pi's output and caps (100 matches, 500-char lines, 50 KB),
   with every host-side buffer bounded (rg `--json` ignores
   `--max-columns`); exit 2 with matches keeps them. Read-only: replay-safe,
   unguarded. In the runner's `JobTools` and as a `grep` extension in the
   daemon.
4. **Prompt guidance in the corpus, not malebolge.** `prompts/patch-agent.md`
   (tool list gains `grep`; project instructions precede and never override
   the job block; the job block and corpus override repo workflow — no
   skills, slices or worktrees) and `prompts/interactive.txt`: show paths clearly; set bash
   `timeout` on commands that may hang; prefer `grep`. Not `system/scaffold.txt`.
5. **Governance.** DEC-073: repo-authored context is instruction, not policy.
   SPEC-004 REV (drafted in design, applied at reconcile): composition gains
   the project-context input; §Job contract gains DEC-073; tools offered gain
   `grep` (replay-safe); audit vocabulary gains `context_degraded`.
6. **Fleet.** malebolge's `dev-tools` gains `doctrine` (DEC-071); satan's
   `jailProbes.malebolge` asserts `rg` (SPEC-002 NF-004).

## Non-Goals

- Shared room-env module: deferred to the vm-mode slice (RFC-019 D1), where
  the daemon becomes its second consumer (POL-001 cutover rule).
- A bash timeout wrapper or cap: exists upstream; the job deadline is the
  wall-clock authority (REQ-030).
- vm mode, the daemon's tools in the room (RFC-019 D1).
- SATAN tools in patch jobs (RFC-019 OQ-2/OQ-3).
- `find` / `ls` tools: bash with `fd` covers them; revisit after the eval.
- The pi-vs-malebolge eval (RFC-019 OQ-9).
- Fixing the daemon's `~/notes` cwd (CHR-020; independent, inq-7).
- A general per-repo room setup step (IDE-012); doctrine in the daemon;
  `doctrine memory sync` before boot.
- Loading repo-authored extensions (raw pi or pi-durable) into the runner.

## Affected surface (coarse)

`~/dev/malebolge`:

- New: `src/project-context.ts` (sources, pick, cap, render),
  `src/runner/project-context.ts` (room reader, doctrine step),
  `src/grep.ts`, `src/truncate.ts`, `src/cwd.ts`, `src/xml.ts` (`escapeXml`
  moved from `skills.ts`).
- `src/runner/shell.ts`, `room.ts` (`ShellLimits`, `overflowed`).
- `src/runner/prepare.ts` (`readyRoom` returns the context), `run.ts`
  (`admit` passes it), `prompt.ts` (`composePrompt` input, working directory).
- `src/runner/tools.ts` (`grep` in `JobTools`); `src/runner/vocab.ts`
  (`context_degraded`).
- `src/daemon-main.ts`: read once, `project_context` + `cwd` sections, `grep`.
- `flake.nix`: `dev-tools` gains doctrine.
- `test/`, incl. `test/runner/tools.test.ts` (four tools → five);
  `docs/internals.md`.

`~/satan-corpus`: `prompts/patch-agent.md`, `prompts/interactive.txt`.

`~/dev/satan`: SPEC-004 revision; DEC-070..DEC-073; `flake.nix` (jail
probe).

## Risks, assumptions, open questions

- **pi-durable API churn** (experimental; malebolge pins 1.3.0).
- **A hostile context file** can mislead the model, never widen what
  collection accepts (DEC-073).
- **ASM-006 validated** (live probe): `rg` at `/etc/room/base/bin/rg` under
  `session`.
- **VH depends on SL-025's room targets being deployed** (its EX-4).

## Verification / closure intent

- VT: `grep` against a faux env (argv incl. `noIgnore`, `--json` across chunk
  boundaries, caps and line truncation, limit abort, no-match, rg error) and
  one conformance run over `localConnection()`; source discovery (names,
  symlinks, walk to git root, caps and marker, order); runner preparing reads
  through the shell (doctrine present/absent/missing binary →
  `context_degraded`; room down retried); `composePrompt` places context before
  an unchanged job block and policy resolution takes no context (DEC-073);
  daemon renders `project_context` and `cwd`.
- VT: `just check` in malebolge (lint, format, typecheck, tests).
- VH (live, with the user): one patch job on `doctrine` (base `edge`) that
  quotes a line from `.pi/APPEND_SYSTEM.md`, `AGENTS.md` and the doctrine boot,
  and runs one `grep` in the room. Entry: SL-025 room targets deployed.
  Fallback: a goad-walk job for `grep` alone.

## Summary

## Follow-Ups

- RFC-019 D1 vm mode (takes the shared env module).
- RFC-019 OQ-9 eval (uses this layer).
