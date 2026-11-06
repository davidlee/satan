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

## Mechanism (added 2026-11-06, RFC-021 F1)

The loss is irreversible, and not only because the row is deleted. Two halves:

1. **Daemon side.** `process_outcome_row` claims the row (`claimed_at`), fails
   `parse_inbox_payload`, then calls `delete_outcome_row` and returns Ok
   (`satan-attrd/src/run_loop.rs:527-548`). Same path for a `schema_version`
   major mismatch (`:540`). Nothing durable records the rejection; the only
   trace is one journald line.
2. **Broker side.** `satan-sensor-content-probe-commit` enqueues the payload and
   then advances the probe watermark to the snapshot's high-water — on *enqueue*,
   not on acknowledgement. A rejected event therefore consumes the evidence it
   carried: the next probe sees nothing new.

Consequence: "no events today" and "every event was rejected today" are
indistinguishable from the database (see RFC-021 F2/F3 and `ISS-063`'s sibling
problem: a reader over successful events reports health).

## Wanted (generalised)

**Immediate mitigation, no code (2026-11-06).** Set `satan-sensor-content-enabled` to
nil. The probe then does nothing — no enqueue *and* no watermark advance, because
`satan-sensor-content-probe-commit` advances only when the snapshot says `:emit`. The
backlog accumulates in `articles.jsonl` and will be emitted whole (at full count) once
the daemon accepts the reason. This stops the destruction without losing the evidence;
it costs timeliness only. Verified: panopticon prunes `raw/` and `segments/` only,
never `content/` (`panopticon/segmentizer/retention.py`; its README: "Extracted content
and digests — No automatic retention yet"), so a deferred backlog survives. Do **not**
stop emitting while letting the watermark advance —
that is the same loss moved to the broker, and remapping to `segment_backlog` is not
equivalent (different stream, different metric, different watermark; see the RFC-021
§5 item 1 comparison).

Beyond adding the missing reason to one side:

- Decide **which side owns the reason vocabulary** — the broker emits, so it
  should either consult a daemon-advertised set (RFC-021 O2) or the daemon should
  store unknown `(source, reason)` pairs opaquely instead of deleting them
  (RFC-021 O1).
- Adopt the **advance-on-acknowledgement rule** for every broker probe watermark:
  advance on enqueue only where the sink cannot reject. `satan-sensor-content`,
  the keyrate sensors and the curiosity sensor all advance through the same
  commit path, so the rule is one fix, not one per sensor.
- If the reason is simply added to attrd: it needs a §6S delta row (a
  design-contract amend), and the magnitude should follow `segment_backlog`'s
  partial-satisfaction reading rather than being invented.

## Implementation

`SL-037` takes both halves in one act: a broker-side gate so an unsupported
`(source, reason)` is *held* (no enqueue, no watermark advance, a visible hold record with a
reader) instead of enqueued-and-deleted, then the daemon-side `ContentBacklog` reason plus
the `§6S.1`/`§6S.2` contract rows. O1's general machinery stays out of scope by design.
