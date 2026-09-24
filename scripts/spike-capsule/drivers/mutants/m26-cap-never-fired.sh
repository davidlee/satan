#!/usr/bin/env bash
# M26 — THE SANDBOX NEVER REPORTS THE BOUND.
#
# The capsule still exhausts its disk; only the status the sandbox hands back is
# cleared. Stage 1 therefore has nothing to refuse on and the pipeline runs on.
#
# Under test: `H7_assert`'s FIRST clause — the join between the sandbox's own
# verdict and the token stage 1 emitted. Without it the row would accept a
# `harvest/resource-cap` produced by any path the mapping happened to catch.
#
# THE MUTANT BOUNDS ITS OWN COST. Once harvest passes, the heavy cells run a
# real verify capsule (~400s each). The claim under test is that the harvest
# boundary MOVED, not where the run lands afterwards, so the verify timeout is
# cut to a value that refuses quickly. Stated here rather than absorbed
# silently: it is the only mutant in this sweep that touches a bound.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind pipeline_capsule
pipeline_capsule() {
  real_pipeline_capsule "$@"
  printf '0\n' >"$1/worker-status"
}

rebind fixture_verify_timeout
fixture_verify_timeout() { printf '20'; }
