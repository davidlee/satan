# 12-HARNESS-BOUNDARY.md — Elisp↔Python harness contract surface

## Protocol (JSONL messages)

Both sides implement and test against the same spec (`docs/satan/protocol.md`) and fixtures (`protocol/fixtures.json`):

### Message types

| Type | Elisp validator | Python validator | In fixtures? |
|---|---|---|---|
| `ready` | `dl-satan-protocol.el` | `harness/protocol.py` | Yes |
| `log` | `dl-satan-protocol.el` | `harness/protocol.py` | Yes |
| `tool_call` | `dl-satan-protocol.el` | `harness/protocol.py` | Yes |
| `final` | `dl-satan-protocol.el` | `harness/protocol.py` | Yes |
| `error` | `dl-satan-protocol.el` | `harness/protocol.py` | Yes |
| `tool_result` (outbound) | `dl-satan-protocol.el` | `harness/protocol.py` | Yes |

Protocol field names match on both sides for all message types.
confidence: high — both load the same `fixtures.json` and assert matching behaviour.

### Fixture path resolution

- **Elisp**: `dl-satan-protocol-fixtures-path` → `protocol/fixtures.json` relative to source dir
  `dl-satan-protocol.el:157-159`
- **Python**: `fixtures_path()` → `../protocol/fixtures.json` relative to `harness/`
  `harness/protocol.py:192-194`

Paths resolve to the same file.
confidence: high

## Environment variables

| Variable | Set by | Read by (elisp) | Read by (python) | Match? |
|---|---|---|---|---|
| `SATAN_RUN_ID` | Broker spawn | `dl-satan-broker.el` | `harness/__main__.py` | Yes |
| `SATAN_RUN_DIR` | Broker spawn | `dl-satan-broker.el` | `harness/bundle.py` | Yes |
| `SATAN_PROVIDER` | Broker spawn | `dl-satan-broker.el` | `harness/providers/__init__.py` | Yes |
| `SATAN_MODEL` | Broker spawn | `dl-satan-broker.el` | `harness/providers/base.py` | Yes |
| `SATAN_BUDGET_TOKENS` | Broker spawn | `dl-satan-broker.el` | `harness/runloop.py` | Yes |

All 5 env vars are forwarded by the broker and consumed by the harness. Exact match.
confidence: high

## Bundle/Manifest contract

### Bundle format (`bundle.json`)

Both sides agree on the bundle structure:
- `prompt`: string (assembled system prompt + framing)
- `manifest`: path or embedded manifest

### Manifest format (`manifest.json`)

| Field | Elisp producer | Python consumer | Match? |
|---|---|---|---|
| `mode` | `dl-satan-broker.el` | `harness/bundle.py` | Yes |
| `run_id` | `dl-satan-broker.el` | `harness/bundle.py` | Yes |
| `harness` | `dl-satan-broker.el` | `harness/bundle.py` | Yes |
| `provider` | `dl-satan-broker.el` | `harness/bundl_.py` | Yes |
| `model` | `dl-satan-broker.el` | `harness/bundle.py` | Yes |
| `budget_tokens` | `dl-satan-broker.el` | `harness/bundle.py` | Yes |
| `budget_calls` | `dl-satan-broker.el` | `harness/bundle.py` | Yes |
| `tools` (JSON Schema array) | `dl-satan-tools.el` | `harness/bundle.py` | Yes |

The `tools` array contains OpenAI-compatible JSON Schemas built by `dl-satan-tools.el` from hander specs + notes-side descriptions. Python reads them verbatim via `build_tools`.
confidence: high — manifest is the core contract and both sides agree.

## Jailed file paths

| Path | Inside jail | Purpose |
|---|---|---|
| `~/notes` | `/satan/notes` (ro) | Notes tree read access |
| `~/notes/satan/hippocampus` | `/satan/hippocampus` (rw) | Hippocampus write access |
| Run directory | `/satan/run` (rw) | Bundle/transcript/actions |

These paths are set in the flake's jail derivation (flake.nix) and consumed by the broker's spawned process env. Both sides agree.
confidence: high — tested via integration ert (fake harness).

## `satan_final` synthetic tool

The harness intercepts `tool_call` with `name = "satan_final"` and translates it into a `final` record. The broker never sees a `tool_call` of that name. Plain-content responses with no tool calls are coerced into `final{reason: "no_tool_calls"}`.

This is a harness-side convention documented in `protocol.md`. Both sides agree.
confidence: high — documented and fixture-tested.

## Budget warning protocol

When `tokens_total` crosses `SATAN_BUDGET_TOKENS`, the harness emits a `log{kind: "budget_warning"}` and appends a system-role message asking for `satan_final`. If the model doesn't comply, the harness force-terminates with `final{reason: "budget_tokens"}`.

This is a harness-side behaviour documented in `protocol.md`. The broker-side budget gate (`dl-satan-budget.el`) handles the pre-spawn daily ceiling. These are two distinct budget mechanisms (daily ceiling in broker, per-run budget in harness).
confidence: high — both mechanisms documented and tested.

## Items referenced from only one side (potential drift)

1. **`SATAN_HIPPOCAMPUS`** — mentioned in governance doc as a jail-internal path but not found in current elisp code references. Possibly set by the flake's jail derivation only.
   confidence: low — need to check flake.nix for this env var.

2. **`dl-satan-patch-adapter-pi.el`** — the pi adapter resolves API keys via `my/op-read-env` and scrubs `op://` refs. The pi harness itself (external to this codebase) must accept these as process env. The contract is implicit — no shared spec governs which env var names are used.
   confidence: medium — the adapter-pi has its own env var list hardcoded in `dl-satan-patch-adapter-pi-api-key-vars` (7 keys: openrouter, anthropic, openai, deepseek, google, together, fireworks). The pi coding agent must be configured to read these; there's no shared doc.

3. **`jailed-pi` binary** — the patch-agent adapter resolves to this binary via `executable-find`. The binary is built by the Nix flake. The HANDOVER doc notes PATH-resolution issues when Emacs's `exec-path` doesn't include the direnv-managed devshell PATH.
   confidence: high — documented open issue in handover.md.

## Conclusion

The core broker↔harness contract (protocol, manifest, bundle, env vars) is tightly maintained on both sides with shared fixtures and matching validators. The patch-agent integration (pi adapter) has a thinner contract boundary — no shared fixtures, no dual-side validator, implicit env composition.
