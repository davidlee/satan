# REV REV-002 — reconcile SL-017

Revision (ADR-013) — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

SL-017 made `satan-announce` the one emit seam and put every intervention
record before its emit. Two emits stay outside the audit log by design
(SL-017 design, "Emits that are not interventions: operational alarms").
Without a standing note, a later audit reads them as unrecorded writers
against ADR-017 authority-ledger row 4 (append-only audit, single writer
`satan-audit-record`).

## Reconcile narrative (SL-017)

- [RV-011 F-13] ADR-017 `authority-ledger.md`, Standing notes, row 4: append
  a paragraph naming the two operational alarms (failure announcements;
  listener death reports) as non-intervention emits. Neither is an audit
  writer, so row 4 stays single-writer.
- [RV-011 F-11] REQ-003: no change. SL-017 covers the notify path only;
  record before side effect for sway / inbox / proposal / patch is SL-017
  PHASE-08 EX-2's backlog item. Status stays `pending`.

## Before / after (ADR-017 authority-ledger.md, Standing notes)

Before: the row 4 note covers only the latent dual-write
(`satan-audit-record` + the attribute bridge).

After: the same note, followed by:

> **Row 4 — operational alarms are not audit writers (SL-017).** Two emits
> report SATAN's own state rather than act on the keeper's world, and neither
> appends audit. **Failure announcements**
> (`satan-broker--announce-failure`) fire after `satan-audit-close` and the
> `.FAILED` rename; the run bundle (`status`, `final.json`, transcript,
> `crash-context`) is their record, and the pop decision is derived from it.
> **Listener death reports** (`satan-attribute-listener--report-death`,
> `satan-patch-listener--report-death`) happen outside any run, with no audit
> handle; their `:journal` line is the only durable trace. Recording them would
> need a third audit writer, which this row forbids. Both emit only through
> `satan-announce`.
