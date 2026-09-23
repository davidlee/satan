# ISS-022: SATAN tick timer is dormant: fires once 5 min after boot, never recurs

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Observed

During SL-018 PHASE-08 (2026-09-23) no tick fired after the one at boot+5min;
every tick for the live rollout had to be driven by hand
(`satan/bin/satan-run tick-pulse`).

## Cause

`~/flakes/modules/home/linux/satan.nix`, `systemd.user.timers.satan-tick`:

```nix
OnBootSec = "5min";
# OnUnitActiveSec = "30min";
# RandomizedDelaySec = "5min";
```

The comment above them still describes "then every 30 minutes with up to 5
minutes of jitter". The recurrence lines are commented out, and this was
already so when the file was created (flakes 947980c2), so git does not say
whether that was deliberate.

## Decide

Either restore the recurrence (uncomment both lines) or, if it was disabled on
purpose, fix the comment to say so. Before re-enabling, check the tick cost
budget (IMP-014) and that the SL-018 credential escalation is wanted at a
30-minute cadence.
