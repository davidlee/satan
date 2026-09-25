`doctrine slice record-delta <ID> <PHASE> --start A --end B` UPSERTs a boundary
row into `.doctrine/state/slice/<NNN>/boundaries.toml`. `doctrine slice
conformance` computes the phase deltas from those rows, so a row with
`code_start_oid == code_end_oid` (a no-op range) silently contributes **nothing**
— while the phase still reads `completed`. The registry is "complete" as far as
conformance is concerned, so there is no refusal and no warning.

That is how a conformance pass can be true by accident: if a *later* phase
happens to re-touch the earlier phase's selectors (an audit or defect fix), the
selectors still come out `conformant`, and the missing delta is invisible.

Check the range, not the status:

    cat .doctrine/state/slice/NNN/boundaries.toml      # start != end for a real phase
    git diff --name-only <start>..<end>                # must be non-empty

Repair with the raw escape hatch (the `--commit` mode records exactly one
commit's own patch and refuses to narrow a known span; `--start/--end` names
both ends deliberately):

    doctrine slice record-delta NNN PHASE-01 --start <pre-work tip> --end <phase close tip>

Tile the ranges (`phase1.end == phase2.start`) so no commit falls between. Found
by the SL-020 audit (RV-020 F-1), where PHASE-01's row was `217ecee..217ecee`
and the conformance verdict rested entirely on PHASE-02's overlap. Related:
[[mem.pattern.doctrine.declare-design-target-selectors-at-design-lock]].


Key check: `[[mem.pattern.doctrine.declare-design-targets-at-lock]]` — the
selector registry is the other half of the same question; a slice can be
selector-correct and boundary-blind at once.
