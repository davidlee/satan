#!/usr/bin/env bash
# M36 — A SECOND GOVERNANCE PATH IN GUARD (b)'S RANGE.
#
# The leg still plants its non-ASCII path and the pipeline still refuses. What
# changes is that a PLAIN governance path rides along in the same commit, which
# is exactly the shape H5 already scores and exactly what D-P05-10 ruled guard
# (b) must not be.
#
# Under test: `guards_assert_isolated`. Conform leg 3 returns on the FIRST
# matching path, so with two forms in the range the refusal is about whichever
# git listed first — and the TOKEN CANNOT SAY WHICH. That is the finding this
# mutant exists to make visible: the boundary clause holds green throughout,
# so without the isolation count guard (b) would be a second, differently-named
# run of H5 (F-P05-22).
#
# The isolation controls are therefore the refusal itself and the ingestion
# clause: both still hold, and both would have scored this run as a clean
# observation of the non-ASCII form.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

# `c3_commit` rather than `c3_plant_file`, so ONE wrapper carries both halves of
# the perturbation: a planted file that is never staged is not in the range at
# all, and the mutant would be wrapping nothing that matters.
rebind c3_commit
c3_commit() {
  local run=$1 message=$2
  shift 2
  c3_plant_file "${run}" "${C3_H5_PLAIN}"
  real_c3_commit "${run}" "${message}" "$@" "${C3_H5_PLAIN}"
}
