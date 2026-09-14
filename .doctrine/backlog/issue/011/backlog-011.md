# ISS-011: satan-attrd rejects sensor outcome reason content_backlog

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`satan-attrd` logs, on every tick since at least 2026-09-11 (22× in 3 days):

    ERROR satan_attrd::run_loop: outcome inbox: parse failed
      error=reason: invalid reason for source=sensor: content_backlog id=1679

The broker enqueues a sensor outcome with reason `content_backlog`; attrd's
reason validation for `source=sensor` does not accept it, so the outcome row is
dropped. Compare the broker-side reason set (`satan-sensor-content.el:122`,
`:reason "content_backlog"`) with attrd's allowlist — one side drifted.

Seen during SL-015 PHASE-03 T18 (journal around tick
`20260914T125539-tick-pulse-c3dce4`); unrelated to the corpus move.
