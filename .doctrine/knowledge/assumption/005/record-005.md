# ASM-005: Oubliette SL-005 pins the room door as Plan F §5 sketches: agent user, runner key in the room declaration, unix-socket relay

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Settled 2026-10-18 — validated, from oubliette SL-005 (design sec-6 relay)

Oubliette SL-005 pins the door as sketched (oubliette DEC-037):

- Door: unix socket `/run/capsule-room/<room>/ssh.sock`, distinct from the capsule relay.
- Login `agent@<net.guest>` through `ProxyCommand`; `HostKeyAlias` with strict
  host-key checking (host keys stable for the volume's life).
- Runner key in the room declaration: a room user is `{ uid; keys; }` (see the
  uid constraint recorded alongside).

Caveat: the relay does not state that the agent home is writable and
executable; confirm against SL-005's locked design when the room adapter is built.

Also from the relay, for SL-023's design (not this record):
- `guest_path` is the oubliette target's `guestPath`, not runner config; the
  room git channel is a follow-on oubliette slice (ISS-021).
- No land verb: promotion is a plain `git fetch` from
  `/var/lib/capsule/collect/<room>/<target>.git` (oubliette DEC-040; DEC-061).
- A stop is a reboot through the stop key that cuts in-flight work, not graceful.
