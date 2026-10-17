# SATAN's jails and patcher on the LLM gateway

## Context

flakes:SL-011 built the LLM gateway: a LiteLLM proxy on
`http://127.0.0.1:4000/v1` holding the provider keys. Each client holds only
its own gateway key (budget, model list), a 0600 file under
`~/.config/llm-gateway/keys/<client>`. flakes:SL-013 (done 2026-10-17) gave
`agents.lib.mkJailedAgents` a gateway mode: a jail built with
`gateway = gatewayClient "<client>"` reads the key file in its launcher and
passes `LLM_GATEWAY_KEY` over an fd (`--args FD`), never argv; pi gets a
generated `models.json` pointing at the gateway.

satan was left out of SL-013 as flakes:IMP-030. Today it still moves
plaintext provider keys:

```
op://… ─satan-credential.el─> broker process-environment ─try-fwd-env─> bwrap argv ─> harness jail
                          └─> patch adapter env ─passApiKeysFromEnv─> jailed-pi
satan-patcher (flakes/features/satan/patcher.nix) ─apiKeyRefs OPENROUTER, DEEPSEEK─> jailed-pi
```

Target:

```
broker / patch adapter / satan-patcher ──(no keys)──> jail launcher
jail launcher ──reads keys/<client>──fd──> jail ──> 127.0.0.1:4000 ──> providers
```

This also closes most of ISS-029 (SPEC-002 NF-004 / REQ-016, criteria 3–4):
keys on bwrap argv, and `SATAN_MAX_BUDGET_TOKENS` not forwarded into the
harness jail.

Naming trap: `satan-gptel-harness` is satan's **Python** harness
(`satan/harness/`, providers `deepseek.py`, `openrouter.py`), not the Emacs
gptel package.

## Scope & Objectives

1. **Harness jail on the gateway.** `satan-jailed-gptel-harness` uses gateway
   mode; the harness gains a gateway (OpenAI-compatible) provider reading
   `LLM_GATEWAY_URL` / `LLM_GATEWAY_KEY` (one endpoint, model by alias:
   DEC-044).
   Drop the four `*_API_KEY` `try-fwd-env` forwards.
2. **Forward the budget ceiling.** `satanGptelJailOptions` forwards
   `SATAN_MAX_BUDGET_TOKENS` (ISS-029 criterion 4), asserted by test.
3. **Broker stops resolving keys.** Remove `satan-broker-provider-key-vars`
   and its key-policy path (`satan-broker.el:48-57, ~743`); modes select a
   gateway model, not a provider key.
4. **jailed-pi and subagent jails on the gateway** (`pi` key; delete
   `jailed-opencode` and `jailed-dirge`, OQ-5). `jailed-pi`,
   `jailed-pi-research`, `jailed-shell`, `jailed-claude` use gateway mode
   (as flakes:SL-013 did for the emacs flake); `jailed-claude` gains pi as a
   subagent so it can run pi research agents (DEC-047); no
   `passApiKeysFromEnv`, no `op run`; drop `dirge` from `subagents`.
5. **Patch path keyless.** Empty or delete
   `satan-patch-adapter-pi-api-key-vars` (`satan-patch-adapter-pi.el:32-44`)
   and the runner's readiness gate over it (`satan-patch-runner.el:252-314`).
