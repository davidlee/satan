# RSK-020: Production runs two revisions of malebolge: pinned runner, live-tree room daemon

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Violates SPEC-002 NF-003 (REQ-015). Sibling of RSK-016. Accepted by the user
for the interactive daemon (SL-028, 2026-10-20).

The patch runner (`satan-runner`) runs `inputs.malebolge.packages.<sys>.runner`
(the `~/flakes` lock, or the dev checkout under `bin/dev-checkouts override`),
while the room daemon unit `malebolge-room` (SL-028) execs `jailed-malebolge`,
whose wrapper runs `/home/david/dev/malebolge/src/daemon-main.ts` from the
live tree (`~/dev/satan/flake.nix:228-232`). Shared code (`src/config.ts`,
gateway/door parsing, room env) can differ between the two with no error.

Detection: `~/flakes/SATAN.md` names both sources. No version handshake exists.

Mitigations: run the daemon from the malebolge input (drop the live-tree
literal), or a protocol/version check where the two share state.
