# CHR-020: Launch the malebolge daemon from a directory other than ~/notes

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Why

`just hello-durable` (`~/notes/justfile`) runs `nix run ~/dev/satan#jailed-malebolge`
from `~/notes`. Every jail binds its launch directory read-write
(`~/flakes/SATAN.md` § Jails), and the daemon's coding tools work in it, so
interactive SATAN can write the user's notes. That breaks the three-roots rule
(notes are read-only to SATAN; [[mem.concept.satan.three-roots]]). Found while
drafting RFC-019.

## Fix

Launch from a directory SATAN may write, e.g. a scratch dir under
`~/.local/state/satan/durable/` or `~/satan-corpus`, with
`cd <dir> && nix run …` in the recipe, or move the recipe out of `~/notes`.
Notes reads stay available through the `notes_*` MCP tools. Superseded once
RFC-019 D1 (vm mode) moves the coding tools into the room.

Check after: `/workspace/notes` absent inside the jail.
