---
name: satan-governance
description: SATAN governance + reference — philosophy, policy, file map, modes, tools, ops, gotchas
metadata:
  type: governance
  topic: satan
  status: canon
  updated_at: 2026-05-23
  verified_at: 2026-05-23
---

# SATAN — Scheduled Agent for Textual Attention and Notes

Living document. Covers both governing architecture and current
operational state. Update on every meaningful change.

Companion: `CHANGELOG.md` (dated, narrative log of what landed).

## One-sentence summary

SATAN is a local, Emacs-mediated, org-backed, harness-agnostic agent
runtime whose model-facing mind lives in `~/notes/satan`, whose
authority is constrained by a broker-enforced tool membrane, and whose
evolution should remain text-first, auditable, proposal-driven, and
deliberately narrow.

## Purpose

SATAN is a local, text-first agent runtime for personal orchestration.
Not a chatbot, not a general-purpose automation daemon, not an
autonomous shell with a personality. A constrained local system that
periodically reads selected personal context, reasons over it through a
model/harness, and produces bounded, inspectable effects through a
trusted broker.

SATAN exists to help maintain alignment between stated intentions,
daily behaviour, notes and memories, projects and obligations,
recurring patterns, and local tools/workflows.

Design priority: **safe, inspectable, evolvable agency** — not maximum
agency.

## Core thesis

SATAN's identity is not any particular model, harness, editor, or CLI.
It is defined by its durable local "DNA":

```text
ROM prompt
+ self-authored memory
+ permission model
+ jail/runtime constraints
+ tool/action protocol
+ invocation schedule
+ audit trail
```

Models are interchangeable. Harnesses are interchangeable. The broker
may evolve. The identity and governance rules should remain coherent
across those changes.

## Status

| Phase | Status | Notes |
|---|---|---|
| 1 — broker + JSONL + fake harness | ✅ | landed 2026-05-19 |
| 2A — real LLM harness (OpenRouter) | ✅ | landed 2026-05-19, smoke-tested live |
| 2B — `notify_send` tool | ✅ | landed 2026-05-19 |
| 2C — `hippocampus_write` tool | ✅ | landed 2026-05-19, raw `find-file` review; renamed from `memory.add_candidate` |
| 2D — `self-edit` mode | ✅ | landed 2026-05-19, SATAN-only scope |
| 2E — mind/mechanism split | ✅ | landed 2026-05-19, prompts + tool descs in `~/notes/satan/` |
| Wired into Sleipnir (`satan.nix`) | ✅ | timers `satan-morning` 09:00, `satan-motd` 07:00, `satan-tick` `OnUnitActiveSec=30min` |
| 3A — protocol reification | ✅ | landed 2026-05-19; `protocol.md` + fixtures + validators on both sides |
| Memory substrate v1 (12 steps) | ✅ | landed 2026-05-19→20; see [[satan-memory-handover]]. DR-116 follow-up (bough B1) landed 2026-05-21 |
| `docs_*` lazy lookup over chunked docs | ✅ | landed 2026-05-21 (`9bacace5`); SATAN now reads its own docs by chunk |
| `@satan` directive trigger (notes_at_satan_*) | ✅ | implementation landed; `tick-agent` mode active; design + plan in `docs/satan/at-satan/` |
| Patch agent Phase 3 (mechanism + content) | ✅ | landed pre-2026-05-21; mechanism per `patch/archive/handover-phase3-mechanism.md`; content + 5 open issues per `patch/handover.md`; runner pivot to standalone Go daemon (`~/dev/satan-patcher/`) noted but not decided |
| Perceptual loop v0 Phases 0–4 | ✅ | landed 2026-05-22; [[satan-perceptual-design]] §1.5 lists per-sub-phase commits |
| Perceptual loop v0 Phase 5 (outcome observer 5.0–5.8) | ✅ | landed 2026-05-22; observer.process runs in `--spawn` before percept-build; positive-only `auto_rule` traces |
| Perceptual loop v0 Phase 6 (cooldown floor render) | ✅ | landed 2026-05-23; read-side capsule annotation `[cooling-down (Nm remaining)]` |

`M-x satan-run RET morning` writes a SATAN-owned block into today's
daily note and a full audit bundle under `~/notes/satan/runs/<run-id>/`.
`motd` writes `~/notes/satan/motd.txt`. `self-edit` stages proposals
under `~/notes/satan/proposals/` — nothing auto-applies.

Tests: all ert green; ~640 satan ert-deftests across `satan/test/` plus
the python harness unittests + 1/1 integration ert. CHANGELOG records
per-phase test totals (e.g. memory substrate +119, observer +N, Phase 6
+4). Exact live counts: `rg -c '^\(ert-deftest' satan/test/*.el`.

## Quickstart

```sh
# Manual invocation (the morning timer also does this).
M-x satan-run RET morning
M-x satan-run RET motd
M-x satan-run RET self-edit          # SATAN audits its own source

# Review staged artifacts.
M-x satan-hippocampus                 # dired ~/notes/satan/hippocampus
find ~/notes/satan/proposals             # denote-named proposals

# Audit a finished run.
emacsclient --eval '(satan-audit-verify-run "/home/david/notes/satan/runs/<RUN-ID>/")'
```

The wrapper script `~/.emacs.d/satan/bin/satan-run <mode>` invokes
`emacsclient --eval` and is what the systemd units call.

## Architecture

Trust-and-data flow, broker/harness/model/tool/output/state layers:
[[satan-architecture]].

## Ownership: mind vs mechanism

**Invariant.** All model-facing behavioural text lives under
`~/notes/satan`. Dotfiles may define mechanisms, validators, handlers,
and capability checks, but must not be the canonical source for
prompts, tool descriptions, behavioural instructions, examples, or
model-facing policy.

```text
Dotfiles contain mechanism.
~/notes/satan contains mind.
```

| Concern | Owner |
|---|---|
| ROM/system prompt, mode prompts | `~/notes/satan/prompts/<mode>.txt` |
| shared system scaffold | `~/notes/satan/system/scaffold.txt` |
| bundle-section headers (`# Now`, `# Today (raw)`, `# Source files`, `# Recent SATAN runs`) | `~/notes/satan/system/framing.txt` |
| per-tool description (model-facing) | `~/notes/satan/tools/<tool-name>.md` |
| `satan_final` description (synthetic terminal tool) | `~/notes/satan/tools/satan_final.md` |
| examples / few-shot snippets, style instructions, hippocampus policy | `~/notes/satan/` |
| hippocampus entries, staged proposals | `~/notes/satan/{hippocampus,proposals}/` |
| tool name / risk / schema / capability / handler | elisp tool-spec (`satan-tools-*.el`) |
| mode allowlist / harness / jail / timeouts / budgets | elisp mode-spec (`satan-mode.el`) |
| JSONL protocol, validation, dispatch, audit, jailing | elisp (`satan-*.el`) |

