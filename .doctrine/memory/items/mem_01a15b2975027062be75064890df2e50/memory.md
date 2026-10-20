`doctrine slice conformance <id>` computes its `undeclared` cell from the recorded
source-delta of each phase (`code_start..code_end`). A range is a commit interval,
not a claim about authorship: if another session committed into the same tree
between the two oids, its paths are attributed to this slice.

Seen at SL-029: PHASE-08's row `df71ab4..1a7a769` spans `2c1b98e`
("doctrine(SL-030): plan — seven phases"), so eight `.doctrine/**` paths from
SL-030 appear in SL-029's undeclared cell.

**Read the cell, don't act on it blindly.** Triage each entry: a foreign path is a
tenant of the interval, not scope creep. Confirm with `git log <start>..<end>` —
if the interval holds a commit whose message names another slice, that is the
cause.

**Narrowing the range is a falsification, not a repair.** Moving `code_start`
forward to exclude the foreign commit makes the row claim the phase began after
its predecessor ended — it understates the phase's own span and breaks the
contiguous chain. SL-029 did exactly that for PHASE-06 (start moved
`9879067` → `31afa50`) before the mechanism was understood; the honest disposition
for PHASE-08 was `tolerated` with the caveat recorded (RV-055 F-2).

If a clean cell is genuinely required, the repair is a delta representation that
can express an interleaved foreign commit — a doctrine change, not a slice one.

Related: `verify-vt` attribution is separately weak for files a slice touches but
whose modification the heuristic does not credit ([[mem.pattern.doctrine.vt-attribution-gap]]);
both symptoms share a root — the recorded delta, not the file tree, is what these
verbs read.