#!/usr/bin/env bash
# M31 — CANONICAL GAINS THE CAPSULE'S OBJECTS BEFORE THE REFUSAL.
#
# The deleted second hop (F-3), performed by hand against this row: canonical
# fetches the capsule's result with NO destination refspec, so its REFS are
# untouched and only its object database grows.
#
# Under test: `assert_outcome`'s object-count clause — which the matrix names as
# THIS ROW'S observable. On a stage-1 refusal nothing is ingested, so every
# other clause passes trivially and the object count is the only thing that can
# see a hostile capsule's objects landing in canonical anyway.
#
# The red lands OUTSIDE the row's own code, which is what the `also` shape
# exists for: the row cannot see this, and that is the point.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind pipeline_capsule
pipeline_capsule() {
  real_pipeline_capsule "$@"
  git -C "$1/canonical" fetch --no-tags --quiet -- \
    "$1/capsule/repo" "${RIG_RESULT_REF}" 2>/dev/null || true
}
