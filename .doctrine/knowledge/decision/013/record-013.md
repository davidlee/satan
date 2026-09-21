# Two sources for one question

The keystone asks: *did the keeper engage with what SATAN put in front of them?*
There were always two places to look.

| | focus telemetry | goad's own record |
|---|---|---|
| what it is | where attention was, inferred from compositor segments | what happened to each question, written by the thing that asked it |
| delivery | cannot say — never sees the prompt | `presented_at`, written at render |
| engagement | any focus segment, unnarrowed by surface | the answer itself |
| deferral | indistinguishable from any other focus | the keeper's own `Later` |
| non-engagement | absence of a segment — also absence of the keeper | presented, unanswered, slot elapsed |
| depends on | panopticon, compositor behaviour, retention policy, ISS-014 | one file SATAN already reads |

The first design chose the left column because `"ask"` was already a member of
`satan-observer-user-facing-kinds` and the negative path appeared to come free.
It did not come free; it came broken, and RV-007 found three independent reasons.

## What the reframe actually removes

- **ISS-014** — `satan-observer--ack-checked-p` compares the symbol `'ok` to the
  string `"ok"` and is nil on every production run. Not this slice's problem any
  more.
- **Segment eviction** — only the newest ten segments survive assembly, so an
  early goad focus can vanish before maturity.
- **The strictly-after-emit boundary** — a keeper continuously focused from
  before the emit counts as absent.
- **`app_id` mislabelling** — real telemetry carries `app_id:"goad"` against
  Emacs and Claude window titles.
- **The self-focus unknown (F-17)** — whether `window.show()` focuses the window
  is no longer a question anything depends on.
- **`goad-emit` exit 0 as delivery proof (F-1)** — goad replies `accepted`
  *before* calling the backend (`controller.rs:735`), so exit 0 never meant what
  the first design read into it.

## What it costs

The backend carries the slice now. Four changes, all in `~/satan/goad/backend.py`,
none optional, against a file with no tests:

1. **`presented_at`** written when an item is actually rendered. This is the
   delivery proof, and it can only be written by something that ran.
2. **Priority in `pending()`** — `main()` renders only `waiting[0]`, and
   `pending()` returns `ITEMS` order behind fourteen checklist entries (F-18).
   Merging without prioritising means never being asked.
3. **Deferral provenance** — `answer()` writes the same `deferred_at` for
   `later:` and `enough:` (F-19). For this slice those are opposite signals, and
   `enough:` can defer an ask the keeper never saw.
4. **Serialize queued items** — `save()` iterates `ITEMS` alone (F-7), so a
   SATAN answer would render, mutate the in-memory map, and vanish on write.

## The shape of the signal

```
ask emitted ──▶ queue.json ──▶ backend prioritises ──▶ goad renders
                                                          │
                                              backend writes presented_at
                                                          │
                     ┌────────────────────────────────────┼─────────────────┐
                 answered                            Later (explicit)    nothing,
              value + at                          deferred_at + provenance  slot elapsed
                     │                                    │                  │
                     ▼                                    ▼                  ▼
            predicate fires                        engaged, unanswered   NON-ENGAGEMENT
               :worked                                  :unknown           the keystone
```

Every branch is a fact in one file, written by the process that asked the
question. Nothing is inferred from where the keeper's eyes were.

## What it does not fix

Correlation. A goad-derived predicate still runs inside
`satan-observer-classify`, which still sits behind
`satan-observer-classify-for-motives`, so motive correlation remains the outer
gate on every classification. [[RV-007]] F-4 (the motive-mutation race) and F-5
(the gate correlates ambient percept, not the question) survive the reframe
untouched and are fixed separately — see the revised [[DEC-007]].
