---
name: at-satan-plan
description: AT-SATAN — rewrite plan (two-stage B→A deliverable)
metadata:
  type: plan
  topic: satan-at
  status: draft
  updated_at: 03398479
  verified_at: 03398479
---

# Plan: Rewrite design.md as two-stage deliverable (B → A)

## Overview

The existing `design.md` (588 lines) is a thorough design document with
pseudo-code, but has several loose ends and inaccurate code references.
Two-phase deliverable:

1. **Phase B — tighten the design doc.** Resolve every open question with
   concrete elisp patterns, replace pseudo-code with eval-able forms, fix the
   handful of factually wrong claims about how the broker / rg / tick
   subsystems actually behave, show exact `rg` invocation and parse, exact
   hash function and digest length, exact output shape, exact tick-agent
   prompt text, exact diff for morning mode. Nothing left to guess.
2. **Phase A — append an implementation guide section** to the same file.
   File-by-file recipe. Verbatim content only for the load-bearing artifacts
   (handler claim logic, tick-agent prompt, the round-trip ert test); the
   rest is described in enough detail that a future agent can produce them
   inline. Sequence for building and testing.

## Phase B: factual corrections (must land before any elisp is written)

The current design doc and the previous version of this plan got several
things wrong about the existing code. Phase B is the chance to fix them.

### B1. Capability-symbol citation

| Wrong | Right |
|---|---|
| "broker passes capabilities as *symbols* (see `dl-satan-broker.el:266-267`)" | Lines 266-267 do `(mapcar #'symbol-name ...)` and convert capabilities to **strings** for the harness/LLM JSON metadata. The in-process tool-handler path is `dl-satan-broker.el:109`: `:capabilities (plist-get mode :capabilities)` — preserved as symbols. Confirmed handler-side at `dl-satan-tools-org.el:73-76` and `dl-satan-tools-inbox.el:49-51`, both of which do `(memq 'sym caps)` against the symbol list. |

Doc-level resolution: the resolved-decisions table cites
**`dl-satan-broker.el:109`** for the symbol-list contract, and the handler
boilerplate uses `(memq 'write-notes (plist-get ctx :capabilities))` to match
the existing org/inbox pattern.

### B2. `rg --null` parse recipe

| Wrong | Right |
|---|---|
| "NUL-delimited handling via `split-string \"\\0\" t` (same pattern as `dl-satan-tools-notes--run-fd`)" | `rg --null` NUL-separates **filename from line:content** within a record; records are still **LF-terminated**. The `fd -0` pattern (true NUL-terminated records) does not transfer. |

Doc-level resolution: specify the parse explicitly. Two viable options;
pick one and show the elisp:

- **Option A (chosen):** `rg --json -n --line-number @satan <root>` →
  parse each LF-terminated line as JSON; keep entries whose `type` is
  `"match"`. Robust against paths containing colons or NULs. Slightly
  more bytes per record but trivially parseable.
- **Option B (rejected):** `rg --null -n --no-heading -H` → split stdout on
  `\n` into records, then split each record on the first `\0` into
  `(path . "line:content")`, then split `"line:content"` on the first `:`.
  Workable but two cascaded splits and edge cases around CRLF / embedded
  colons in content.

