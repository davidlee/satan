# IMP-057: satan-tank: recent-wakes section for malebolge wake fires and failures (SL-034 DEC-134)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Deferred from SL-034 (DEC-134). v0 reports a failed wake via a journal line and
a `notify_send` over the `scheduled` satan-mcp connection, which already shows in
satan-tank's RECENT EVENTS. A dedicated section listing recent wake fires and
failures needs a source: filter satan-mcp runs by identity kind `scheduled`, or a
read op on the malebolge daemon.
