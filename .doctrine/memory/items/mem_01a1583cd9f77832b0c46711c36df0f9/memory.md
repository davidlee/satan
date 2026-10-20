# Nested jails are additive, never narrowing

An unjailed process inside a jail is jailed; a jailed process inside a jail gets the union of both jails. A nested jail can therefore never repair an outer profile's exposure, so the outer profile remains the containing guarantee and 'nested' never implies 'narrower'.
