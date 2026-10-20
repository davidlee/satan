@.doctrine/state/boot.md
If you have NOT seen `BOOT-SENTINEL: doctrine-governance-snapshot` anywhere in your context (system prompt or preceding messages), you MUST read the file referenced above now. If you HAVE seen it, you MUST NOT — the content is already in context. If that file does not exist, doctrine is not set up in this checkout: tell the user to install doctrine and run `doctrine install`.

---

**Use pi agents for delegation in this repo — not `claude -p`, not Claude subagents.**

pi on deepseek is ~20× cheaper than you, and the wrapper returns a reduced transcript rather than a wire log. Keep your context for judgement. One-time setup per shell:

```bash
export PI_BIN=jailed-pi                     # host only: bare `pi` holds no gateway key
export PI_MODEL=llm-gateway/deepseek-flash  # the only model the gateway's models.json names
```

Inside `jailed-pi` the cwd is `/workspace/<basename>` and sibling repos are `/workspace/<name>` (`/workspace/malebolge`, …) — write prompt paths that way. Already inside a jail? Leave `PI_BIN` unset: `jailed-pi` is on the jail's PATH too, and would nest.

**Recon — cheap, no thinking**

```bash
./scripts/pi-scout "where is the spawn path implemented?"
./scripts/pi-scout --think low "trace every caller of satan-tool-dispatch"
echo "long prompt" | ./scripts/pi-scout          # argv or stdin
```

**Judgement — governance applicability, competing readings, tradeoffs**

```bash
./scripts/pi-research "does ADR-017 reach a new MCP spawn surface?"
```

Both: answer on stdout, prompt on argv or stdin, `PI_BACKSTOP` seconds hard cap (default 900). Their tool lists include `write` — give them read-only questions, or an isolated worktree if they must write.

**When you need the evidence, not just the answer**

```bash
mkdir -p /tmp/run
"${PI_BIN:-pi}" --mode json --model "$PI_MODEL" --tools read,grep,find,ls,bash \
   --no-extensions --no-skills --no-context-files --offline --approve \
   --session-dir /tmp/run/session "…" > /tmp/run/events.jsonl
./bin/pi-run-reduce /tmp/run/events.jsonl --alert 'FAIL|\.doctrine/'
# stdout: one status line   stderr: alert lines   /tmp/run/{transcript.md,status.json}
```

`-v` prints the transcript, `-q` prints nothing, `--budget-bytes N` bounds it. Exit 0 = completed, 1 = failed or incomplete, 2 = usage. From bash, `source scripts/lib/pi-report.sh` and call `pi_report <stream> "[label]"` — it degrades to a tail when node is missing.

**Follow-on turns** — `--session-id <stable-id>` on a second run continues the conversation (verified across separate processes). Same id, same `--session-dir`. Through `jailed-pi`, `/tmp` is a fresh tmpfs per run: put a session dir that must survive under the cwd (it is bound), not `/tmp`.

**Traps, all learned the hard way**

- `--mode rpc` is **not** a one-shot: it shuts down on stdin EOF and answers nothing. Always `--mode json`.
- json mode exits 0 even when the model errored — the verdict is `status.state`, or the reducer's exit code.
- Leave `--no-extensions` in, or the child pi loads your MCP config and can recurse.
- `--tools` *replaces* the tool set: name every tool you want.
- stdout is JSONL only, one record per LF. Never `2>&1` it — you'd count diagnostics as events.

---
