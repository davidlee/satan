# IMP-065: Capsule attribute exposure: decide measure / remove / keep

## Why this exists

The attribute bars are rendered into the system prompt of **every** mode: each
run's context fn ends in `satan-context--finalize-prompt`
(`satan-context.el:458-467`), which fetches the `satan_attributes` snapshot
(direct psql `SELECT … WHERE scope='global'`, `satan-attribute-render.el:45-67`)
and splices `satan-attribute-render-block` into the prompt
(`satan-context.el:416-417`; block at `satan-attribute-render.el:106-122`).

That is an exposure to the model that exists independently of whether anything
*acts* on the values — and nothing does: no gate, mode, budget or tick path
reads `satan_attributes` (see RFC-021 F8). So "declare the attribute layer
telemetry" does not settle the prompt: the bars stay unless someone removes
them.

This item is the decision, not the experiment. It exists so the third option
(deliberate exposure) is on the record rather than drift.

## The three options

| Option | Cost | What it settles |
|---|---|---|
| **Measure** | a slice: `IMP-066` (replay harness, frozen tool results, deny-by-default capabilities, preregistered outcome + divergence policy) | whether the exposure changes model behaviour |
| **Remove** | one branch — `satan-attribute-render-block` already suppresses on a nil snapshot (`satan-attribute-render.el:117`); the disabled marker at `:113-115` is the same seam | nothing about effect; simply stops the exposure |
| **Keep** | zero — but then say so in `capsule-contract.md` and stop relitigating | nothing; records intent |

## What is known, and what is not

- **Known:** the exposure is universal and unconditional for modes that render a
  capsule; the block self-suppresses on a DB failure, so a snapshot outage
  silently removes it (`:117`) — the model then sees no attributes at all with no
  marker, which is *not* the same signal as "disabled".
- **Known:** there is no measurement of effect, and no attribution path that could
  produce one: attributes are displayed, not acted on, so no intervention outcome
  carries information about them.
- **Not known:** whether the bars change tool choice, action volume or mode
  behaviour. Correlation is not available either — the capsule already carries
  the same upstream evidence elsewhere (`# Attention` renders raw focus/browser
  segments, `satan-percept.el:135-145`; the model can re-derive presence mid-run
  via `activity_read` scope="current", `satan-desktop.el:112-140`).

## Wanted

A decision, recorded on this item or as a contract amend:

1. **measure** → scope `IMP-066` and preregister its outcome variable;
2. **remove** → land the branch, update `capsule-contract.md` §2/§3, and note in
   `wiring-status.md` that the layer is no longer model-visible;
3. **keep** → a line in `capsule-contract.md` saying the exposure is deliberate
   and unmeasured, so the next reader does not re-open it as a bug.

## Notes

- Independent of RFC-021 O5a (scheduling authority: consumer vs telemetry).
  Telemetry answers O5a and leaves this open.
- Removing the block does not touch the daemon, the event log or the dispatcher;
  it is a broker-side render branch only.
- If removal is chosen, the `satan-tank` renderer (`satan-tank.el:186-198`) is the
  remaining reader — unwired, so nothing else needs changing.
