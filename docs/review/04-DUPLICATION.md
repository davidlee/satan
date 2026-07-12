# 04-DUPLICATION.md — Duplication & near-duplication

## Repeated pattern: mode/tool allowlist specification

Tool→mode mapping has two writers:

- `dl-satan-mode.el` — every mode spec carries a `:tools` allowlist; the broker gates dispatch on this list.
- `dl-satan-tools-atsatan.el` — adds tools to the tick-agent mode at load time via `dl-satan-tick-register` (`patch_job_create`, `patch_job_status`).

The governance handover explicitly says: *"Tool-spec `:modes` is documentary only; the broker does not consult it."* So tool specs carry a `:modes` annotation that nothing reads, while mode specs carry the authoritative `:tools` list — except where `tick-register` mutates that list from outside. Two writers, one reader. confidence: medium.

## Imports across the memory substrate (positive finding, not duplication)

Files requiring the canon/evidence/grammar/store quad:

- `dl-satan-percept.el` — canon, evidence, grammar
- `dl-satan-observer.el` — all four
- `dl-satan-tools-hippocampus.el` — all four
- `dl-satan-tools-memory.el` — all four

These are legitimate consumers; each presents a different surface over the substrate. Not flagged. confidence: medium.

## Capability strings co-defined in tool specs and mode specs

Capability tokens (`"hippocampus-write"`, `"inbox-write"`, `"memory-write"`, `"patch-job-create"`, `"notify"`, `"write-daily"`, `"stage-proposal"`) appear in two places by design:

- `:capability` field in each tool's spec (e.g. `dl-satan-tools-*.el`)
- `:capabilities` list in each mode-spec (`dl-satan-mode.el`)

This is the intended coordination pattern (governance §permission). Strings live nowhere central; renaming one requires touching N call sites. confidence: medium — not duplication in the bad sense, but rename-cost is real.

## Magic numbers: budget/token/timeout constants

Numeric budgets are scattered, by design:

| File | Constant | Default |
|---|---|---|
| `dl-satan-budget.el` | `dl-satan-budget-daily-tokens` | 400000 (now 2M per CHANGELOG) |
| `dl-satan-mode.el` | per-mode `:budget-tokens` | 20000 / 10000 / 3000 / 50000 |
| `dl-satan-tick.el` | `dl-satan-tick-register` defaults | 3000 tokens / 4 calls / 30s |

Intentional per-mode tunables; not flagged.

## Env-var forwarding to child processes

`dl-satan-broker.el:740-755` and `dl-satan-patch-adapter-pi.el:231-280` both build environment lists forwarding `SATAN_RUN_ID`, `SATAN_PROVIDER`, `SATAN_MODEL`, `SATAN_BUDGET_TOKENS`. Same five-ish keys, two construction sites. No shared helper. Currently in sync (verified in 02-DEPENDENCIES). Drift risk if a new key is added on one side only. confidence: high.

## op:// secret resolution

`my/scrub-op-refs-env` is the documented one-way scrub at the broker boundary. Op-cache lookup logic (`op://...` URI → cached secret) appears in:

- `dl-satan-broker.el` — model harness env scrub
- `dl-satan-patch-adapter-pi.el` — pi adapter env scrub

Both call the same helper (`my/scrub-op-refs-env`), so this is shared. The earlier scout draft flagged "op:// resolve duplication" — verified, no duplication, single helper. confidence: high.

## Function-body duplication

Spot-checked two pairs hypothesised by earlier draft:

- `dl-satan-patch-worktree-create` (`patch-worktree.el:81`) vs `dl-satan-patch-store--parse-row` (`patch-store.el:157`) — different shapes entirely (path construction vs DB-row parsing). No overlap.
- `dl-satan-observer-classify` (`observer.el:474`, 46 LOC) vs `dl-satan-percept-build` (`percept.el:45`, 33 LOC) — `percept-build` wraps `evidence-assemble → canon-canonicalize`; `observer-classify` is a guard-cond tree dispatching to predicate functions. No body overlap.

No function-body duplication identified across the codebase by inspection of the largest-19 list. confidence: medium.
