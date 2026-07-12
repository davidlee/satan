# 00-CONTEXT.md — Scout's mental model

## Sources consulted (in order)

1. `AGENTS.md` — project orientation, tool conventions, architecture overview
2. `docs/satan/INDEX.md` — doc index
3. `docs/satan/governance.md` — canon: philosophy, file map, modes, tools, ops
4. `docs/satan/architecture.md` — seven-layer model (invocation/broker/harness/model/tool/output/state)
5. `docs/satan/protocol.md` — JSONL wire spec (skim)
6. `docs/satan/patch/brief.md` + `patch/handover.md` — patch-agent design + current state (skim)
7. `docs/satan/memory/design.md` (lines 1–100) + `memory/handover.md` — memory substrate (skim)
8. `docs/emacs/naming.md` — naming conventions (`dl-MODULE`, `--private`, `my/`)
9. `CHANGELOG.md` — last 200 lines + all SATAN entries (sip)

## Mental model

SATAN (Scheduled Agent for Textual Attention and Notes) is a local, Emacs-mediated, org-backed agent runtime. It is **not** a chatbot or autonomous daemon — it is a constrained system that periodically reads personal context, reasons over it through a jailed model/harness, and produces bounded, inspectable effects through a trusted broker.

### Seven canonical layers (per architecture.md)

| Layer | Description | Key files |
|---|---|---|
| **Invocation** | When/why SATAN runs (scheduled timers, manual `M-x my/satan-run`) | `dl-satan.el`, `dl-satan-tick.el`, `bin/satan-run`, `bin/satan-run-tick` |
| **Broker** | Trusted authority: mode resolution, context assembly, process lifecycle, tool dispatch, audit | `dl-satan-broker.el`, `dl-satan-context.el`, `dl-satan-mode.el`, `dl-satan-audit.el` |
| **Harness** | Talks to a model/runtime (OpenRouter, fake test harness, pi) | `harness/__main__.py`, `harness/runloop.py`, `harness/providers/*.py`, `harness/bundle.py` |
| **Model** | Performs reasoning (external — not in this codebase) | N/A (external API) |
| **Tool** | Broker-owned capabilities with schemas, risk levels, allowlists | `dl-satan-tools.el` + `dl-satan-tools-*.el` (14 tool files) |
| **Output** | Validates/routes model output: apply low-risk, stage proposals, reject | `dl-satan-output.el`, `dl-satan-block.el` |
| **State** | Local, text-first, inspectable state (hippocampus, proposals, runs, prompts) | `~/notes/satan/` (not in this repo), `dl-satan-jsonl.el` |

### Current state

SATAN has evolved through multiple phases:
- **Phase 1**: Broker + JSONL protocol + jailed fake harness (2026-05-19)
- **Phase 2**: Real LLM harness, tools (notify, hippocampus, self-edit), mind/mechanism split
- **Phase 3**: Protocol reification, harness multi-file split, bundle framing
- **Memory substrate**: Grammar, canonicalizer, evidence-window, PostgreSQL store (complete v1)
- **Patch-agent**: Git-worktree-based coding harness integration (Phase 3 content landed, acceptance still owed)
- **Perceptual-layer v0**: Motive file, auto-resonance, sensor alerts, outcome observer, percept capsule, cooldown floor (Phases 0–6, most recent)

### Trust boundaries

- Broker = trusted (Emacs process)
- Model/harness = untrusted (bubblewrap-jailed)
- Communication via JSONL stdin/stdout
- Tool descriptions live in `~/notes/satan/` (mind); tool schemas/handlers live in dotfiles (mechanism)
- Mode allowlists + capability checks gate every tool call

### Naming conventions (per docs/emacs/naming.md)

- `dl-satan-MODULE` — public module API
- `dl-satan-MODULE--name` — module-private (cross-file `--` calls are a coupling smell)
- `my/satan-*` — user-facing interactive commands
- Tool names: `domain_verb` (underscored, not dotted)
- Test files mirror source with `-test.el` suffix
