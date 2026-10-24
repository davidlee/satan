@.doctrine/state/boot.md
If you have NOT seen `BOOT-SENTINEL: doctrine-governance-snapshot` anywhere in your context (system prompt or preceding messages), you MUST read the file referenced above now. If you HAVE seen it, you MUST NOT — the content is already in context. If that file does not exist, doctrine is not set up in this checkout: tell the user to install doctrine and run `doctrine install`.

---

**Use pi agents for delegation in this repo — not `claude -p`, not Claude subagents.**

pi on deepseek is ~20× cheaper than you, and every route below returns a reduced transcript rather than a wire log. Keep your context for judgement.

**Default — the `pi_agent` MCP tool (server `quotient`, tool `mcp__quotient__pi_agent`)**

One blocking call: `pi_agent(prompt, profile)` → `{state, final, result, transcript, status, artifacts, refusal, session}`. `quotient help result` is the full contract.

- `profile`, defined in `~/.config/quotient/profiles/` (quotient ≥ 0.3.0 reads no launch-dir layer): `read` (read-only view of the root; tools `read, grep, find, ls, bash`; `thinking: off`) is for recon. `research` is the same with `thinking: low`, for judgement. `write` adds `edit, write` and a writable root. Each is callable only while the operator policy's `profiles` lists it.
- Trust `result` only when `final` is true. Otherwise read `state`, `causes`, and `transcript`. `refused` means nothing ran; `refusal.reason` says why.
- `session`: pass back the returned id to continue the conversation.
- `cwd` defaults to this repo; other roots must be in the policy. `tools` and `ceilings` can only narrow.
- Evidence for every run lives under `artifacts.dir` (`~/.local/state/quotient/runs/…`), outside the tree.

Operator setup, outside the repo (an absent or malformed policy refuses every call):

- Policy: `~/.config/quotient/policy.json` (mode 0444; schema `quotient-policy/1`, see `quotient help policy`). It names the forms by stable link, `~/.local/state/quotient/forms/<capability>/bin/quotient-<capability>`.
- `just quotient-forms` rebuilds those links and `~/.local/state/quotient/bin/quotient` (GC-rooted). Run it after changing the forms in `flake.nix` or bumping the `quotient` input.
- The server is the `quotient` entry in `.mcp.json`, run from that bin link; `quotient help clients` prints the client snippets.
- Profiles are read once at start-up. Restart the session after editing `~/.config/quotient/profiles/`.

**Judgement — governance applicability, competing readings, tradeoffs**

Use `pi_agent(profile: research)` when the policy enables it. Otherwise, or for custom flags, use the shell route:

```bash
export PI_BIN=jailed-pi                     # host only: bare `pi` holds no gateway key
export PI_MODEL=llm-gateway/deepseek-flash  # the only model the gateway's models.json names
./scripts/pi-research "does ADR-017 reach a new MCP spawn surface?"
./scripts/pi-scout --think low "trace every caller of satan-tool-dispatch"   # recon with thinking
```

Answer on stdout, prompt on argv or stdin, `PI_BACKSTOP` seconds hard cap (default 900). Their tool lists include `write`: give them read-only questions, or an isolated worktree if they must write. Inside `jailed-pi` the cwd is `/workspace/<basename>` and sibling repos are `/workspace/<name>`; write prompt paths that way. Already inside a jail? Leave `PI_BIN` unset.

**Raw shell runs** (custom flags, no MCP client): `pi --mode json … > events.jsonl`, then `~/.local/state/quotient/bin/quotient reduce events.jsonl --alert 'FAIL|\.doctrine/'`. The reducer exits 0 on completed, 1 on failed or incomplete. Traps:

- `--mode rpc` is **not** a one-shot: it shuts down on stdin EOF and answers nothing. Always `--mode json`.
- json mode exits 0 even when the model errored. The verdict is `status.state`, or the reducer's exit code.
- Leave `--no-extensions` in, or the child pi loads your MCP config and can recurse.
- `--tools` *replaces* the tool set: name every tool you want.
- stdout is JSONL only. Never `2>&1` it.
- Through `jailed-pi`, `/tmp` is a fresh tmpfs per run. Put a `--session-dir` that must survive under the cwd.

---
