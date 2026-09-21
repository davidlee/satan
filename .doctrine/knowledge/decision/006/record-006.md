## Correcting research delta 9

Delta 9 reads: *"`tick-pulse` cannot ring the doorbell today. Its capabilities are `'(stage-proposal hippocampus-write)` — no `notify`, no `inbox-write`."* The cited site, `satan/satan-mode.el:146-154`, is the `self-edit-mech` registration.

tick-pulse is not registered in `satan-mode.el` at all. It comes from `satan/satan-tick.el:95`:

```elisp
;; Default registration: a single lightweight pulse tick.
(satan-tick-register "pulse")
```

which takes `satan-tick-register`'s defaults (`:60-88`):

```elisp
:tools '("org_read_context" "notify_send" "inbox_append"
         "activity_read" "notes_recent"
         "sway_border_set" "sway_border_reset"
         "memory_mark" "memory_resonate" "memory_show_trace"
         "motive_read" "motive_replace"
         "vcs_log")
:capabilities '(notify inbox-write memory-write motive-write)
```

So tick-pulse already holds both capabilities delta 9 says it lacks, and already ships `notify_send` and `inbox_append` as tools. D1 never blocked the autonomous producer.

## What the correction hands the slice

`motive-write`, `motive_read` and `motive_replace` are in the same mode. Whatever inq-1 decides about checking for a correlating motive before emitting an ask, the mode that emits has the motive surface in reach. The correlation gate can be enforced where the ask is made rather than discovered thirty minutes later as `:no_correlation`.

## The hazard the correction exposes

```elisp
(defcustom satan-tick-quiet-hours nil ; was '(22 . 7); disabled while iterating
```

Quiet hours are off. A single systemd timer fires the broker every ~30 minutes and nothing suppresses the night. Today that is harmless: every tick surface is ambient — a sway border, an inbox line, an org block. A doorbell is not ambient; it draws a window.

RFC-016 diagnoses SATAN's dormancy as an attention-economy failure. A slice that answers it by earning the right to interrupt, and then interrupts at 3am, spends the attention it was built to conserve. Restoring the window belongs in this slice.

## Why a distinct capability

SPEC-001 REQ-005/010 want the surface to fail closed and be killable. Reusing `notify` gives one switch for two behaviours: turning off goad would silence all notification, and re-enabling notification would silently re-arm goad. A `goad-ask` capability plus a `satan-goad-enabled` defcustom (the governed idiom, authority-ledger row 6) keeps the two independent.

## Amendment — a goad-specific window, not global quiet hours (RV-007 F-15)

The hazard this record identified is real and unchanged: a doorbell on a
round-the-clock ~30-minute tick can ring at 3am, and shipping it without a window
spends exactly the attention the slice exists to conserve.

The proposed remedy was wrong. `satan-tick-quiet-hours` is consulted by
`satan-tick` **before any mode is selected** (`satan/satan-tick.el:124`), so
restoring it would suppress the entire tick overnight — observer processing,
memory work, inbox work, every other tick behaviour — none of which this slice
has any business changing. That is scope creep dressed as a safety control.

The contained solution is a **goad-specific emission window** owned by the ask
path, which stops the doorbell without touching global scheduling.