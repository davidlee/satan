# ISS-053: SPEC-002 Transports has no row for the client → malebolge interactive daemon socket

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

SPEC-002 §Transports (`.doctrine/spec/tech/002/spec-002.md:80-93`) names every
channel except the client socket of malebolge's interactive daemon
(`$XDG_RUNTIME_DIR/satan/durable/<profile>/durable.sock`; protocol
`~/dev/malebolge/src/protocol.ts`). The runner's equivalent control socket has
a row (`:89`).

SL-030 gives that socket a verb that creates durable agent state (select or
create a conversation), so its absence becomes more costly. Per SPEC-002 D3
("gaps are backlog, not prose"), add a row via a SPEC-002 revision, or record
that it is deliberately below the spec's altitude.

Found in SL-030's research (Thread 1, governance).