Phase B includes the Option-A `call-process` form, copying the stderr-temp-
file pattern from `dl-satan-tools-notes--run-fd` (the call-process plumbing
*does* transfer; only the parse doesn't).

### B3. Excluding `@satan-done` lines

| Wrong | Right |
|---|---|
| "Pipe through `grep -v '@satan-done'`" | Post-filter in elisp after parsing. Piping `rg --null` output through `grep -v` breaks the NUL framing; `grep -z -v` would preserve it but is an extra moving part. With Option-A JSON output the filter is one `seq-remove` over the parsed match list. |

Resolution: drop the pipe. Filter `@satan-done` matches in elisp.

### B4. Hash length / id format

The current doc shows `:id "M-d3a2f1"` (6 hex chars). Plan resolution says
"first 12 hex chars". Pick one and sync. **Decision: 12 hex chars** (48
bits, comfortable for ≤200 results per scan). Update the worked-example
output to read `:id "M-d3a2f17b8c4e"`.

Stability caveat to add to the doc: the hash is `(file . line)` — stable
within a single scan→done cycle, **not** across edits that shift line
numbers. Implementer should not later treat the id as a cross-run anchor.

### B5. Tick-pool weights

| Wrong | Right |
|---|---|
| 'add `("tick-agent" . 3)` … weighted below `"tick-pulse"`' | Current default is `'(("tick-pulse" . 1))`. Setting agent=3, pulse=1 makes agent *higher* than pulse, not lower. The design.md draft sets pulse=5, agent=3. Either change both, or pick coherent numbers. |

Decision: keep pulse=5, agent=3 (matches existing draft). Phase A modifies
both entries of the `dl-satan-tick-pool` defcustom default. Note that this
is a defcustom — users with `M-x customize` overrides won't pick up the new
entry; an inline `Customisation note:` is added to the doc.

### B6. Run-id source for the claim marker

`@satan-done(<run-id>,comment)` requires the handler knows the current
run-id. Not currently called out. Resolution: read from
`(plist-get tool-ctx :id)` — the broker populates it at
`dl-satan-broker.el:107`. Add to the resolved-decisions table so the green
implementer doesn't fumble looking for it in run-state, env, or mode-spec.

### B7. Drop the line-number anchor for the morning diff

| Wrong | Right |
|---|---|
| "single-line edit to `dl-satan-mode.el:75`" | Line numbers rot. Describe the edit by the morning mode's `:tools` plist key (currently around line 70 but unimportant). |

### B8. Verify command for ert

| Wrong | Right |
|---|---|
| `emacsclient --eval '(ert "notes-at-satan-")'` | `(ert)` interactive returns immediately. Use `(ert-run-tests-interactively "notes-at-satan-")` for a popped-up results buffer, or `(ert-run-tests-batch "notes-at-satan-")` for headless. |

### B9. Tool-list overlap (`org_read_context` × `notes_at_satan_scan`)

The scan returns context lines and an org headline already. Why also carry
`org_read_context` in the `tick-agent` mode?

Decision: **keep both**. Scan returns a fixed N-line window plus the
immediate headline; `org_read_context` lets the agent expand to the full
subtree or a different file when a directive references work elsewhere
("@satan check the bough tree for this project"). Document the boundary in
the tick-agent prompt: scan first, only use `org_read_context` to expand a
specific reference the scan surfaced.

### B10. Require chain (load order)

`dl-satan-tools-atsatan.el` calls `dl-satan-tick-register` at load time.
That symbol lives in `dl-satan-tick.el`. If `dl-satan.el` requires the
new tools file before tick, load fails.

| Wrong | Right |
|---|---|
| Slot `(require 'dl-satan-tools-atsatan)` alphabetically | Insert it **after** `(require 'dl-satan-tick)` in `dl-satan.el`. Tools file's mode registration depends on `dl-satan-tick-register` being defined. |

Phase A's "Files to modify" entry for `dl-satan.el` calls this out
explicitly; the anchor is "immediately after the `dl-satan-tick` require".

### B11. `rg --json` output schema

NDJSON records carry `.type` ∈ `{begin, match, context, end, summary}`.
Only `match` records are interesting.

Field map (locked):

| Field | Path |
|---|---|
| File path | `.data.path.text` |
| Line number | `.data.line_number` (1-based) |
| Matched line text | `.data.lines.text` |

Parse recipe: `split-string stdout "\n" t` → `mapcar` over
`json-parse-string` (with `:object-type 'plist`) → `seq-filter` on
`(equal (plist-get rec :type) "match")` → `seq-remove` the
`@satan-done` matches → build result entries.

### B12. Context window: in-elisp slice, not `rg -A/-B`

`rg --json` with `-A N -B N` emits separate `type=context` records that
must be re-associated to their preceding match — fragile across record
ordering and requires per-file state tracking in the parser.

Decision: **in-elisp slice.** After parsing matches, open each match's
file once (cached by path within the scan), take lines `(line - N)
.. (line + N)` from the buffer, join with `\n`. Buffer-walk also does the
org headline walk-up — single file open serves both needs.

### B13. Headline walk-up for markdown

| Wrong | Right |
|---|---|
| Walk up for `^*+ ` regardless of extension | Org regex misses markdown. Behaviour: try `^\\(\\*+\\|#+\\) ` first match walking backward. Return the matched heading text (including the leading sigil) so the LLM sees `** Maintenance` vs `## Maintenance` and can tell. Return `nil` if neither found. |

### B14. Test fixture shape

Round-trip test (the verbatim one) needs an ephemeral root so it does
not write into `~/notes/`. Fixture pattern:

```elisp
(let* ((root (make-temp-file "satan-atsatan-test-" 'dir))
       (dl-satan-tools-atsatan-root root)
       (file (expand-file-name "test.org" root)))
  (unwind-protect
      (progn
        (write-region "* H\n- @satan do thing\n" nil file)
        ;; … scan, assert, done, re-scan, assert …
        )
    (delete-directory root 'recursive)))
```

Phase B documents this pattern in the "verbatim round-trip test"
subsection. Other ert tests share it via a `cl-macrolet` or a
`with-atsatan-root` helper macro (Phase A authors the helper).

### B15. Inter-file concurrency caveat

Optimistic re-read protects against double-claim of the same line.
Does not protect against two ticks editing different lines of the same
file concurrently — both read full file, edit one line, write whole
file; last write silently wins.

Probability under a 30-min systemd timer is near zero. Under
hand-driven `my/satan-run "tick-agent"` during development it is
plausible.

Decision: **accept the risk for v1.** Document it as a known limitation
in the design invariants section. Future: file-level lock via
`make-lock-file` / `lock-buffer` if it bites.

## Phase B: replace pseudo-code with eval-able elisp

Every code block currently marked ```` ```elisp ```` becomes eval-able:

- **Register forms** — real `dl-satan-tool-register` plists with the
  schema, modes list, and handler symbol filled in.
- **Handler functions** — `require` at top, `defcustom`/`defconst` forms,
  full handler body with `condition-case`, exact `(cons 'ok ...)` /
  `(cons 'error ...)` return shape matching neighbours like
  `dl-satan-tools-inbox.el`.
- **Tick registration** — `(dl-satan-tick-register "agent" ...)` with the
  overrides plist. Note: `dl-satan-tick-register` prepends `"tick-"` to
  produce `tick-agent`, and resolves the prompt file to
  `<prompts>/tick/agent.txt`. So the public mode name is `tick-agent` and
  the short-name argument is `"agent"` — the doc must be consistent.
- **Hash function** — `(secure-hash 'md5 (format "%s:%d" file line))` then
  `(substring digest 0 12)`. Built-in to Emacs 30.2; no dep.
- **`rg` invocation** — concrete `call-process` form with `--json -n`, temp
  output buffer, stderr-temp-file (cribbed from `--run-fd`), JSON parse via
  `json-parse-string` line by line.

## Phase B: add the missing pieces

### Worked output example

Two `@satan` hits in different files, full JSON-shape result. Demonstrates
the headline walk-up (the heading the line falls under) and the context
window. Length: ~25 lines including formatting. Goes in the
`notes_at_satan_scan` section.

### Verbatim tick-agent prompt

The behavioural frame for autonomous action — the highest-leverage artifact
in this whole effort. Goes in the doc as a fenced code block at the
bottom of the `Mode: tick-agent` section, also written verbatim into
`~/notes/satan/prompts/tick/agent.txt`. Includes:

- "Scan first, act second" rule
- "Claim each immediately after acting" rule
- "Prefer existing tools — agenda_read, inbox_append, bough_read" rule
- "Skip what you cannot do; leave a hippocampus entry" rule
- "No side effects without a tool call" rule
- "If a directive is ambiguous, skip it" rule

### Resolved design decisions table

Replaces the current `## Open questions` section. Each row carries the
question, the decision, and the rationale — the same body as B1-B9 above
plus the already-resolved Q1-Q6 from the current doc (separate scan/done
tools, hybrid context window, optimistic concurrent-claim check, default
extension filter, code-block references included with judgment, soft
truncation flag).

## Phase A: Implementation guide (appended section)

Append `## Implementation guide` after the tightened design section.

### File-by-file checklist

For each file to **create**, the section gives:

- Full path
- One-paragraph description of contents
- Verbatim content **only for the load-bearing artifacts** (see scope
  decision below)
- Any `git add` step required (only for files under `~/.emacs.d/satan/` —
  the notes-repo files do not feed the Nix flake build)

For each file to **modify**, the section gives:

- File path
- Anchor (function name, defcustom name, or mode-list `:tools` key) — not a
  line number
- Exact old_text → new_text for the edit

### Verbatim-content scope (Phase A simplification)

Earlier draft promised "verbatim content" for all five new files; that
balloons the doc without proportional value. Decision:

| File | Treatment |
|---|---|
| `~/notes/satan/prompts/tick/agent.txt` | **Verbatim.** Behavioural prompt — every word matters. |
| `satan/dl-satan-tools-atsatan.el` claim function (`dl-satan-tool/notes-at-satan-done`) | **Verbatim.** Optimistic re-read, idempotent claim, run-id embedding — subtle. |
| `satan/test/dl-satan-tools-atsatan-test.el` round-trip test (`notes-at-satan/scan-then-done-then-rescan`) | **Verbatim.** One test that exercises scan → done → re-scan; demonstrates the contract. |
| `dl-satan-tools-atsatan.el` scan function | **Described** (call-process form, JSON parse, filter, build match plists). Future agent fills in. |
| `~/notes/satan/tools/notes_at_satan_scan.md`, `_done.md` | **Described** (3-paragraph spec, audience: the LLM). |
| Remaining ert tests | **Described** (one paragraph per test case). |

### Files to create

1. `satan/dl-satan-tools-atsatan.el` — handlers + registrations
2. `satan/test/dl-satan-tools-atsatan-test.el` — ert (5 tests; round-trip
   verbatim, others described)
3. `~/notes/satan/tools/notes_at_satan_scan.md` — model-facing description
4. `~/notes/satan/tools/notes_at_satan_done.md` — model-facing description
5. `~/notes/satan/prompts/tick/agent.txt` — tick-agent prompt (verbatim)

### Files to modify

1. `satan/dl-satan.el` — add `(require 'dl-satan-tools-atsatan)`. Anchor:
   the existing block of tool requires.
2. `satan/dl-satan-mode.el` — add `"notes_at_satan_scan"` (not `_done`) to
   the `morning` mode's `:tools` list. Anchor: the `(list :name "morning"
   …)` form's `:tools` key.
3. `satan/dl-satan-tick.el` — change `dl-satan-tick-pool` defcustom default
   from `'(("tick-pulse" . 1))` to `'(("tick-pulse" . 5) ("tick-agent" .
   3))`. Anchor: the `defcustom dl-satan-tick-pool` form. Note the
   customisation caveat: users with `M-x customize` overrides need to
   re-add the entry manually.
4. `satan/dl-satan.el` (separately or same edit): nothing else — the
   `tick-agent` mode is registered via `dl-satan-tick-register "agent"`
   inside `dl-satan-tools-atsatan.el`'s load body, so a single require is
   enough.

### Build-verify sequence

```sh
git -C ~/.emacs.d add satan/dl-satan-tools-atsatan.el
git -C ~/.emacs.d add satan/test/dl-satan-tools-atsatan-test.el
# Notes-side files live under ~/notes/ — separate repo, no flake involvement.

cd ~/flakes && home-manager switch --flake .#david

# Run the ert suite headless. Exits non-zero on failure; failure output
# goes to stdout (unlike emacsclient --eval, which swallows it).
emacs -batch \
  -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
  -l ert -l dl-satan-tools-atsatan-test \
  --eval '(ert-run-tests-batch-and-exit "notes-at-satan-")'

# Smoke-test one tick-agent run end-to-end in the live emacs:
emacsclient --eval '(my/satan-run "tick-agent")'
# Then inspect the audit bundle:
ls ~/notes/satan/runs/most-recent/
```

## What this plan does NOT change in design.md

- The `background_enqueue` and `web_fetch` sketches — they remain "future
  tools, design sketch, not v1".
- The claim lifecycle ASCII diagram — correct, only wording tightens.
- The design invariants section — accurate, kept verbatim.

## Decision log (from the design tightening)

| Question | Decision | Rationale |
|---|---|---|
| Hash function | `(secure-hash 'md5 (format "%s:%d" file line))` → `(substring digest 0 12)` | Deterministic, built-in to Emacs 30.2, no dep. 48 bits comfortable for ≤200 results. |
| Hash stability | Single-scan-cycle only | `(file . line)` shifts under edits; documented as non-persistent. |
| `rg` invocation | `rg --json -n @satan <root>` parsed line-by-line | Robust against colons/NULs in paths; avoids cascaded split bugs. |
| Exclude `satan/` dir | `--glob '!satan/**'` plus a defconst exclude list mapped to repeated `--glob` flags | Matches existing `dl-satan-tools-notes--exclude` pattern. |
| Exclude `@satan-done` lines | Post-parse elisp filter (`seq-remove`) | Pipe-through-grep breaks NUL/JSON framing; PCRE lookahead is overkill. |
| Context-window method | Line-sliced N-above/N-below plus org headline walk-up | Hybrid; matches existing draft. |
| Concurrent claim safety | Optimistic re-read of the target line; if already `@satan-done`, return `(:status "already-done")` | Idempotent, matches Q3 resolution. |
| `write-notes` capability | New symbol, checked via `(memq 'write-notes (plist-get ctx :capabilities))` | Matches `inbox-write` / `write-daily` pattern. Central capability registry is a future refactor. |
| Run-id source for marker | `(plist-get tool-ctx :id)` (broker populates at `dl-satan-broker.el:107`) | Avoids the green-implementer fumble. |
| Default path-pattern | `.*\.(org\|md)$`, overridable | rg `-g` for extension filter. |
| `tick-agent` short-name vs full name | `dl-satan-tick-register "agent"` → mode name `tick-agent`, prompt `<prompts>/tick/agent.txt` | Convention enforced by `dl-satan-tick-register`. Doc uses both consistently. |
| Require chain | `(require 'dl-satan-tools-atsatan)` must come **after** `(require 'dl-satan-tick)` in `dl-satan.el` | Tools file calls `dl-satan-tick-register` at load time. |
| `rg --json` field map | path = `.data.path.text`; line = `.data.line_number`; content = `.data.lines.text`; filter `.type == "match"` | Locks the parse surface so the elisp doesn't drift. |
| Context lines | In-elisp slice from the file buffer (±N around `:line`) | `rg -A/-B` context records must be re-associated to their match — fragile. Buffer is already opened for the headline walk-up. |
| Headline walk-up | Walk backward for `^\\(\\*+\\|#+\\) `; return matched heading text or nil | Org and markdown both covered with one regex. |
| Test fixture | `make-temp-file ... 'dir` + `let`-bound `dl-satan-tools-atsatan-root` + `unwind-protect` cleanup | Keeps `~/notes/` clean; round-trip test verbatim form documented in Phase B. |
| Inter-file concurrency | Accepted limitation for v1 | Two ticks editing different lines of the same file at once can lose a claim. Probability near zero under 30-min systemd timer. Document in design invariants. Future: `make-lock-file`. |
| Verify command | `emacs -batch -l ert -l <test> --eval '(ert-run-tests-batch-and-exit "notes-at-satan-")'` | Non-zero exit + stdout output on failure; `emacsclient --eval (ert-run-tests-batch …)` swallows results. |

## Constraints

- One file: `./design.md`. No code changes in this plan's deliverable.
- design.md stays self-contained as a design + implementation spec.
- Existing section ordering preserved so anyone who has read the doc
  before can still find their place.
- No new external dependency: `rg` and `fd` are already in the Nix env;
  `secure-hash` is built-in; the elisp side uses `call-process` like its
  neighbours.