The broker assembles `manifest.json` by joining the two halves: each
allowed tool's full OpenAI-tools JSON Schema is built from the elisp
schema (mechanism) plus the notes-owned description (mind). The harness
consumes `manifest["tools"]` verbatim — it holds no canonical
descriptions of its own. Missing notes-side files signal at run-start
rather than degrading silently.

Rule of thumb: if changing the text could change what the model
chooses to do, it belongs in `~/notes/satan`.

## Source of truth

- **Canonical personal substrate**: org/denote notes. SATAN may read
  broadly through selected context assemblers, but writes only to
  explicit owned regions or staged artifacts.
- **Derived operational layer**: `bough` may cache, index, relate,
  enrich, or project org/denote state. Treat as reconstructable unless
  explicitly promoted. Operationally useful, not canonical.
- **SATAN-owned state**: lives under `~/notes/satan` — hippocampus,
  proposals, run summaries, prompt material, owned output surfaces.

## Read broadly, write narrowly

Safety depends on asymmetric access. SATAN may read selected personal
context broadly, subject to mode and privacy policy. It may write only
through narrow broker-controlled surfaces: SATAN-owned org blocks,
SATAN hippocampus files, SATAN proposal files, SATAN MOTD/status
files, local notifications, other explicitly registered low-risk
surfaces. All other effects should be staged as proposals.

## Proposal-first agency

Prefer proposals over direct mutation. Direct writes are appropriate
only when:

- target surface is owned by SATAN
- operation is low risk
- mode permits auto-application
- action validates against the tool/action contract
- audit log records it

Higher-risk actions stage. Examples requiring proposal or explicit
review: self-editing ROM/prompt/tool behaviour; expanding write scope;
changing capability policy; destructive edits; outbound communications
beyond local notification; code changes; bough structural mutation;
calendar/email/chat actions; loading generated elisp.

Central pattern:

```text
observe → infer → propose → validate → apply or stage → audit
```

## Self-modification governance

Self-editing is allowed but constrained. SATAN may propose changes to
prompts, tool descriptions, hippocampus policy, style, mode behaviour,
future tools, local documentation.

SATAN must not silently apply changes to: ROM prompt, tool
implementations, permission model, jail profile, self-edit scope,
executable code.

Self-edit proposals include: target, rationale, expected effect, risk,
rollback path where applicable, diff or concrete replacement text.
Generated code is never auto-loaded merely because SATAN wrote it.

## Harness and model agnosticism

Core protocol stays stable and simple enough that multiple adapters
can implement it. The broker should not depend on one provider's
tool-call format, one model's JSON behaviour, one CLI's terminal
transcript conventions, or one frontend's prompt assembly model.

Preferred boundary:

```text
broker writes manifest/context/prompt bundle
harness reads bundle
harness emits JSONL protocol messages
broker validates and responds
```

Harness-specific conventions belong in adapters, not in SATAN's
conceptual core.

## Protocol governance

Boring on purpose: newline-delimited JSON; explicit message types; no
transcript scraping; no free-text command parsing; structured tool
calls, results, finals; auditable transcript; strict validation at the
broker boundary.

The canonical message spec is [protocol.md](protocol.md). Shared exemplars
live at `~/.emacs.d/satan/protocol/fixtures.json` and drive validator tests on both
sides — the elisp validator (`satan-protocol-validate` in
`satan-protocol.el`) and the python validator (`harness/protocol.py`)
must remain in lockstep. Adding a message
type or required field means: edit the spec, add fixtures, update both
validators. Tests fail loudly otherwise.

The protocol is a membrane between untrusted reasoning and trusted
local action. Optimise for: debuggability, testability, portability,
crash recovery, explicit failure states, replayable audit logs.

## Permission governance

Capability-based. A mode grants capabilities; a tool requires
capabilities; an action is allowed only if the mode, tool, risk
policy, and validator all agree. Avoid vague categories like "trusted
model" or "safe prompt." Use explicit capabilities: read context,
write owned daily block, write MOTD, stage proposal, write hippocampus
entry, send local notification, query bough, propose self-edit. The
model is never the authority on whether an action is safe.

## Hippocampus governance

SATAN's memory is called the hippocampus and lives at
`~/notes/satan/hippocampus/` as one denote-named org file per entry.
SATAN curates the hippocampus freely — writes auto-apply, no candidate
/ confirmed ceremony. The user reviews when they want to via
`satan-hippocampus`; ad-hoc deletes / edits are expected.

Each entry carries provenance (`:RUN_ID:`, `:MODE:`, file mtime).
A future loop-detection / salience pass can use that to weigh
SATAN-authored entries against user-confirmed ones.

Important classes of entry: preference, behavioural pattern, standing
constraint, project fact, operating principle, rejected inference,
stale/expired belief. Hippocampus helps SATAN behave consistently
without becoming an opaque personality accretion.

## Outbound communication governance

Start local and narrow. Permitted low-risk surfaces: desktop
notification, MOTD/status text, SATAN-owned daily-note block, proposal
file, hippocampus file. Higher-impact outbound (email, chat,
calendar mutation, issue/PR comments, public posting, external API
mutation) requires explicit review. SATAN does not become socially or
operationally active by accident.

## Jail and runtime governance

Least privilege. The jail exposes only: prepared input bundle; allowed
scratch/output paths; necessary model-provider network access if
applicable; controlled environment variables. It does not expose:
arbitrary home directory, secrets, SSH keys, browser profile, mail,
full note tree with write access, database credentials, unrestricted
shell authority. If the model needs access to something sensitive, it
requests a broker tool.

## Audit governance

Every run is explainable after the fact. A run answers:

- Which mode ran?
- What prompt material was used?
- What hippocampus was visible?
- What context was visible?
- Which harness and model executed?
- Which tools were available?
- Which tool calls were requested?
- Which tool calls were allowed or denied?
- What final output was produced?
- Which actions were applied, staged, rejected, or failed?
- What errors occurred?

Auditability is a core feature, not debug scaffolding.

## Evolution principles

