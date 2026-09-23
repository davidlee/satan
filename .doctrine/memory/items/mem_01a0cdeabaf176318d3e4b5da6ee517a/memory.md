Bough (the old org-graph integration) is **deprecated and, per the keeper, inactive**
(stated in the SL-016 design session, 2026-09-23). Bough derivation was ended in
SL-002 PHASE-05 (`c7e6ece`); inquisition RV-001 covered removing the integration.

Residue that still *looks* live:

- `satan-motive--admitted-namespaces` (`satan/satan-motive.el`) still admits
  `bough_event`, `bough_node`, `bough_project`. A motive may cue on them and
  parse valid, but nothing live emits those handles, so such a cue never
  correlates.
- The SATAN orientation signpost still lists `satan-tools-bough.el` among tool
  modules.

**How to apply:** never pick a `bough_*` handle as an example subject, cue or
correlation anchor. Use `app:`, `surface:`, `domain_kind:`, `artifact:`,
`phase:`, `focal_app:`. Verify against current canon rules before relying on
any namespace being emitted.
