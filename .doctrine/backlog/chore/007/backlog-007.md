# CHR-007: Retarget stale dl-satan-* symbol names and ~/.emacs.d paths in corpus tool descriptions and framing (SL-012 follow-up)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

SL-012 dropped the `dl-satan-*` library prefix (every symbol is now
`satan-*`) and moved the package out of `~/.emacs.d`. The corpus at
`~/satan` still cites the old names and the old root in model-facing
text, so SATAN reads symbol names that no longer resolve:

| File | Stale claim |
|---|---|
| `~/satan/system/framing.txt:2` | "Loaded by `~/.emacs.d/satan/dl-satan-context.el`" — now `~/dev/satan/satan/satan-context.el` |
| `~/satan/tools/notes_at_satan_intervention_done.md:19` | `dl-satan-intervention-write-manual-outcome` |
| `~/satan/tools/docs_search.md:16` | `dl-satan-tools-docs` |
| `~/satan/prompts/tick/agent.txt:62` | `dl-satan-patch-classify` |
| `~/satan/tools/vcs_log.md:16` | repo search list `~/dev/<slug>`, `~/.emacs.d`, `~/flakes` — verify against `satan-tools-vcs.el`; `~/.emacs.d` no longer holds satan, and `~/satan` (corpus) is missing |

Distinct from [[CHR-004]] (paths in the self-edit patch lane, done) and
[[CHR-006]] (`~/notes/satan` paths in `docs/` prose). This one is stale
*symbol names* in corpus prose, from SL-012 rather than SL-015.

Verify each name against the live defun before rewriting — some may
have been renamed, not just re-prefixed (SL-012 resolved two collisions
to verb-first command names).
