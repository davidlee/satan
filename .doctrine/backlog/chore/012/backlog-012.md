# CHR-012: Spike: pi-durable host for interactive SATAN (pandaemonium)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Spike agreed with the user 2026-10-16 (design sketch + backlog, no slice).
Feeds RFC-018 ("Pi Durable as the harness"); findings land there.

## Why

`just hello-satan` (in `~/notes`) runs a jailed pi coding-agent (`jpi`) with
`.pi/extensions/satan.ts` bridging SATAN's MCP socket. Pi Durable
(`@earendil-works/pi-durable`) offers durable conversations, crash-safe turns,
resume and background compaction — the harness RFC-018 proposes.

## Key finding (preflight)

Pi Durable is a **library**, not a CLI/TUI, and does **not** load
coding-agent extensions (`ExtensionAPI`, `pi.registerTool`). Its own
`defineExtension`/`defineTool` model replaces them. A host program is needed.

## Sketch

New repo `~/dev/pandaemonium` (outside satan — RFC-018 D1 home rule):

```
daemon ── Harness.open(SQLite under satan-state-root/durable/)
  ├─ CodingTools
  ├─ satan ext: pi-mcp McpClient + unix-socket transport → satan-mcp socket
  ├─ persona section: scaffold.txt + prompts/interactive.txt (satan-corpus-root)
  └─ NDJSON socket ($XDG_RUNTIME_DIR/satan/durable.sock)
       in:  input · abort · compact      out: watchEvents snapshot + batches
clients: `attach` (terminal) · Emacs v0 = comint over attach
```

- Model: `deepseek/deepseek-v4.1-flash`. Keys via env for the spike (ISS-029
  accepted); `~/flakes` IDE-003 (LiteLLM proxy) is the intended fix.
- SATAN tools are `replay: "unsafe"` (default): interrupted → error result.
- Jail: worst case, run from a jailed shell.

## Outputs

- Working `just hello-durable` alongside `hello-satan`.
- RFC-018 "Spike findings" section.

## Progress (2026-10-16)

Built and verified live. Repo `~/dev/pandaemonium` (uncommitted, awaiting
user); `just check` green: biome, tsc, 65 vitest tests.

- Model default `deepseek/deepseek-flash`: what the jailed pi's `~/notes`
  sessions actually ran (jail home `/home/agent/jail.nix/home/agent`).
  `deepseek-v4.1-flash` is not in the `deepseek` catalog; it exists only as
  `openrouter/deepseek/deepseek-v4.1-flash`.
- Live, against satan-mcp (37 tools) and DeepSeek under `op run`:
  - persona loaded; `satan_boot_context` called; answer streamed;
  - late attach replays the transcript;
  - SIGKILL during a `bash` call → restart resumed the run, the tool came
    back `interrupted` with its committed output;
  - comint client checked in batch Emacs;
  - SIGTERM shuts down cleanly.
- Renderer bugs found live and fixed test-first, all one root cause: an
  answer's text is spread over `message_start` (first partial),
  `message_update` (deltas, or whole `block`/`message` replacements) and
  `message_end` (the final entry holds the tail). The renderer now tracks the
  answer's text and prints only the unseen part.
  - Unit tests with hand-written event sequences missed it; an end-to-end test
    (faux model at 40 tok/s through the real daemon) asserts the exact client
    output and was mutation-checked against both bugs.
- `~/notes/justfile`: `hello-durable`, `attach-durable` (uncommitted).
- Findings → RFC-018 § "Spike findings" (F1–F7).
- Memories: `mem.fact.pi.durable-is-a-library`,
  `mem.fact.satan.jailed-pi-home-and-op-keys`.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-17 · spike close · 9de3a7e (all CHR-012 work uncommitted)

### Produced
- `~/dev/pandaemonium` — pi-durable daemon + attach client + comint client; 65 tests (uncommitted, no commits yet)
- `~/notes/justfile` — `hello-durable`, `attach-durable` (uncommitted)
- RFC-018 § Spike findings — F1–F7
- minted: IMP-037 — jail the daemon; IMP-038 — satan-mcp reconnect; RSK-018 — daemon socket authority; IDE-008 — pi-env habitat; IDE-009 — modes as events; IDE-010 — native Emacs client

### Learned
- mem.fact.pi.durable-is-a-library — library not CLI; no coding-agent extensions; watchEvents answer-text gotcha
- mem.fact.satan.jailed-pi-home-and-op-keys — jail home path; op:// keys need `op run` outside the sandbox
- EVD-004 — SIGKILL mid-tool: run resumes, unsafe tool returns interrupted with committed output

### Open
- QUE-003 — does pandaemonium replace hello-satan or coexist
- ASM-004 — env keys via `op run` until `~/flakes` IDE-003
