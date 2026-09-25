# IMP-032: Split harness protocol out of the persona scaffold so interactive can omit it

## Context

`system/scaffold.txt` is one document serving two audiences. Its closing
`Protocol:` section — emit JSONL only, end every run with a real `satan_final`
call, never emit free-form prose — is correct for the broker-spawned batch runs
(morning / motd / self-edit-* / ruminate / tick), which
`satan-context--assemble-prompt` reads. It is wrong for the interactive pi
session, whose system prompt is `~/notes/.pi/SYSTEM.md`, built by
`~/notes/justfile:10-13` as `cat scaffold.txt; cat prompts/interactive.txt` —
and whose manifest has no `satan_final` tool.

Surfaced as the corpus iteration board's IT-012 (2026-09-25) and closed the same
day by the cheap mitigation below. This item records the durable fix.

## Current mitigation (this item's starting point)

`prompts/interactive.txt` now opens with a `## Precedence` block that names the
scaffold's `Protocol:` section and declares it superseded; `.pi/SYSTEM.md` was
regenerated. Pinned by
`satan-context/interactive-addendum-supersedes-harness-protocol`.

It works, but it still ships both instructions and relies on the later one
winning. A system prompt that says X and then says "ignore X" is weaker than one
that never said X — and there is no second prose-level guard if the two files
drift apart again.

## Proposed shape

Split the scaffold by audience:

- `system/scaffold.txt` — the persona: identity, core stance, write boundaries,
  memory model, evidence and tool discipline. Shared by every path.
- `system/protocol.txt` — the harness protocol: JSONL, `satan_final`, no prose.
  Read only by the broker path.

`satan-context--assemble-prompt` concatenates scaffold + protocol + mode prompt.
`build-system-prompt` (notes justfile) cats scaffold + interactive only. The
interactive system prompt then *omits* the protocol instead of overriding it.

## Constraint that made this non-trivial

Every test that binds `satan-system-scaffold-file` to a temp file (~15 sites
across `satan-context-test`, `satan-percept-test`, `satan-resonance-test`,
`satan-motive-test`) would also need to bind a new `satan-system-protocol-file`,
or the protocol would be read from the real corpus mid-test and break
`string-prefix-p "SCAFFOLD\n\nPROMPT"`-style assertions. Two ways out:

1. Keep the protocol path **derived** from the scaffold path
   (`<scaffold-dir>/protocol.txt`), read with
   `satan-context--read-file-or-empty`; a temp scaffold then redirects the
   protocol too and existing tests are untouched.
2. Add a `defcustom` and update every test site.

Option 1 is cheaper and self-consistent; settle it in design.

## Acceptance

- `system/scaffold.txt` carries no harness-protocol text.
- The interactive `SYSTEM.md` contains no `satan_final` / JSONL instruction.
- Batch runs still receive the protocol, and the existing context tests pass
  unchanged.
- `satan-context/interactive-addendum-supersedes-harness-protocol` is retired or
  rewritten — its premise (the scaffold carries the protocol) no longer holds.
