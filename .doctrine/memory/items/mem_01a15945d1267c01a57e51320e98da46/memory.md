Facets are flags: `doctrine knowledge edit decision DEC-103 --context … --choice …
--alternatives a,b --rationale … --consequences a,b --decided-by … --decided-on YYYY-MM-DD`.
The bare id `103` is refused ("not a canonical record ref (expected e.g. ASM-007)").
Prose body is separate: `doctrine knowledge edit DEC-103 --body -`.
Lifecycle status is its own verb: `doctrine knowledge status DEC-103 accepted`.
`knowledge new` may print a reservation-degradation warning when the git remote is
unreachable (this checkout cannot exec git-ssh) and still creates the record locally.