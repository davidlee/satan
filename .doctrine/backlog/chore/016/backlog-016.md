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

## Covered by SL-023 PHASE-12 (user ruling 2026-10-19)

PHASE-12 deploys the runner against the live `assistant` room instead of a
slot, so it covers these items live (PHASE-12 EX-6, EX-7, EX-10):

- one job end to end against `assistant`, `[door] kind = "room"`, repo
  `goad-walk`, result left in quarantine;
- reconnect after a room stop (`capsule assistant stop` / `start`): pause,
  then resume through a fresh `session`-launched daemon;
- push, collect and the probe (now a collect, design rev 63) run
  non-interactively as the runner user;
- a changed host key fails `host_key`, never a pause — the runner half only,
  through a scratch instance with a tampered copy of `known_hosts`.

Verified live on 2026-10-19: jobs pj-01M58KY5GCAV5RSCK8BN47TCDV (end to end, needs_review/complete) and pj-01M58KYQJ2AF6YXD2HYTX5KRM3 (stop/start reconnect, resumed and collected); non-interactive push/collect/probe ran as the runner user in both; the scratch changed-host-key instance failed as `host_key` with no waiting_room, real `known_hosts` unchanged. Evidence: SL-023 `notes.md`, PHASE-12 "Live evidence (VA-1, VA-2, VH-2) 2026-10-19".

Still deferred here:

- silence-limit drop on a frozen guest (pi-env 30 s `SILENCE_LIMIT_MS`) →
  pause;
- oubliette's own verbs refusing a changed host key (exit 1): exercising it
  live would mean editing the real `known_hosts`;
- the agent home being writable and executable (ASM-005's open caveat);
- the re-check of the room adapter at oubliette SL-006's lock.

## Closed per SL-023 user ruling 2026-10-19 (1)

The SL-023 closure run (jobs pj-01M58TKGY59Y8C10ZTWJ8V1D46 promoted,
pj-01M58TKGYN2G6HPJ9DM5763XD8 rejected, both against room `assistant`) plus
PHASE-12 cover the live room rung. The remaining items above (silence limit,
oubliette verbs' host-key refusal, agent home writable/executable) are waived
by the ruling. The re-check of the room adapter at oubliette SL-006's lock
stays OPEN: it lives in SL-023 `notes.md` Harvest `### Open` (an audit item).
