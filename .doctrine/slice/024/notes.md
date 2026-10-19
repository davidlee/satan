# Notes SL-024: malebolge: advertise Agent Skills in the system prompt

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Review continuation

Critical reading recorded on RV-028. The design document was left unchanged.
An additional pass would be useful after responses are integrated: check that
the compatibility claims match the resulting parsing/loading contract and that
the deployment assertion can reject an incorrect skill suffix. A broader
architectural pass is not warranted by the current scope.

Review artifacts are uncommitted; this session did not land a commit. No code
changed, and no implementation gate or live deployment verification was run.

### After integration (design-run rev 26)

F-1..F-3 integrated into sec-4/6/7 and disposed `fix-now` on RV-028
(F-3 partial: `SKILL.md` asserted, bundled reference files not). A further
pass would probe exactly the continuation above: parsing predicates and
duplicate rules against pi `skills.ts:120,320,420-455`, and the
`malebolge-jail-profile` negative control. The user waived that pass on
2026-10-19 ("reviewed, let's lock and plan"); the raiser's verification of
the three answers stays open on RV-028 and is not a lock blocker (all minor).
Both probes are VT rows in sec-6, so implementation exercises them.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-19 · ready · b616a58

### Produced

- Scope, research, locked design (run dr-01a151c7), plan + 3 phase sheets (commit b616a58). No code yet.
- RV-028 — GPT design review; F-1..F-3 integrated into design §4/6/7.

### Learned

- Nothing new for memory; handover-era nix facts superseded by CHR-018 (recorded in slice-024.md Context).

### Open

- RV-028 — raiser verification of F-1..F-3 answers outstanding (minor; not a lock blocker).
- DEC-066 — yaml parser; DEC-067 — read once at startup (both shape PHASE-01/02).
