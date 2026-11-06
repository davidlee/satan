# IMP-066: Replay/sandbox harness for prompt-effect trials (frozen tool results, deny-by-default capabilities)

## Gated by

`IMP-065` choosing **measure**. If exposure is removed or deliberately kept, this
item is moot and should be closed unimplemented.

## Why this exists

Any claim that a capsule block changes model behaviour needs a randomised
comparison, and a randomised comparison needs two runs that differ **only** in
that block. Byte-identical initial context is not sufficient: later `tool_result`
payloads are live reads, so the arms diverge from the second tool call onward
regardless of how identical the prompt was. Confounding is already present in the
live capsule, too — `# Attention` renders the raw focus/browser evidence
(`satan-percept.el:135-145`) that drives the very sensors behind the attribute
deltas, and `activity_read` scope="current" lets the model re-derive presence
mid-run (`satan-desktop.el:112-140`). So the trial must freeze tool results, not
just the prompt.

## Seams that already exist

- **One dispatch chokepoint:** `satan-tool-dispatch` (`satan-tools.el:165`) is the
  single place a tool call becomes a result, and the harness only ever sees a
  `tool_result` the broker sends (`docs/protocol.md`, `tool_call` field table).
  A stub there is indistinguishable to the model.
- **One side-effect guard:** `satan-tool--capability-denied-p`
  (`satan-tools.el:155-163`) reads `:capabilities` from the run-ctx that the mode
  spec supplies; effects are already refused by name (`:185`). A deny-by-default
  capability profile is therefore a mode-spec change, not new machinery.
- **Recorded material:** every run writes `transcript.jsonl` (in/out/broker events
  with payloads) plus a frozen `bundle.json` (`satan-audit.el:5-8`).
- **The render seam:** `satan-attribute-render-block` takes the snapshot as an
  argument (`satan-attribute-render.el:106-122`), so an arm can be withheld
  (`nil` → suppressed, `:117`) or fed controlled values with no DB involvement.

## What does not exist

- **No run replay or sandbox harness.** `rg replay` over `satan/` returns only
  domain rebuilds — intervention records, grammar renormalisation, patch-inbox
  reconnect, `desktop-at` — none of which re-drive a model.
- **No arm bookkeeping.** The bundle can carry the arm label (safe: `:prompt` is
  what the harness reads, other keys remain audit-only, `satan-context.el:462`),
  but nothing writes one today.
- **No capability profile for a read-only/no-side-effect run.**

## Scope

1. **Frozen tool results** at `satan-tool-dispatch`, served from a recorded
   transcript; effectful tools denied by capability profile.
2. **Divergence policy — preregistered, not blind.** Call ids are
   harness-chosen (`docs/protocol.md`), so matching by id is meaningless across
   arms. Pick one policy and record it: deny-with-structured-error for any call
   absent from the recording; serve by `(name, args)` match and deny otherwise;
   or serve read-only tools from a frozen snapshot at the recorded timestamp and
   deny effectful ones. **Divergence is treatment, not noise** — a model that
   diverges *because* the block moved it is the effect being measured — so the
   divergence rate must be reported alongside the outcome.
3. **Arm assignment: seeded and logged.** Same rule IMP-012 already imposes on
   its roll (`Math.random` / `Date.now` banned); write the arm to the bundle so
   the analysis can join it back.
4. **Replay artefacts outside `satan-runs-dir`.** `satan-budget-today-total` sums
   token usage across every run directory for today's prefix (`satan-budget.el:56-66`)
   and `satan-budget-exceeded-p` gates spawning on it (`:68-72`), so replay
   bundles in that tree would throttle live ticks with replay spend.
5. **Preregister the outcome variable.** Interventions are rare and the observer
   only classifies where one was made, so the measurable outcomes are tool
   choice, action counts, tokens and mode — not "did SATAN help". Fixing this is
   the real work; the plumbing is mechanical.

## Power, stated honestly

- **Live tick assignment:** 36 eligible ticks/day at the 40-minute cadence
  (ISS-022) → 252/week, so a 50:50 split is **≤ ~126/week/arm** before jitter,
  refusals (`run_busy`, budget) and no-signal ticks.
- **Offline replay:** a different, **supply-limited** quantity — bounded by the
  number of eligible recorded contexts, one full model call per replay, and
  budget. Not interchangeable with the live figure.
