# ISS-014: Observer ack gate is always false: sensor_status :focus is a string, compared with eq to a symbol

Found by an adversarial review of SL-016's design (GPT / gpt-5.6-sol), then
confirmed by direct read. **This is a live misclassification bug, independent of
SL-016.**

## The defect

`satan-memory-evidence--segments-status` returns a **string** status —
`"ok"` / `"stale-Nm"` / `"missing"` / `"malformed"` — and its docstring says so
outright: *"STATUS is the JSON-friendly string `\"ok\"` …"*
(`satan/satan-memory-evidence.el:163-190`). That value reaches
`:sensor_status → :focus` verbatim (`:555`, `(car focus-probe)`).

`satan-observer--ack-checked-p` compares it to a **symbol**:

```elisp
(defun satan-observer--ack-checked-p (after)
  (eq 'ok (plist-get (plist-get after :sensor_status) :focus)))
```
`satan/satan-observer-classify.el:271-277`

```
$ emacs --batch --eval '(princ (format "%S" (eq (quote ok) "ok")))'
nil
```

So `--ack-checked-p` returns nil **for every production run**.

## Blast radius

In `satan-observer-classify-negative` (`satan/satan-observer-classify.el:326-345`):

```elisp
(let* ((checked (satan-observer--ack-checked-p after))
       (found (if checked (satan-observer--count-ack-events after intervention) 0)))
  (cond
   ((and checked (> found 0))   ; ← unreachable
    (list :classification :unknown :confidence :low ...))
   (t
    (list :classification :ignored
          :confidence (if checked :medium :low) ...))))
```

With `checked` always nil:

- the `:unknown` branch is **unreachable**;
- `found` is hard-wired to 0, so `satan-observer--count-ack-events` never runs;
- **every user-facing intervention that fires no positive predicate classifies
  `:ignored :low`** — unconditionally, whatever the keeper actually did;
- confidence is never `:medium`, so the `:medium` arm is also dead.

The recorded `:evidence` plist is correspondingly misleading: it reports
`:acknowledgement-checked :false` and `:ack-events-found 0` on every row, which
reads as "we could not check" rather than "we had the data and did not look".

Non-user-facing kinds take the `:neutral` branch and are unaffected.

## Why the tests do not catch it

`satan/test/satan-observer-test.el:682` constructs the status as the **symbol**
`'ok` by hand, so the fixture disagrees with what the assembler actually
produces. The test passes; production does not behave as tested. Same shape as
[[mem.fact.satan.green-is-not-green]] — a check that cannot fail is not a check.

## Fix sketch

Compare against the string, or normalise at the boundary. Prefer normalising
once where the evidence plist is built rather than string-comparing at every
consumer, and **pin the fixture to the assembler's own output** so the two
cannot drift again — a test that builds its own status value is the thing that
hid this.

Check the other `:sensor_status` consumers for the same mismatch before fixing;
`satan-sensor-alerts.el` reads the same table.

## Relation to SL-016

Prerequisite for SL-016's negative leg. [[DEC-012]] narrows ack-event counting
by target surface so `:ignored` means *ignoring* rather than *absent* — but
narrowing a count that is never taken changes nothing while this bug stands.
SL-016's design §6 also describes a "today" behaviour (`:ignored` requires zero
focus segments, so it means the keeper was away) that is **not** the current
behaviour; the truth table needs correcting once this is fixed.
