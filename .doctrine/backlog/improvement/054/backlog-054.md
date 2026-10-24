# IMP-054: MCP run identity per conversation, not per connection (supersede DEC-5 one-run-per-connection)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Problem

The MCP server mints one interactive run (run-id, run dir, audit bundle) per
connection (DEC-5, pre-doctrine MCP design). That fitted one pi session per
connection. The malebolge daemon multiplexes threaded conversations over one
long-lived connection, and scheduled async sessions are about to join them.
So today:

- one interactive run and audit bundle spans the daemon's whole lifetime,
  across every conversation;
- memory-write attribution (`satan-memory-store--current-run-id`, bound to the
  session's run-id in `satan-mcp--tools-call`) cannot tell conversations apart;
- the DEC-8 session gate keys on the connection (see ISS-058).

## Direction (to design)

The client names the conversation per call (e.g. a conversation id in the
`tools/call` `_meta`), and SATAN keys run identity, audit and attribution on
that rather than on the connection. Open questions: run lifecycle for a
conversation (open/close signals, or idle expiry), how scheduled async
sessions are marked so they count against ceilings (IMP-053) and the budget,
and what replaces the DEC-8 mutual exclusion once sessions are not
human-supervised. Needs a slice; touches SPEC-001 (protocol) and ISS-050.