When extending SATAN, prefer changes that preserve or strengthen these
properties:

1. **Local first** — durable state remains local and inspectable.
2. **Text first** — behaviour and hippocampus visible as text where practical.
3. **Broker enforced** — enforcement in the trusted broker, not in prompt wording.
4. **Harness agnostic** — new runtimes plug in behind the protocol.
5. **Proposal first** — risky actions are staged before applied.
6. **Read broad, write narrow** — write surfaces stay explicit and small.
7. **Self-edit cautiously** — reflexive behaviour produces reviewable proposals, not silent mutation.
8. **No ambient authority** — models/harnesses never inherit broad host access by default.
9. **Make drift visible** — behaviour/prompt/hippocampus/permission changes auditable.
10. **Small useful loops beat grand autonomy** — a good daily block beats a half-trusted general agent.

## Architectural smells

Warning signs (not always forbidden, but require explicit
justification):

- prompts or tool descriptions hardcoded in dotfiles
- harness-specific logic leaking into the broker
- model-visible behaviour changing without notes-repo diffs
- new tools with broad shell/file/database access
- terminal transcript scraping as protocol
- generated code auto-loaded without review
- self-edit scope expanding before review UX matures
- hippocampus accumulating without curation / forgetting
- noisy notifications with low utility
- bough becoming canonical by accident
- audit artifacts missing or incomplete
- model-declared risk accepted as authoritative
- convenience bypasses around capability checks

## File map

### Emacs (`~/.emacs.d/satan/`)

