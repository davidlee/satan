# IMP-027: Bound open goad asks if live use shows checklist starvation

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

RV-017 F-2 (SL-016 second-pass review). Deferred deliberately (user,
2026-09-24): ship unbounded, judge from live use, tune only if it annoys.

```
tick (~30 min, ≤10 calls) ──goad_ask──▶ queue ──▶ backend.pending() = [asks…, checklist…]
                                                         │
                                                         ▼
                                                 run() renders still[0] only
```

- `satan-tool/goad-ask` checks neither the number of open asks nor whether
  the subject already has one open.
- `pending()` puts asks first on purpose (RV-007 F-18): behind the checklist
  an ask would never be seen. goad renders one view at a time, so an open ask
  hides the checklist until the keeper answers it or taps Later/Enough.
- Asks queued behind the visible one mature `undelivered` — truthful, but
  each rang the doorbell.

## Symptoms to watch for

- The daily checklist rarely gets its turn.
- Several asks per tick; `undelivered` verdicts on asks queued behind the
  visible one.
- A new ask arriving right after the keeper tapped Later.

## Options when it needs tuning

| policy | bound | cost |
|---|---|---|
| one open at a time | ~1/hour 09:00–22:00 (60-min window) | one check in the tool |
| one per subject | none on the checklist | little protection |
| one open + daily cap (defcustom) | N/day | new tunable |
| minimum gap after a verdict | ~24h / gap | tunable; overlaps attribute pacing |

Implement as a **refusal** (`error`, nothing recorded), not a suppression:
asking while `app:goad` is in the percept is the model misreading its own
percept, not an organism condition — no attrd reason needed. Reuse canon's
outstanding-ask predicate (`satan-memory-canon--goad-outstanding-p`, shared
with the tool since RV-017 F-5).

**Later-deferred asks — open question, same permissive default.** A Later
leaves the ask outstanding (SL-016 OQ-1). Under a cap, counting it blocks a
new ask for the rest of its window (honours "later"); not counting it lets
SATAN ask something else straight after being told "later". Current
choice: no cap, so moot; decide alongside the cap.
