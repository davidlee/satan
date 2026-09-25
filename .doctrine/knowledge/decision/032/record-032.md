User-directed, 2026-09-25: "any file with a txt org or md extension; nothing hidden (starting with a dot). and for double-handling - I think we should allow, but aim to make it obvious which reads are equivalent."

Decision, in three parts.

1. **Extension allowlist.** `notes_read` opens `.org`, `.md`, `.txt` only. Those are the corpus's note formats; anything else (a project's `justfile`, a `.json`, a binary) is refused as an error, per DEC-029's refusal policy. The allowlist is case-insensitive on the extension.

2. **No hidden paths.** A path is refused if any component begins with `.` (`.git`, `.env`, `.dir/note.org`). Hidden material under a notes root is configuration and tool state, not notes.

3. **Overlap with `org_read_context` is allowed deliberately, not engineered away.** The journal, the week file and `inbox.org` are reachable from both tools, and that redundancy is accepted: an extension-shaped gate is legible and cheap, whereas carving out the fixed files would refuse a path the model has every reason to think is a note, and would put a rule in the reader that belongs to the caller's choice of tool.

The condition on (3) is the user's: make the equivalence obvious. Both corpus descriptions carry it — `tools/notes_read.md` names the scopes `org_read_context` serves, and `tools/org_read_context.md` points at `notes_read` for the same files. Nothing enforces that coupling mechanically, so it is a description-level obligation the plan must carry, and a later drift is a doc-table drift.

Rationale for gating at the extension rather than at the content: it refuses nothing the tool exists for (IT-001's blind spot is project pages, slips and journal-era notes, all `.org`/`.md`/`.txt`), and it makes the door's width auditable from the description alone.