| File | Role |
|---|---|
| `satan.el` | Aggregator + `satan-run`. |
| `satan-mode.el` | Mode registry; modes `morning`, `motd`, `self-edit-mech`, `self-edit-mind`. |
| `satan-tick.el` | Tick mode family: weighted picker, quiet-hours gate, `satan-tick-register` helper, default `tick-pulse`, `satan-tick`. |
| `satan-tools.el` | Tool registry, dispatch, schema validator, JSON-Schema builder (from notes descriptions). |
| `satan-tools-org.el` | Handlers: `org_read_context`, `org_update_owned_block`, `proposal_stage`. |
| `satan-tools-notify.el` | `notify_send` (D-Bus). |
| `satan-tools-hippocampus.el` | `hippocampus_write`; `satan-hippocampus`. Emits an `auto_rule` memory observation when called from a `memory-write` mode (cross-ref hook, [[satan-memory-design]] §10.7). |
| `satan-tools-inbox.el` | `inbox_append`; `satan-inbox`; `satan-inbox-unread-count`. |
| `satan-tools-agenda.el` | `agenda_read` (gcalcli → text); timeout-wrapped; calendar id from `$WORK_EMAIL`. |
| `satan-tools-activity.el` | `activity_read` (panopticon's `~/.local/state/behaviour/` → histogram or focus segments); read-only. |
| `satan-tools-bough.el` | `bough_read` (shell-out to `bough --json` for `node`, `recent_changes`, `active`, `day`, `week`, `project_subtree`); only path SATAN uses to read bough. |
| `satan-tools-memory.el` | `memory_mark`, `memory_resonate`, `memory_show_trace` — LLM-facing tools over the memory substrate. |
| `satan-tools-docs.el` | `docs_list`, `docs_search`, `docs_read` — lazy lookup over the frontmatter-stamped chunks under `docs/satan/` + `docs/emacs/`. |
| `satan-memory.el` | Substrate aggregator + `satan-memory-{resonate,show,status}` interactive surface. |
| `satan-memory-grammar.el` | Closed-world enums, alias seed, default weights for grammar v1 (mirrored in `memory/migrations/0002_grammar_v1.sql`). |
| `satan-memory-canon.el` | Pure canonicalizer + rule registry; emits handles + per-handle source. Purity grep-lint enforced. |
| `satan-memory-evidence.el` | Impure evidence-window assembly (panopticon + `bough_read` + git/fs) per [[satan-memory-design]] §4; deterministic truncation. Also the §S6 git-activity probe (`--git-commits-status`): reads `segments/git-<day>.jsonl`, bursty-freshness (never stale), adds `:git_commits` + `:git` sensor_status. |
| `satan-memory-store.el` | `mark` / `resonate` / `show` against `satan_memory` via `psql` subprocess. |
| `satan-memory-migrate.el` | Forward-only migration runner; `satan-memory-renormalize` (§7 grammar-bump replay) + `-status`. |
| `satan-percept.el` | Perceptual-loop §S1: percept builder, persist (`percept.json`), capsule render. Phase 1. |
| `satan-resonance.el` | Perceptual-loop §S2: cue derivation + sensor-observed-handle gate + capsule resonance block. Phase 2. |
| `satan-motive.el` | Perceptual-loop §S3 + §S4 + Phase 6: motives.org parser, atomic writer, footer rewriter (`satan-motive-touch-footer`), capsule render with cooldown annotation (`[cooling-down (Nm remaining)]`). |
| `satan-observer.el` | Perceptual-loop §S5: 24h transcript scan, window-mature gate, baseline-vs-after diff, positive predicate classifier, multi-motive resolver, verdict persistence; broker entry `satan-observer-process RUN-CTX`. Phase 5. |
| `satan-sensor-alerts.el` | Perceptual-loop §S6: freshness check dispatcher, per-cause cooldown, quiet-hours suppression, dispatch through `notify_send` tool path, records into `actions.json.pre_spawn`. Phase 4. Renders the `git` sensor (no alert cause — commits are bursty, a quiet feed must not page). |
| `satan-tank.el` | Shared mutable run-context "tank" plist accessors (run_id, time_now, evidence, percept, sensor_status, pre_spawn, motive, observer summary). |
| `satan-tools-motive.el` | `motive_read` / `motive_replace` handlers + bound validators (≤3 active, ≤10 ruminations, `:cue:` syntax + sensor-observed-handle requirement, rejects `:ceiling:`). |
| `satan-tools-atsatan.el` | `notes_at_satan_scan` (read; `rg --json` over `~/notes/` excluding `satan/`, enriched with headline + context) + `notes_at_satan_done` (claim by replacing `@satan` with `@satan-was-here` + quoted run-id block). Registers `tick-agent` via `satan-tick-register`. |
| `satan-tools-notes.el` | `notes_recent` (fd-based recently-modified files under `~/notes/`, excludes `satan/`). |
| `satan-tools-sway.el` | `sway_border_set` / `sway_border_reset` (visual ephemeral effect). |
| `satan-tools-vcs.el` | `vcs_log` (read; `git -C REPO log` for an abs path or a bare slug resolved against `~/dev`/`~/.emacs.d`/`~/flakes`); pwd-independent. The on-demand drill-in for the git-activity sensor (§S6); the `project:<slug>` handle tells the model *which* repo to ask about. |
| `satan-patch.el` | Patch-agent aggregator + `satan-patch-*` interactive surface. |
| `satan-patch-store.el` | `satan_patch.patch_jobs` PG store; INSERT fires `pg_notify` for queued rows. |
| `satan-patch-worktree.el` | Worktree allocator + cleanup: `git worktree add <runs-dir>/<job-id>` against current HEAD, branch `satan/patch/<job-id>`. |
| `satan-patch-adapter.el` | Adapter protocol (`Provider`-like); pre-resolves API keys via `my/op-read-env`. |
| `satan-patch-adapter-pi.el` | `pi`-CLI adapter; stdin EOF close, `--system-prompt` (not `-file`), stderr persisted to sidecar log. |
| `satan-patch-runner.el` | Background runner: claims queued jobs, spawns adapter in jail, persists transcript + result; `satan-patch-runner-enabled` defcustom can hand queue off to standalone Go daemon at `~/dev/satan-patcher/`. |
| `satan-patch-listener.el` | `pg_notify` LISTEN bridge waking the runner without polling. |
| `satan-patch-classify.el` | `@satan` directive → patch-shape classifier (used by `tick-agent` + `self-edit-*` to route patch-shaped work via `patch_job_create`). |
| `satan-patch-inbox.el` | Inbox handoff: writes `~/notes/satan/inbox.org` entry on patch completion. |
| `satan-patch-prompt.el` | Patch-agent system prompt assembler (per-job). |
| `satan-tools-patch.el` | LLM-facing tools: `patch_job_create`, `patch_job_status`, `patch_job_result`, `patch_job_cancel`, `patch_job_cleanup`. See `docs/satan/patch/{brief,plan,handover}.md`. |
| `memory/migrations/0001_init.sql` | Substrate schema (§6.2). |
| `memory/migrations/0002_grammar_v1.sql` | v1 grammar seed (aliases + namespace weights). |
| `memory/migrations/0003_memory_functions.sql` | `memory_mark_trace`, `memory_resonate`, `memory_show_trace`, `handle_weight_for`. |
| `memory/migrations/0004_grammar_v2_fixture.sql` | Operator-applied fixture bump exercising the renormalize CLI (adds `planning -> phase:orientation`). |
| `memory/migrations/0005_patch_jobs.sql` | Patch-agent schema: `satan_patch.patch_jobs` table + index. |
| `docs/satan/memory/design.md` | Substrate design (§§0–11). |
| `satan-context.el` | Per-mode bundle assembly; strict `--read-required`; scaffold assembly; recent-runs block via `:recent-runs N` mode-spec key. |
| `satan-output.el` | Mode output handlers (`morning`, `motd`, `tick`, `self-edit`; the last is shared by both `self-edit-{mech,mind}` lanes). |
| `satan-block.el` | Owned-block find/replace. |
| `satan-jsonl.el` | Line-buffered filter + writer + `satan-jsonl-prepare`. |
| `satan-protocol.el` | Validator for the JSONL membrane; fixture loader; constants. |
| `docs/satan/protocol.md` | Canonical message-type spec. |
| `protocol/fixtures.json` | Shared valid/invalid exemplars consumed by both ert and python tests. |
| `satan-audit.el` | Append-only artifact writer + 6-predicate verifier. |
| `satan-budget.el` | Daily token ceiling: enumerates today's `runs/`, sums per-run `usage.tokens_total`, gates the broker pre-spawn. |
| `satan-broker.el` | `make-process` driver: sentinel, timeout, direnv, op:// resolution, env pass; `--build-manifest`. |
| `test/satan-memory-{migrate,grammar,canon,evidence,store,renormalize}-test.el` | Memory substrate ert against `satan_memory_test`; canon also enforces purity + §9.10 bough isolation lint. |
| `test/satan-tools-{bough,memory,hippocampus,atsatan,docs,motive,patch}-test.el` | Tool-handler ert; hippocampus covers the cross-ref hook. |
| `test/satan-{percept,resonance,motive,observer,sensor-alerts,tank,context}-test.el` | Perceptual-loop module ert (Phases 1–6). |
| `test/satan-patch-{store,worktree,adapter,runner,listener,classify,inbox}-test.el` | Patch-agent module ert. |
| `bin/satan-run` | Shell wrapper (`emacsclient --eval`). |
| `bin/satan-run-tick` | Tick wrapper; calls `(satan-tick)` which picks + quiet-checks. |
| `harness/__main__.py` | Entrypoint: sys.path bootstrap + `main`. |
| `harness/protocol.py` | JSONL validator + `emit*` / `read_tool_result`. |
| `harness/bundle.py` | `load_bundle` / `load_manifest` / `build_system_prompt` / `build_tools`. |
| `harness/runloop.py` | Turn loop + budget guard + tool-call dispatch. |
| `harness/providers/{base,openrouter}.py`, `__init__.py` | `Provider` ABC, OpenAI-v1 adapter, `build_provider` registry. |
| `harness/test_gptel_harness.py` | stdlib unittest cases (no network). |
| `test/satan-MODULE-test.el` | Phase-3 unit ert, split per source module (T6). |
| `test/satan-integration-test.el` | 1 e2e ert (skips unless `SATAN_TEST_JAIL_BIN` set). |

### Wiring

- `~/.emacs.d/init.el` — `(require 'satan)` after `dl-denote-journal`.
- `~/.emacs.d/core/dl-path.el` — `"satan"` in `my/lisp-dirs`.
- `~/flakes/modules/home/emacs.nix` — `"satan"` in `configDirs`.
- `~/.emacs.d/flake.nix` — `satanFakeHarness`, `satanGptelHarness`,
  `satanJailOptions`, `satanGptelJailOptions`,
  `satan-jailed-fake-harness`, `satan-jailed-gptel-harness`. Devshell
  exposes both binaries on PATH; broker's `direnv-env` plumbing picks
  them up at spawn.
- `~/flakes/modules/home/satan.nix` — imported by Sleipnir. Units
  `satan-morning.{service,timer}` (09:00),
  `satan-motd.{service,timer}` (07:00), and
  `satan-tick.{service,timer}` (`OnBootSec=5min`,
  `OnUnitActiveSec=30min`, `RandomizedDelaySec=5min`).

### Notes tree (canonical model-facing surface)

```
~/notes/satan/
  prompts/                           # mode prompts
    morning.txt
    motd.txt
    self-edit-mech.txt               # SATAN's mechanism scope (~/.emacs.d/satan/)
    self-edit-mind.txt               # SATAN's mind scope (notes prompts+system+tools)
    tick/                            # one file per registered tick-* mode
      pulse.txt
  system/
    scaffold.txt                     # shared system-prompt scaffold (termination instruction)
  tools/                             # one markdown file per tool — model-facing description
    org_read_context.md
    org_update_owned_block.md
    proposal_stage.md
    notify_send.md
    hippocampus_write.md
    inbox_append.md
    bough_read.md
    memory_mark.md
    memory_resonate.md
    memory_show_trace.md
    docs_list.md
    docs_search.md
    docs_read.md
    satan_final.md                   # synthetic harness-side tool, canonical desc here
  motd.txt
  inbox.org                          # append-only headlines, tagged :unread:satan:
  hippocampus/                       # <ID>--<slug>__satan_hippocampus.org; rw inside jail at /satan/hippocampus
  proposals/                         # <ID>--<slug>__satan_proposal.org
  runs/<run-id>/                     # YYYYMMDDTHHMMSS-<mode>-<rand6>
    bundle.json                      # frozen input (incl. assembled :prompt)
    manifest.json                    # mode + capabilities + harness + tools[] (full JSON Schemas)
    transcript.jsonl                 # one JSON object per line
    final.json                       # validated final or {status: invalid}
    actions.json                     # {applied, staged, rejected, failed}
    stdout.log
    stderr.log
    status                           # done | failed | timed-out | invalid-protocol | budget-exceeded
```

## Modes

| Mode | Tools | Auto-apply | Budget tokens / tool-calls / wall |
|---|---|---|---|
| `morning` | `org_read_context`, `org_update_owned_block`, `proposal_stage`, `notify_send`, `hippocampus_write`, `inbox_append`, `agenda_read`, `activity_read`, `sway_border_set`, `sway_border_reset`, `bough_read`, `memory_mark`, `memory_resonate`, `memory_show_trace`, `docs_list`, `docs_search`, `docs_read` | `owned` | 20000 / 8 / 90s |
| `motd` | `org_read_context`, `notify_send`, `inbox_append`, `agenda_read`, `activity_read`, `sway_border_set`, `sway_border_reset`, `bough_read`, `memory_mark`, `memory_resonate`, `memory_show_trace` | `owned` (motd surface owned by output handler; written from `satan_final.summary`) | 10000 / 4 / 45s |
| `tick-pulse` | `org_read_context`, `notify_send`, `inbox_append`, `sway_border_set`, `sway_border_reset`, `bough_read`, `memory_mark`, `memory_resonate`, `memory_show_trace`, `motive_read`, `motive_replace`, `patch_job_create`, `patch_job_status`, `patch_job_cancel` | `owned` (only `inbox_append`; motives written via `motive_replace` model-side, footer via observer broker-side) | 3000 / 4 / 30s |
| `tick-agent` | as `tick-pulse` plus `notes_at_satan_scan`, `notes_at_satan_done`, `notes_recent` | as `tick-pulse` (claims directives via `notes_at_satan_done`) | 3000 / 4 / 30s |
| `self-edit-mech` | `proposal_stage`, `sway_border_set`, `sway_border_reset`, `bough_read`, `memory_resonate`, `memory_show_trace`, `docs_list`, `docs_search`, `docs_read`, `patch_job_create` | `none` | 50000 / 20 / 180s |
| `self-edit-mind` | `proposal_stage`, `sway_border_set`, `sway_border_reset`, `bough_read`, `memory_resonate`, `memory_show_trace`, `docs_list`, `docs_search`, `docs_read` | `none` | 50000 / 20 / 180s |

Tick-mode pool (`satan-tick-pool`): `tick-pulse` weight 5,
`tick-agent` weight 3. `satan-tick-register SHORT-NAME` registers
each — `pulse` from `satan-tick.el`, `agent` from
`satan-tools-atsatan.el`. Each rendered tick capsule includes the
perceptual layer's percept / resonance / motive / sensor blocks
(broker-built; see [[satan-perceptual-design]]).

Capabilities: `morning` and `motd` (and `tick-*`) carry `memory-write` so
the memory_mark + hippocampus cross-ref hook are admitted; `self-edit-*`
lanes are read-only against the substrate.

All three use OpenRouter with `anthropic/claude-haiku-4.5` by default.
Override per-mode in `satan-mode.el`: `:provider`, `:model`,
`:budget-tokens`.

## Tools

| Name | Risk | Auth | Effect |
|---|---|---|---|
| `org_read_context` | read | — | Read today/week/inbox text. |
| `org_update_owned_block` | low | capability `write-daily` | Replace owned `#+begin_satan` block (target=today). |
| `proposal_stage` | low | capability `stage-proposal` | Write a denote proposal file. |
| `notify_send` | low | capability `notify` | D-Bus desktop notification. |
| `hippocampus_write` | low | capability `hippocampus-write` | Append a denote hippocampus entry (SATAN-owned, auto-applied). |
| `inbox_append` | low | capability `inbox-write` | Append a headline to `~/notes/satan/inbox.org` (SATAN-owned, auto-applied; preferred over `notify_send` for non-urgent messages). |
| `agenda_read` | read | — | Fetch the work calendar via `gcalcli`. Calendar id read from `$WORK_EMAIL`; wrapped in `timeout(1)` so a stalled gcalcli can't freeze the broker. |
| `activity_read` | read | — | Read panopticon's behaviour state from `~/.local/state/behaviour/`. `scope="today"` returns the daily histogram; `scope="recent_focus"` / `recent_browser` return the last N focus / browser segments; `scope="current"` returns the live focused-window snapshot (`app_id`, `workspace`, `output`, `title`, `pid`). PII redaction is handled by the producer (firefox URLs stripped to origin, incognito dropped). The `current` scope intentionally passes `title` through — see open thread "current-scope title leak". |
| `bough_read` | read | — | Shell-out wrapper around `bough --json` — only path SATAN uses to read bough.  Scopes: `node`, `recent_changes`, `active`, `day`, `week`, `project_subtree`. |
| `memory_mark` | low | capability `memory-write` | Persist an `observation` trace into `satan_memory`. The broker canonicalizes evidence deterministically; the LLM supplies typed hints (no raw handles).  Stamped `trace_origin = llm_mark`. |
| `memory_resonate` | read | — | Inverted-index lookup over `trace_handles`; returns matches scored by `weight * trace.strength`.  No state mutation in v1. |
| `memory_show_trace` | read | — | Round-trip a trace by id (handles, sources, links). |
| `docs_list` | read | — | List every chunk under `docs/satan/` + `docs/emacs/` as `{name, description, path, type, topic, status}` — no bodies. |
| `docs_search` | read | — | Filter doc chunks by frontmatter (`topic`/`type`/`status`) and/or a literal case-insensitive `query` substring against the body. Returns the skinny entry shape; pair with `docs_read`. |
| `docs_read` | read | — | Full body of one chunk by `name` slug. |
| `motive_read` | read | — | Whole `~/notes/satan/motives.org` parsed: active motives + prose + `:cue:` + footer fields; ruminations. Capsule already includes motive block, so motive_read mostly serves explicit lookups + observer correlation context. |
| `motive_replace` | low | capability `motive-write` | Atomic full-file motive replace; broker validates ≤3 active, ≤10 ruminations, every active motive's `:cue:` matches the canon handle regex AND includes ≥1 sensor-observed handle, rejects `:ceiling:`. Broker preserves `:worked_count:` + `:last_intervention_at:`. |
| `notes_at_satan_scan` | read | — | `rg --json --fixed-strings @satan` over `~/notes/`, excluding `satan/**`. Returns each unclaimed directive with headline + ±N lines + stable session id. Only path to user-authored directives. |
| `notes_at_satan_done` | low | capability `write-notes` | Claim a directive by replacing `@satan` with `@satan-was-here` + a quoted run-id + optional comment block. Persistent and grep-able; excluded from future scans. |
| `notes_recent` | read | — | `fd --changed-after N hours` over `~/notes/` (excludes `satan/`); newest-first, capped at 200, denote-style title/tag parsed. |
| `patch_job_create` | medium | capability `patch-job-create` | Enqueue a patch job: writes `satan_patch.patch_jobs` row, fires `pg_notify`, runner picks up + allocates `git worktree add` + branch `satan/patch/<job-id>` + spawns adapter in jail. See `docs/satan/patch/{brief,plan,handover}.md`. |
| `patch_job_status` | read | — | Read job state from `satan_patch.patch_jobs` (queued/claimed/preparing_worktree/running/needs_review/failed/cancelled + 3 optional). |
| `patch_job_result` | read | — | Read job result JSON when terminal; includes branch ref user can cherry-pick. |
| `patch_job_cancel` | medium | capability `patch-job-cancel` | Cancel a job; may not kill an already-running adapter process (open issue per `patch/handover.md`). |
| `patch_job_cleanup` | medium | capability `patch-job-cleanup` | Remove a job's worktree + branch after user has acted on its result. |

The python harness intercepts a synthetic `satan_final(summary,
actions[])` tool call as the terminal signal and emits the broker's
`final` record. Plain-content responses with no tool calls are coerced
into `final` with `reason=no_tool_calls`. Budget exhaustion: harness
self-terminates with `reason=budget_tokens`.

## Operations

```sh
# Build the jailed harnesses.
nix build .#satan-jailed-fake-harness  --no-link --print-out-paths
nix build .#satan-jailed-gptel-harness --no-link --print-out-paths

# Standalone protocol smoke (no Emacs) — fake harness.
JAIL=$(nix build .#satan-jailed-fake-harness --no-link --print-out-paths)/bin/jailed-satan-fake-harness
mkdir -p /tmp/satan-smoke && SATAN_RUN_ID=smoke SATAN_RUN_DIR=/tmp/satan-smoke \
  "$JAIL" <<< '{"type":"tool_result","id":"c1","ok":true,"result":{"content":""}}'

# Unit ert (per-module — load any test file in satan/test/satan-*-test.el).
emacs --batch -L core -L lisp -L org -L satan -L satan/test \
  -l satan/test/satan-broker-test.el -f ert-run-tests-batch-and-exit

# Integration ert (real bwrap jail, fake harness).
JAIL=$(nix build .#satan-jailed-fake-harness --no-link --print-out-paths)/bin/jailed-satan-fake-harness
SATAN_TEST_JAIL_BIN=$JAIL emacs --batch -L core -L lisp -L org -L satan -L satan/test \
  -l satan/test/satan-integration-test.el -f ert-run-tests-batch-and-exit

# Python harness unit tests.
cd ~/.emacs.d/satan/harness && python -m unittest test_gptel_harness -v

# Audit a real run.
emacsclient --eval '(satan-audit-verify-run "/home/david/notes/satan/runs/<RUN-ID>/")'

# Inspect timer state.
systemctl --user list-timers satan-*
journalctl --user -u satan-morning.service --since today
```

## Conventions / gotchas

### Bundle `:now` block

Every context-fn includes a `:now` plist via `satan-context-now`:
`iso_date`, `weekday`, `iso_week`, `time`, `tz_offset`, `tz_name`.
The broker renders this as a fixed `# Now` section between the
assembled prompt and any `today_text` / source-file sections (see
`satan-context--render-prompt` and `~/notes/satan/system/framing.txt`),
so the model always sees the same date/time/tz framing regardless of
mode. Single source of truth — never set `:date`/`:time` separately.

### Bundle `:recent_runs` block (tick modes)

A mode-spec carrying `:recent-runs N` opts into a `# Recent SATAN runs`
block listing the N most recent runs newest-first, regardless of mode
(cross-mode visibility — a recent `self-edit-*` or `morning` matters
to the next tick). Each entry: `[YYYY-MM-DD HH:MM] mode[(FAILED)]:
summary` (summary clipped to 280 chars, replaced with ellipsis when
truncated; omitted on FAILED runs without a `final.json`), plus a
`tools: name×N, …` tally line from `transcript.jsonl` (excludes
`satan_final`).

`satan-tick-register` defaults to `:recent-runs 5`, so both
`tick-pulse` and `tick-agent` carry the block. Other modes leave
the key unset and see no change. The block is silently omitted
when `satan-runs-dir` is missing or empty — same convention as
the other render-* helpers. Helpers live in `satan-context.el`
(`--list-recent-runs`, `--summarize-run`, `--tally-tool-calls`,
`--render-recent-runs`).

Rationale: tick modes fire roughly every 30 minutes and were
otherwise amnesic between invocations — prone to looping on the
same hypothesis or re-issuing the same `inbox_append`. `memory_resonate`
answers a different question ("similar moment?"); this block
answers "what did I, SATAN, last try?".

### Owned-block syntax

Custom block, not a dynamic-block, not a drawer:

```org
#+begin_satan :block satan :owner SATAN :updated [2026-05-19 Tue 07:30]
…body…
#+end_satan
```

Inert to org's dblock updater; `satan-block-replace` is idempotent.

### `json-serialize` arrays

Elisp lists become objects unless coerced to vectors.
`satan-jsonl-prepare` walks payloads: plists (car keyword) preserved;
non-plist lists → vectors; recurses. Applied at every JSON write
boundary (audit, outbound send). **Never call `json-serialize` directly
on a SATAN payload.**

### Failed-action shape

Plist `(:action ACTION :reason MSG)`, never the improper cons
`(ACTION . MSG)` — `json-serialize` rejects improper lists.

### Run-id

`format-time-string "%Y%m%dT%H%M%S" + "-" + mode + "-" + 6-hex-random`.
The `YYYYMMDDT` prefix is load-bearing: `satan-budget` uses it to
enumerate today's runs without parsing manifests.

### Self-edit lanes (mech vs mind)

Self-editing is split into two proposal-only lanes that share governance
defaults (50000-token budget, 20 tool calls, 180-second timeout,
`proposal_stage` only, `auto-apply none`) but read different roots:

| Mode | Source roots | Stamped `:MODE:` |
|---|---|---|
| `self-edit-mech` | `satan-self-edit-mech-roots` (default `~/.emacs.d/satan/`) | `self-edit-mech` |
| `self-edit-mind` | `satan-self-edit-mind-roots` (default `~/notes/satan/{prompts,system,tools}/`) | `self-edit-mind` |

Both lanes write proposals to `~/notes/satan/proposals/`; the
`:MODE:` property in each denote file distinguishes them. Mode specs
reference defcustoms via `:source-roots-var` so the user can recustomize
roots without redefining modes. The shared context-fn
`satan-context-self-edit` reads either `:source-roots` (direct) or
`:source-roots-var` (indirect) from the mode spec; sources are
abbreviated paths (`~/notes/...`, `~/.emacs.d/...`).

### Tick mode family

`tick-*` modes are short, frequent, lightly-budgeted runs fired every
~30 minutes by `satan-tick.timer`. The wrapper `bin/satan-run-tick`
calls `satan-tick`, which:

1. Returns early if `satan-tick-quiet-p` is non-nil. Default
   quiet window is 22:00–07:00 inclusive of 22 / exclusive of 07,
   wraparound supported. Set `satan-tick-quiet-hours` to nil to
   disable.
2. Samples a mode name from `satan-tick-pool` (defcustom alist of
   `(MODE-NAME . WEIGHT)`; default `(("tick-pulse" . 1))`).
3. Spawns the chosen mode via `satan-run`, which still passes
   through the daily-token-ceiling gate.

Each tick mode is registered via `satan-tick-register SHORT-NAME
&rest OVERRIDES`. The helper applies the standard defaults
(`org_read_context` + `notify_send` + `inbox_append` tool surface,
`(notify inbox-write)` capabilities, 3000-token / 4-call / 30-second
budget, `satan-context-tick` + `satan-output/tick`,
`anthropic/claude-haiku-4.5`). Prompts live at
`~/notes/satan/prompts/tick/<short-name>.txt`. Add a tick by writing a
prompt file and calling `(satan-tick-register "name")` from the
config.

### Daily token ceiling

`satan-budget-daily-tokens` (default 400000) caps total tokens spent
under `satan-runs-dir` per local day. Pre-spawn, the broker sums
each today-prefixed run's max `usage.tokens_total` log event. If the
ceiling is met, the broker writes a slim audit bundle for the new
run-id with `status=budget-exceeded`, a synthetic `final.json` carrying
`reason=budget_daily_tokens`, and skips the child entirely. Set to nil
to disable. Status `budget-exceeded` is a valid terminal — the audit
verifier accepts it.

### direnv-driven exec-path

`satan-direnv-dir` (default `user-emacs-directory`) is resolved via
`envrc--export` at spawn time and merged into `process-environment`.
Means the jailed binary lives in the `.emacs.d` devshell; no global
`home.packages` install.

### Jail env

`SATAN_RUN_ID`, `SATAN_PROVIDER`, `SATAN_MODEL`, `SATAN_BUDGET_TOKENS`
forwarded via `try-fwd-env`. `SATAN_RUN_DIR`, `SATAN_HIPPOCAMPUS` set
to fixed paths inside the jail (`/satan/run`, `/satan/hippocampus`).
`$HOME/notes` is ro-bound to `/satan/notes`.

### Key resolution (op://)

Mode `:provider` symbol maps via `satan-broker-provider-key-vars`
(`openrouter` → `OPENROUTER_API_KEY`, plus `anthropic`, `openai`,
`deepseek`). Broker calls `my/op-read-env` at spawn to resolve any
`op://` ref to plaintext, wrapped in `condition-case` so a locked 1P
doesn't crash the run. Resolved plaintext is forwarded into the jail.

### Four traps from the Nix integration

(See [docs/emacs/traps.md](../emacs/traps.md) for the full table. Repeated
here for SATAN-specific relevance.)

1. **Flake builds see only git-tracked files** — `git add` new `.el` or
   `harness/*.py` before `home-manager switch` or
   `nix build .#satan-jailed-gptel-harness`.
2. **`:ensure nil` is "don't install"** — n/a for SATAN itself (no
   `use-package` blocks here), but watch in surrounding modules.
3. **Never `setq` preloaded native-comp vars** — n/a for SATAN.
4. **`trusted-content` entries must be `~/` form** — n/a for SATAN.
5. **Harness build runs `ruff check`** — the
   `pkgs.stdenv.mkDerivation` shape introduced in phase 3B replaced
   `pkgs.writers.writePython3Bin` (single-file only).  `checkPhase`
   runs `ruff check --select E,F,W --ignore E501,E402 .`; the legacy
   W503 / E704 ignores were dropped because ruff doesn't emit them.

### Naming

- `satan-MODULE` for the elisp `provide` symbol.
- `satan-MODULE-name` for public internals; `satan-MODULE--name`
  for private.
- `satan-*` for user-callable commands (`satan-run`,
  `satan-hippocampus`).
- Tool names: `domain_verb` (`org_read_context`, `notify_send`).
  Underscored, not dotted: must match `^[a-zA-Z0-9_-]+$` so the schema
  survives every OpenAI-compatible adapter (OpenRouter → Amazon Bedrock
  rejects dots; OpenAI's own validator does too).

## External dependencies

- **panopticon** (`~/dev/panopticon`, own repo) — captures desktop
  behaviour into `~/.local/state/behaviour/{raw,segments,histograms,current}/`.
  v0.1 sway watcher + firefox extension + segmentizer live as of
  2026-05-19. SATAN consumes via `activity_read` (read-only, no IPC
  from the broker — handler runs in Emacs and reads files directly).
  See `~/dev/panopticon/HANDOVER.md`.

## Open threads

Numbered for cross-referencing in commits / changelog.

1. **Real-API live smoke** — ✅ done 2026-05-19. Morning run against
   OpenRouter produced a daily-note SATAN block and a full
   `transcript.jsonl` with `usage` log events.
2. **`org-roam` backlinks in morning context** —
   `satan-context-morning` currently only dumps today's note text +
   prompt. Surfacing backlinks for unresolved-loop items would let the
   model thread yesterday's open questions into today's plan.
3. **Hippocampus / proposal review UX (magit-style)** — v1 is raw
   `find-file` / dired (`satan-hippocampus`). When volume
   warrants, a `magit-status`-style buffer over `proposals/` +
   `hippocampus/` with `a`pply / `r`eject / `s`nooze actions.
4. **Budget-exhaustion UX** — ✅ done 2026-05-19. On first budget
   breach the harness emits `log{kind=budget_warning}` and appends a
   system-role nudge to the chat; the model gets one turn to call
   `satan_final`. If it doesn't, the harness force-terminates with
   `final{reason=budget_tokens}` (the old behaviour, now an escape
   hatch rather than the primary path).
5. **Pi / Zerostack harness adapter** — same `Provider` interface,
   different runtime. Plug-in via env (`SATAN_PROVIDER=pi`). Not
   started.
6. **Self-describing manifest** — ✅ done 2026-05-19 (phase 2E).
   Broker writes full JSON Schema for each allowed tool into
   `manifest.json["tools"]`; harness reads verbatim. Descriptions are
   loaded from `~/notes/satan/tools/<name>.md` (mind/mechanism split).
7. **Self-edit scope expansion** — currently
   `satan-self-edit-root = ~/.emacs.d/satan/`. Broader (full
   `~/.emacs.d/`) is on the table when SATAN's edit suggestions prove
   trustworthy.
8. **`org_read_context` scope coverage** — only `today | week | inbox`.
   `org-agenda`, `org-roam` graph queries, recently-edited files would
   all be useful.
9. **Bundle-section framing in `build_system_prompt`** — ✅ done
   2026-05-19 (phase 3D). Section headers (`# Now`, `# Today (raw)`,
   `# Source files`) live in `~/notes/satan/system/framing.txt`; the
   broker renders the full system prompt and writes it into
   `bundle["prompt"]`; the harness is a passthrough
   (`return bundle["prompt"]`). No canonical model-facing prose lives
   in dotfiles anymore.
10. **`activity_read` current-scope title leak** — `scope="current"`
    returns sway's focused-window snapshot verbatim, including the
    `title` field. Sway IPC titles surface browser tab page-titles,
    editor file paths, Slack thread subjects, etc. — anything the
    focused window puts in its title bar. When this lands in the LLM
    request body the provider can log it. Acceptable for now; tighten
    later either by (a) stripping `:title` SATAN-side or (b) having
    panopticon write a `current/sway-public.json` without title for
    consumers like SATAN to read.
11. **Perceptual loop v0 (Phases 0–6)** — ✅ landed 2026-05-22→23.
    Percept capsule, auto-resonance, motive file, sensor alerts,
    outcome observer, cooldown floor — all in. Design doc
    [[satan-perceptual-design]] §1.5 has the per-phase landing map.
    Next: collect a month of `:worked_count:` + `auto_rule` traces
    before designing v1 (hypothesis substrate, intrusion ceiling,
    outcome scorer). Durable carry-forwards live in
    [[satan-follow-ups]].
12. **Patch agent (Phase 3 mechanism + content)** — Phase-3 mechanism
    landed (DB + worktree + 5 tools + adapter protocol + pi adapter
    + runner + inbox handoff + classifier, commit `17575424`); Phase-3
    content (tick + self-edit prompts routing patch-shaped work via
    `patch_job_create`) in flight. 5 open issues per
    `docs/satan/patch/handover.md` (PATH resolution for jailed-pi,
    cancel doesn't kill process, op popup count, empty stdout log on
    success, §4.6 acceptance owed). Possible pivot: extract runner to
    the standalone Go daemon at `~/dev/satan-patcher/` (noted in
    `patch/archive/handover-phase3-mechanism.md`; not decided). Phase
    4 (memory hooks) out of v1 scope.
13. **`@satan` directive trigger (at-satan)** — ✅ landed
    (`satan-tools-atsatan.el`); `tick-agent` mode registered
    (weights `pulse=5/agent=3`). Design + plan in
    `docs/satan/at-satan/{design,plan}.md`. Future tools sketched
    (`background_enqueue`, `web_fetch`) but not started.
14. **Outstanding bough gaps** — B1 (per-status-transition history)
    closed by DR-116 2026-05-21; B2 (`--max-depth N` on
    `node subtree`) open, worked around by elisp post-pruning. See
    [[satan-bough-gaps]].

## Preferred shape of future work

Improvements usually fall into one of these categories:

- **Better context** — agenda; backlinks; recently-edited notes;
  unresolved loops; bough graph queries; project summaries.
- **Better review** — proposal review UI; hippocampus review UI;
  accept/reject/snooze flows; diff-based self-edit review.
- **Better portability** — second harness adapter; self-describing
  manifests (done — phase 2E); provider-neutral tool schema generation.
- **Better governance** — clearer capability policy; stronger audit
  verification; narrower jail profiles; better failure handling.
- **Better usefulness** — daily planning loop; evening reflection loop;
  weekly pattern review; capture triage; MOTD/status loop.

Avoid adding autonomy before improving review, audit, and context.

## When implementation conflicts with this document

Either:

1. change the implementation to restore the invariant, or
2. deliberately revise this document and explain why the governing
   principle changed.

Do not let accidental implementation drift become architecture.
