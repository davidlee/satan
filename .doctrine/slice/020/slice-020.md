# notes_read and notes_grep: read the user's notes corpus from inside the harness

## Context

SATAN has a *temporal* index of the user's notes and no *content* access to them.
`notes_recent` (`satan/satan-tools-notes.el`) lists which files moved in a window
— path, mtime, denote title/tags — and `notes_at_satan_scan` reads only
`@satan` directive regions. `org_read_context` returns fixed files (today's
journal, the week file, `inbox.org`). Everything else under `satan-notes-root`
is, from inside the jail, unreachable: a `ruminate` run can see that
`forgettable.org` changed and cannot read a line of it.

This is the oldest unactioned item on the r3 iteration board (IT-001, first seen
2026-06-01 — a proposal staged that day,
`~/satan-corpus/proposals/20260601T000614--add-notes-read-tool-and-disambiguate-docs-vs-notes-tool-namespaces__satan_proposal.org`,
and re-confirmed by the 2026-09-25 holistic audit's §3.3 fix list). The board's
own falsifier is a registry grep: a `notes_read`/`notes_grep` tool exists.

It is a goal-1 (usefulness) gap: the charter's first line is contact with the
user's *stated* intentions, and their project notes are where those intentions
live. It also unblocks the disambiguation half of the June proposal by giving
the notes corpus a namespace that a `docs_*` name can be read against.

## Scope & Objectives

Add two read-only tools over the notes corpus, modelled on `notes_recent` — same
root (`satan-tools-notes-root`), same risk class, same host-side subprocess
shape, no capability:

- **`notes_read :path`** — the body of one file under the notes root, with the
  denote metadata `notes_recent` already computes (`:title`, `:tags`, `:ext`,
  `:mtime`), capped in **bytes** at `satan-tools-notes-read-max-bytes` and
  carrying `:bytes`, `:total-bytes` and an explicit `:truncated` flag. The path is
  notes-root-relative only and everything else is refused as an error
  (**DEC-029**); the door is `.org`/`.md`/`.txt` only, and never a hidden path
  (**DEC-032**); running out of cap is a flagged truncation, not a failure
  (**QUE-002** carries the deferred pagination question).
- **`notes_grep :query [:limit]`** — search across the corpus (`rg`,
  case-insensitive, **literal** `--fixed-strings`, gitignore-aware) over the file
  set `notes_read` can open — every hit is openable, one-way (**DEC-033**) —
  returning one line per match as `{:path :line :text}` with paths **relative to
  the notes root**, capped in total (flagged) with **no per-file cap**. Literal
  rather than regex because the query targets user prose — a model-typed phrase
  must not be silently reinterpreted as a pattern; `notes_at_satan_scan`, over
  this same corpus, made the same call (`satan-tools-atsatan.el:148`), where
  `hippocampus_grep`'s regex targets SATAN's own curated titles.

Both are *read broadly, write narrowly*: read-only, no capability, no new
authority item (ADR-017 §3 ledger unchanged).

Supporting work the pair drags with it:

1. **Naming.** `satan-tool/notes-read` is today the handler for `notes_recent` —
   the name the new `notes_read` tool needs. Rename it to
   `satan-tool/notes-recent` (mechanism-internal; no behaviour change).
2. **Confinement.** A path argument is a new class of input for this module: it
   must resolve only *inside* the notes root (relative, no `..` component, no
   absolute path, no symlink escape, not the root itself), and refuse loudly
   otherwise.
3. **Mind surface.** `tools/notes_read.md` + `tools/notes_grep.md` in the corpus
   (`satan-tools-descriptions-dir`), and the allowlists that make them reachable:
   `morning`, `motd`, `ruminate`.
4. **Doc mirrors.** Four prose surfaces restate the registries, each gaining its
   rows: `docs/governance.md` `## Tools` (under IT-011's live two-way diff) and its
   `## File map` module→tool row; `docs/resilience-design.md` §2.2 (tier drop
   lists) and §3 (the per-tool tier inventory). Omitting the `## Tools` rows would
   *regress* an open board item rather than merely leave drift.
5. **Tier classification.** The harness's token-exhaustion ladder
   (`satan/harness/runloop.py` `TIER_1_DROP` / `TIER_2_DROP`) is a second tool
   registry: an unclassified tool stays available at every tier, which would
   weaken the wind-down guarantee for exactly the tool that pulls note bodies
   into context. `notes_grep` joins tier 1 (survey tools, beside
   `hippocampus_grep`); `notes_read` joins tier 2 (focused reads, beside
   `org_read_context` / `hippocampus_read`) — **CON-001** makes placing every
   tool an obligation, and `docs/resilience-design.md` §2.2 is its prose mirror.
6. **Failure policy.** A missing or failing `fd`/`rg` — and any exit code above
   `rg`'s 1 — is an **error**, not an empty result; `rg` exit 1 (no matches) is a
   clean empty result (**DEC-030**). `content_read`'s soft-fail-to-empty is
   explicitly not the model.
7. **Interactive exposure.** Registering either tool also exposes it on the
   `interactive` MCP surface, which is the union of every registered tool, and
   MCP startup fail-fasts on a missing description file — so the two corpus
   descriptions are load-bearing for the keeper's own session, not only for the
   three scheduled modes (**DEC-031**).
8. **Equivalence legibility and the prompt (DEC-032 part 3).** `notes_read`
   deliberately overlaps `org_read_context` on the journal, the week file and
   `inbox.org`. The overlap is allowed on the condition that it is obvious: both
   `tools/notes_read.md` and `tools/org_read_context.md` name the reads that are
   equivalent, so a caller can tell which door it is standing in. Nothing
   enforces this mechanically — a description-level obligation the plan carries,
   and a later drift is a doc drift, not a bug. The same reasoning puts the pair
   into `prompts/ruminate.txt`'s gather phase, which today names `notes_recent`
   alone: adding tools to a mode whose own instruction does not name them leaves
   the capability unusable in practice, which is the gap this slice closes.

## Affected Surface

| Surface | Repo | Change |
|---|---|---|
| `satan/satan-tools-notes.el` | mechanism | two handlers, `rg` runner, path confinement, handler rename, two registrations |
| `satan/test/satan-tools-notes-test.el` | mechanism | tests for the above |
| `satan/test/satan-broker-test.el` | mechanism | description fixtures for the new morning tools (manifest build looks up one per allowed tool) |
| `satan/satan-mode.el` | mechanism | `morning`, `motd`, `ruminate` `:tools` allowlists |
| `satan/harness/runloop.py` | mechanism | tier-1 / tier-2 drop sets |
| `satan/harness/test_gptel_harness.py` | mechanism | tier-ladder tests |
| `tools/notes_read.md`, `tools/notes_grep.md` | mind | new description files |
| `tools/org_read_context.md` | mind | names the reads equivalent to `notes_read` (DEC-032) |
| `tools/notes_recent.md` | mind | the two sentences this slice makes false |
| `prompts/ruminate.txt` | mind | the gather phase names the find-then-read pair |
| `docs/governance.md` | mechanism | `## Tools` rows and the `## File map` module row |
| `docs/resilience-design.md` | mechanism | §2.2 drop lists and the §3 per-tool inventory |

## Non-Goals

- **The `docs_*` → `project_docs_*` rename.** Part 2 of the June proposal;
  higher-impact, touches every prompt that names those tools, and not what
  IT-001's falsifier asks for. Its own slice.
- **`notes_list`** (all notes, not just recently changed). `notes_grep` with a
  broad query covers the discovery need; a third listing surface is not yet
  earned.
- **Any write path into the notes root.** The notes repo is the user's; SATAN
  reads it and writes to its own corpus. Not in this slice, and not later
  without an ADR-level argument.
- **Extraction.** POL-001 lists `satan-tools-{atsatan,notes}.el` under *earns the
  seat* ("the notes corpus as substrate") — the mechanism stays in the client.
  Holding a read-only tool does not re-open that.

## Risks & Open Questions

- **R3 — interactive exposure (DEC-031, accepted).** Registering a tool also
  puts it on the `interactive` MCP surface, and MCP startup fail-fasts on a
  missing description. Accepted deliberately (read-only tools over the user's own
  notes, in the session most entitled to read them), so R3 is a risk only if the
  plan splits the registration from the description files.
- **R1 — token cost.** A read tool lets a run pull arbitrary note bodies into a
  budgeted context, and notes are uncurated (a capture file can be huge). The
  character cap plus `:truncated` is the mitigation, and the tier ladder
  (objective 5) is the backstop; **QUE-002** tracks the residual case.
- **R2 — budget/attention regression.** Adding two tools to three allowlists
  widens each mode's manifest. Cheap (two schemas) but non-zero, and the
  `morning`/`motd` budgets are already a live board item (IT-011's mode table).
- **R4 — doc-table drift.** `docs/governance.md` `## Tools` is under IT-011's
  live two-way falsifier and `docs/resilience-design.md` §2.2 mirrors the tier
  sets; both are checked mechanically by the VTs above.
- **R5 — unenforced description coupling (DEC-032).** The equivalence sentences
  in `notes_read.md` and `org_read_context.md` have no test behind them and can
  rot silently. Accepted: the alternative is a test asserting prose, which pins
  wording nobody can then improve. Checked by eye at slice close, and visible as
  doc drift afterwards.
- **A1 — assumption.** `rg` and `fd` are available on the host path the broker
  spawns from; `notes_recent` already depends on `fd` in exactly this way, so the
  assumption is no weaker than the status quo. A missing binary must fail loud,
  not empty (the `content_read` soft-fail-to-empty policy at
  `satan-tools-content.el:242-260` is explicitly *not* the model — SL-015's
  "a wrong-but-readable path is worse than an error").
- **A2 — assumption.** The `~/notes` files a run most wants are gitignore-clean;
  `rg`/`fd` default ignore behaviour is the same filter `notes_recent` already
  uses, and is the intended one (see `notes_recent`'s own description). The
  extension globs added by DEC-033 are pinned explicitly rather than inherited
  from that default.

## Verification & Closure

- **VT (mechanism)** — `satan/test/satan-tools-notes-test.el`: body + metadata
  round-trip and the date-prefix `:title` rule; nested and plain relative paths;
  refusal of absolute, `..`, empty and wrong-type paths; refusal of the root and
  of a directory as `not a file`; **refusal of a symlink inside the root pointing
  outside it** (the only case exercising truename containment, RV-019 F-9);
  refusal of a non-note extension and of any hidden path component (DEC-032);
  missing file; byte cap with `:bytes`/`:total-bytes`/`:truncated`; an absent
  notes root named as such for both tools; grep argv (expanded root,
  case-insensitive, literal, **globs derived from the extension defconst**,
  `--max-columns-preview`); **no per-file match cap**; relative-path parsing; rg
  exit 1 as clean-empty and exit 2 as an error; an absent `rg` binary as an error
  (DEC-030); total-match cap; both tools present in the registry with
  `notes_recent` still registered.
- **VT (tier ladder)** — `satan/harness/test_gptel_harness.py`: `notes_grep`
  dropped at tier 1, `notes_read` dropped at tier 2 (CON-001).
- **VT (registry↔allowlist)** — `satan-mode-check-tool-references` passes, and
  the `morning` manifest builds with the new names (broker test).
- **VA (drift)** — IT-011's registry-minus-`## Tools`-table diff is empty after
  the change (it is non-empty *before*, for other tools — the new names must not
  appear in that output).
- **VA (board)** — IT-001's falsifier returns the new names:
  `grep -rl 'notes_read\|notes_grep' ~/dev/satan/satan/*.el`.
- **Closure** — both tools callable in a `ruminate` or `morning` manifest, with
  their descriptions loaded from the corpus, and the board item closable with
  that evidence.

## Summary

Two new read-only tools in `satan-tools-notes.el`, a handler rename, a path
confinement rule plus an extension/hidden filter, five corpus files (the pair,
`org_read_context`'s equivalence pointer, `notes_recent`'s corrected sentences,
and `ruminate`'s gather phase), three mode allowlists, four doc-table mirrors, the
harness tier ladder, and tests. One module, one slice.

## Follow-Ups

- `docs/data-collection.md` §3.5 describes `notes_recent` as "excludes `satan/`"
  (the corpus left `~/notes` in SL-015) and has no `notes_read`/`notes_grep`
  subsection. Board drift item.
- **QUE-002** — whether a single over-cap note needs offset pagination. Decide
  when a real note is found that the flat cap renders useless.
- The `docs_*` rename (June proposal part 2).
