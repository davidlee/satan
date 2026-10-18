# CHR-016: SL-023 live room rung: runner against a real oubliette room once SL-006 ships

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Deferred live verification of SL-023's room adapter and door kind (DEC-065).
Not a closure gate for SL-023 (design §9 closure evidence: the room adapter's
fixture tests are green; the live room rung is not closure evidence while
oubliette SL-006 is unshipped). The slot stays the live rung until then.

**Waits on:** oubliette SL-006 (room git channel and `session` launcher)
shipping. Before running, re-check the room adapter against SL-006 at its lock
(design §6 "SL-006 lock drift"; §8 risks).

**Env-gated, not in `just check`.** Covers (design §9, "Live room rung"):

- one job end to end against a room, `[door] kind = "room"`;
- reconnect after a room stop: pause, `capsule <room> start`, resume through a
  fresh `session`-launched daemon;
- silence-limit drop on a frozen guest (pi-env 30 s `SILENCE_LIMIT_MS`) → pause;
- a changed host key on reconnect fails as `host_key`, never a pause, and
  oubliette's verbs refuse it too (exit 1);
- push, collect and the probe run non-interactively as the runner user (the
  oubliette module owner's default key, CON-003/CON-004);
- the agent home is writable and executable (ASM-005's open caveat).

Deployment facts it needs in `~/flakes` / `SATAN.md`: runner config rendered
from the oubliette target/room attrsets; door `ssh_config` (`ProxyCommand`,
`ServerAliveCountMax`); satan's key and the module owner's default key in the
room user's `{ uid; keys; }`.
