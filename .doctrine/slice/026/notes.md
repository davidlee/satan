# Notes SL-026: malebolge coding layer: project context, cwd, ripgrep grep

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-19 · ready (plan 8 phases, none started) · 8c5bcb3

### Produced
- scope + research round done; scope reshaped on research (commits d911161, 8256d4a), then rewritten against design decisions (slice-026.md, uncommitted)
- RFC-019 D7 table corrected: pi-durable bash already has `timeout`
- minted: CHR-020 (related, independent); DEC-070, DEC-071, DEC-072, DEC-073 (accepted, shape SL-026); IDE-012 (room setup step, deferred); REV-008 (SPEC-004 draft, apply at reconcile)
- design.md locked (run dr-01a152b2 rev 44) after RV-033; selectors `.doctrine/spec/tech/004/*`, `flake.nix`
- plan.toml / plan.md: PHASE-01..08 (commits 83018c0, 3179933, 8c5bcb3); phase sheets materialised

### Learned
- mem.pattern.doctrine.cross-corpus-id-collision — qualify foreign ids (oubliette DEC-052 ≠ satan DEC-052)
- mem.pattern.satan.research-jail-snapshot — research jail sees no sibling repos; launch over a snapshot
- doctrine verify checks in design runs need `doctrine` on PATH (else "no result produced"); not yet a memory
- pi-env reports a missing argv binary as `spawn_error`, not exit 127 (design §4.3); candidate memory at harvest
- rg `--json` ignores `--max-columns` and exits 2 after matches on any file error (RV-033 F-2, F-7); candidate memory
- the oubliette room floor is `git bash coreutils-full which` — no `find` (design §4.2); candidate memory
- cross-repo VT test_file paths are absolute (SL-023 convention); verify-vt FAILs until files exist

### Open
- ASM-006 — validated (live probe), closed
- RV-033 F-1 (probe) answered: transcription onto PHASE-03 EX-3/VT-2 repaired after the raiser's check; raiser re-verify pending. F-2 verified.

## Design triage (2026-10-19, explore stage, run dr-01a152b2)

### Findings that reshape the open questions
- **The runner has no system prompt sections.** Its extensions are
  `[JobTools, jobGuard]` (`malebolge/src/runner/start.ts:147`); the corpus
  prompt + policy fragments + job block go in as the conversation's first
  *input message* (`run.ts:348-354`, `composePrompt`). Context composed into
  that message lands in the durable transcript: fixed for the job's life,
  survives restart, needs no job-row field.
- **Runner cwd is the clone root** (`/work/goad-walk`, has `.git`), so a walk
  that stops at the nearest git root reads one directory there.
- **`~/notes` has `.git` and no `AGENTS.md`/`CLAUDE.md`**: under the same walk
  rule the daemon finds nothing until CHR-020 moves its cwd; CHR-020 need not
  land first.
- **goad-walk has no `AGENTS.md`/`CLAUDE.md`**: the slice's VH needs one added
  to that repo (the user's) before the live job.
- **Context files may carry harness-specific syntax** (malebolge's own
  `AGENTS.md` is a Claude `@`-import stub); pi renders them verbatim, and so
  will we.
- **ASM-006 validated** (live probe; record body has the evidence).
- **pi-env FileSystem ops exist** (`readTextFile`, `listDir`), but a room loss
  is classified only at the Connection seam; `roomShell` already does that for
  `exec` (mem.fact.pi-env.type-survives-only-at-connection).

### Constraining governance
SPEC-004 §Components (pure composition), §Job contract ("the repo itself
authors no policy"), §Execution environment (tool list); REQ-030 (deadline is
the wall-clock authority); DEC-056 (no default prompt text in malebolge);
DEC-067 (read-once constant section); ADR-017 §4 (degrade, not fail);
POL-001 (cutover, not copy); SPEC-002 NF-004 (jail probes), NF-005 (notes
read-only).

### Risks
- pi-durable API churn (pinned 1.3.0).
- A context file in a repo is untrusted text in the job's input; the DEC
  bounds what it can mean, not what the model does with it.

## Review passes (design, 2026-10-19)

RV-033 concluded: adversarial lane, three rounds, 22 findings (ledger holds them).
A further pass would probe only what the ledger leaves to instruments: F-1
(preparing bounds against hostile room binaries and FIFOs) and F-2 (grep
host-side memory bound) are routed `probe`; their adversary and criterion are
on RV-033 and `/plan` must transcribe them onto phase VTs, where the probe
itself runs. No further prose pass is needed: every other finding is verified,
and the two user decisions (F-16 no clean, fail `dirty_clone`; F-17 limits on
all `preparing` execs) are integrated. Residual: an independent GPT design
review was not run (codex MCP failed to connect this session).

