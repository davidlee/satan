# IMP-064: Tick gate on the existing S2 admittability predicate, with an every-Nth floor

## Origin

A discarded improvement card proposed designing a symbolic tick gate "from the
data" — new handles versus a recent baseline, changed handle set over the last N
ticks, any pattern firing. A cheaper predicate already ships.

## Shape

`satan-resonance--admittable-p` (`satan-resonance.el:46`) is exactly the card's
stage 3: at least one percept handle whose `rule_id` falls outside a closed,
ctx-only exclusion list. It is computed every tick already, and its `gate-skip`
status is an audited resonance outcome. So the gate is one call site before
`satan-broker-run`'s spawn branch — no new predicate, no new schema, no new sink.

Contracts to preserve:

- **Floor.** Run one tick in every N regardless of the predicate. A ctx-only
  percept means degraded sensing (`sensor_status` missing), and degraded sensing is
  precisely when `satan-sensor-alerts` matters — the percept currently in the state
  root carries only `day:`/`week:` handles, so an unfloored gate would suppress the
  ticks that notice the outage. This is the case the card missed.
- **Recorded decline.** Suppression uses the existing no-child shape — synthetic
  final + reason as the `run_busy` path does (`satan-broker.el:697-704`) plus a
  stamped `satan-trace-outcome` — so the decline is visible in the same artefacts
  IMP-063 reads. No new trace kind, and nothing written into `traces` (see ISS-064).
- **Never gate perceive.** `satan-run-perceive` runs before the gates by design
  (ISSUE-001 / `satan-broker.el:670-690`); it is cheap and is the gate's own input.
- **Kill switch** defcustom, house convention, and a suppress-path test.

## Gated by

IMP-063: measure first. If most ticks apply something, or spend is dominated by a
few modes, the economic case evaporates and this closes unimplemented. The daily
ceiling (`satan-budget-daily-tokens`, 2.5M) already bounds worst-case spend, so the
argument for a gate has to come from the measurement, not from arithmetic.
