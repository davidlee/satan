# Declare design-target selectors at design lock, not at audit

`slice conformance` reads only `design-target` selectors; declaring them late
leaves the drift signal inert for the slice's whole life, and the fix is the
registry verb, never prose.

## The mechanism

`doctrine slice conformance <id>` computes a three-cell algebra between what the
slice **declared** as `design-target` selectors and what git actually touched
(the recorded source-deltas):

- **undeclared** — edited but in no `design-target` selector
- **undelivered** — declared but matched no edit
- **conformant** — matched both ways

Selectors with intent `scope-relevant` are **not read** by conformance. They
describe what the slice may need to *look at*; `design-target` describes what it
intends to *change*. Registering the edit surface as `scope-relevant` looks
diligent and buys nothing.

## The failure it causes

SL-015 declared 2 `design-target` paths and edited 28. Conformance read
**2 conformant / 59 undeclared** for the slice's entire life — 28 legitimate
edits presenting as scope creep, buried in 31 rows of `.doctrine/**`
bookkeeping. Nothing was actually wrong, and nothing could have been detected if
it were: the one check that does not take a slice's word for its own scope had
no signal to give. Declaring the 28 at audit moved it to
**30 conformant / 0 undelivered / 31 undeclared** in one call.

For calibration, a well-declared slice looks like SL-013: 22 conformant, 12
undeclared. Residual `.doctrine/**` rows are the house tolerance — they are
workflow artefacts, not design targets.

## What to do

- Declare the intended edit surface when the **design locks**, from
  `design.md`'s own scope statement. It is the same list you just wrote in prose.
- Add to it as phases land and the surface turns out wider — appending is cheap;
  reconstructing it at audit is archaeology.
- `doctrine slice selector add <id> --intent design-target <globs…>`; globs work
  (`satan/*.el`), so the list is usually short.

## The trap when fixing it

A conformance finding is fixed by the **selector registry**, which lives in
`slice-NNN.toml` — not by editing design prose. Where a design template carries
a §6 selector mirror, that mirror is documentation; `slice conformance` never
reads it. Edit only the prose and conformance stays exactly as red as it was.

Related: [[mem.pattern.doctrine.conventions]], [[mem.signpost.doctrine.audit]].
