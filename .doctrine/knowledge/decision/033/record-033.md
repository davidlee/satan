User-directed, 2026-09-25: the same `.org`/`.md`/`.txt`, non-hidden filter applies to `notes_grep`.

Decision: `notes_grep`'s search set is exactly `notes_read`'s openable set. rg is invoked with explicit globs for the three extensions (hidden paths are already skipped by rg's default, but the ignore rules are pinned explicitly rather than inherited, so the two tools cannot drift apart through a changed default).

Why the narrow door over complete recall: a hit the model cannot open is a dead end it must narrate, and the narration costs more than the recall is worth. Making every hit actionable by construction also means the pair states one rule, once, in both descriptions, instead of two overlapping widths.

Accepted cost: a search will not surface a match in a non-note file under the root (a stray script, a JSON store). That is a real loss of recall, and it is bounded and legible — the description says what the tool searches, so a model that needs a wider sweep knows this tool is not it.

The pair is therefore one coherent surface: `notes_grep` finds a readable location, `notes_read` opens it. `notes_read`'s extension allowlist (DEC-032) is the single source of that width.


## Correction (2026-09-25, RV-019 F-14)

The phrase "searches exactly the file set `notes_read` can open" overstates the
guarantee in one direction and is corrected here.

The guarantee is one-way: **every `notes_grep` hit is a file `notes_read` can
open** (same three extensions, same hidden-path refusal). The converse does not
hold, because rg's ignore rules still apply with explicit `--glob` set: a note
that `~/notes` gitignores is openable by `notes_read` but invisible to
`notes_grep`. That filter is kept deliberately — it is the same one `notes_recent`
already applies through `fd`, so the corpus's notion of the user's material stays
consistent across the two tools — and the recall loss is disclosed in the tool
description rather than left implicit.
