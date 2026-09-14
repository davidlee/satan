# CHR-004: Retarget self-edit prompts' allowed_paths and check globs to the relocated corpus and extracted package (SL-015 follow-up)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

SL-015 PHASE-03 retargeted the self-edit prompts' literal `~/notes/satan/…`
strings to `~/satan/…` (`~/satan` `c02b2b2`) and nothing more (phase A6). The
prompts are stale well beyond that, since SL-012 extracted the package out of
`~/.emacs.d`:

| File | Stale claim |
|---|---|
| `~/satan/prompts/self-edit-mech.txt:5,75` | code lives under `~/.emacs.d/satan/` (now `~/dev/satan/satan/`) |
| `self-edit-mech.txt:13` | `allowed_paths` mixes repo-relative (`satan/`, `test/`) with a home path (`~/satan/tools/`) — the latter is outside any single patch repo |
| `self-edit-mech.txt:17` | check glob `satan/test/dl-satan-*-test.el` (prefix dropped in SL-012; tests are `satan-*-test.el`) |
| `self-edit-mind.txt:20` | `allowed_paths` `["satan/prompts/", "~/satan/prompts/", …]` — same repo-relative/home mix |

Corpus content is now committed in the `~/satan` repo, so a mind self-edit is a
patch against repo `~/satan` with repo-relative paths (`prompts/`, `system/`,
`tools/`). Mechanism self-edits are patches against `~/dev/satan`.

Found as SL-015 PHASE-03 F-5. Check against the patch job schema
(`satan-tools-patch.el`) before rewriting — `repo` + `allowed_paths` semantics
are defined there.
