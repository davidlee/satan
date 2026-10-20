# IDE-014: Self-paced ticks: SATAN sets when the next tick runs, inside host-enforced bounds

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

User idea, 2026-10-20, prompted by ISS-022 (the `satan-tick` timer fires once
at boot+5min and never recurs). Instead of a fixed cadence, the persistent
session "sets the dial", or each tick decides when the next one runs.

## Shape

```
 tick N ends ──▶ tick_schedule(next_in, reason)   ; model proposes
                   │
                   ▼ host clamps to [floor, ceiling]; budget gate
                 systemd-run --user --on-active=<clamped> satan-run tick-pulse
                   │                      (one transient unit, replaced each time)
 fallback:       satan-tick.timer at the ceiling = heartbeat if no proposal
```

- **The model proposes, the host disposes.** Cadence drives spend, so the
  bounds (floor, ceiling, daily token budget, quiet hours) stay host-side
  authority items (ADR-017). The model never edits its own clamp.
- **The heartbeat is not optional.** A model that schedules nothing, or
  crashes, still gets a tick at the ceiling. ISS-022's fix (restore
  recurrence) becomes this heartbeat.
- **Proposals are recorded.** Each requested and clamped interval plus its
  reason goes to the run's audit, so cadence choices can be reviewed later.

## Variants

1. Per-tick: each tick's last act is `tick_schedule`. Simple; stateless.
2. Session dial: the durable session (malebolge, IDE-009) holds a standing
   cadence and changes it rarely. Needs modes-as-events first.
3. Stochastic gate: IMP-012 (attributes decide arrival, integrate-and-fire).
   Here the model chooses the interval; there attributes do. They can
   compose: the model sets a base rate, attributes modulate it.

## Open

- Floor and ceiling values; whether quiet hours override a proposal.
- Interaction with IMP-014 (tick perf / budget-breach alert) and SL-018's
  credential escalation at higher cadence.
- Whether tick-pulse (cheap) and tick-agent (expensive) are scheduled
  separately (`satan-tick-pool`).

Related: ISS-022, IMP-012, IMP-014, IDE-009, RFC-016, ADR-017.