6. **satan-patcher daemon** (`~/flakes/features/satan/patcher.nix`, other
   repo): drop `apiKeyRefs`; the jail it builds reads its own key file.
   Re-lock `agents` in **both** satan's and flakes' `flake.lock` (the
   deployed harness builds via flakes' `satan` input); set the untracked
   `~/.config/satan-patcher/policy.toml` defaults to
   `llm-gateway`/`deepseek-flash` and drop its `cheap+code` tag. Order
   (DEC-048): satan, then flakes + home-switch, then restart Emacs, then the
   emacs edit.
7. **Retire `satan-credential.el` and the SL-018 credential surface**
   (DEC-042): mode keys `:credential-policy`/`:credential-escalate-after`,
   `credential_*` statuses, `credential-refs`, and, in the emacs repo,
   `satan-credential-function` (`dl-satan.el`) and `my/satan-credential`
   (`dl-secret.el`).
7a. **Typed launcher refusal** (DEC-041): a child that dies before `ready`
   without an error message is `spawn_failed`, audited with its stderr tail;
   perception frontiers commit only on `ready`, once, from the snapshots taken
   at perceive (ingest heads included).
7b. **Harness talks only to the gateway** (DEC-044): no `SATAN_PROVIDER`,
   no `:provider` in profiles; `budget_exceeded` classifies as `credits`
   (DEC-045); a 403 model-access refusal is `auth`, a dropped connection
   `server`, a timeout still `timeout`.
7c. **Flake check** asserting the built harness launcher's env (DEC-046).
8. **Issue keys** and document (`docs/`, README) which client each jail uses.
   Key budgets are deployment-side insurance caps, not SATAN policy
   (DEC-043).

## Non-Goals

- Emacs's in-process LLM clients — gptel, minuet, unjailed eca, and the
  config's `dl-llm-gateway.el` key reader: owned by **emacs:SL-015**. satan
  needs no elisp key reader: the jail launcher reads the key file.
- Retiring `~/.config/zsh/env.zsh` `*_API_KEY` exports: emacs:SL-015 OQ-5,
  unblocked when this slice closes.
- New gateway providers/models: flakes:IMP-029. Needed here only if satan's
  modes require OpenRouter models (OQ-4).
- ISS-028 (dev jails binding the Emacs socket, harness binding `~`
  read-write): same REQ-016, different gap.
- ISS-038 / ISS-039 (patch adapter resolving `jailed-pi` from PATH; two
  `patch_jobs` consumers).
- Renaming `satan-gptel-harness`.
- ISS-043 (`satan-attrd` jail forwards provider keys on argv): split out of
  ISS-029, no owner yet.

## Coordination with emacs:SL-015

| concern | owner |
|---|---|
| gptel / minuet / unjailed eca → gateway, `dl-llm-gateway.el`, `my/op-key` removal | emacs:SL-015 |
| satan jails, harness, broker, patch adapter/runner, `satan-credential.el` | this slice |
| `satan-patcher` module in `~/flakes` | this slice (cross-repo step) |
| `dl-satan.el` / `dl-secret.el` satan credential backend | this slice (DEC-042) |
| client wire convention for reasoning effort | shared; see design |
| `env.zsh` export removal | emacs:SL-015, after this slice |

No shared code: the two slices meet only at the gateway (one key per
consumer) and at `env.zsh`.

## Affected surface

Owned by the design: `design.md` § Code impact.

## Risks & assumptions

- **A1**: agents gateway mode (flakes:SL-013) works for `makeJailedAgent`
  (harness, shell), not only `makeJailedPi`. Verify in research.
- **A2**: the satan-patcher systemd unit runs as a user that can read
  `~/.config/llm-gateway/keys/<client>`.
- **R1: model coverage.** The gateway serves `deepseek-flash`; satan modes
  using OpenRouter models break until flakes:IMP-029, unless remapped.
  Settled: SATAN's one profile is `deepseek-flash` (OQ-4).
- **R2: the broker's key check is a readiness gate.** Removing it must not
  silently turn a missing key file into a late harness failure; the jail
  launcher's error must surface in the run audit. Settled by DEC-041.
- **R3: two consumers of `jailed-pi`** (elisp runner, satan-patcher;
  ISS-039) with different `agents` provenance (direnv live vs lock).
- **R4: cross-repo.** `patcher.nix` is outside `just check`; verify by
  build and by hand.

## Open questions

Settled by the user, 2026-10-17:

- **OQ-1** Two keys: `satan` (harness, broker-driven) and `pi` (jailed-pi
  and the other pi jails). The patch path is low-value: the patcher barely
  works and its replacement is under construction (the gateway is part of
  that motive; cf. IDE-007). Give it the minimum, sharing `pi`; no
  investment beyond removing its keys.
- **OQ-5** Delete `jailed-opencode` and `jailed-dirge`.

Settled in design, 2026-10-18:

- **OQ-2** Harness provider shape: one gateway endpoint, model by alias; the
  per-provider classes go (DEC-044).
- **OQ-3** `satan-credential.el` serves only provider keys; it is retired
  outright with the SL-018 credential surface (DEC-042).
- **OQ-4** Modes need only `deepseek-flash`; flakes:IMP-029 is not a
  prerequisite.

## Verification / closure intent

- Flake check (DEC-046) asserting the harness jail's env list:
  no `*_API_KEY`, `SATAN_MAX_BUDGET_TOKENS` present (REQ-016 criteria 3–4).
- ert: broker spawns without provider-key resolution; patch runner readiness
  no longer depends on key vars; a launcher refusal is `spawn_failed` and
  leaves every perception frontier unchanged.
- Harness tests: gateway provider builds requests from
  `LLM_GATEWAY_URL`/`LLM_GATEWAY_KEY`.
- `rg '_API_KEY|op://|op run' flake.nix satan/` shows only documented
  exceptions.
- Manual (VH): a broker tick and a patch job succeed; `llm-gateway list`
  shows spend on satan's key(s); `ps` shows no key in argv.
- `just check` green.

## Summary

Move satan's harness jail, pi jails and patcher onto the LLM gateway via
agents' gateway mode, so no satan process holds a provider key; forward the
budget ceiling into the harness jail. Implements flakes:IMP-030; closes
ISS-029's criteria 3–4.

## Follow-Ups

- emacs:SL-015 OQ-5 (`env.zsh` retirement) unblocks on close.
- Note this slice on flakes:IMP-030 and emacs:SL-015.
