#!/usr/bin/env bash
# M35 — THE MOVE HAPPENS BEFORE THE CANDIDATES PIN B.
#
# The trunk advance is not removed — it is brought FORWARD, to before
# `candidate create`. The candidates then pin the moved trunk as their base, the
# admitted close target fast-forwards, and integrate takes it.
#
# Under test: H16's ORDERING, which is the row's entire content. § 5.6 puts the
# advance "AFTER the contract pinned B and BEFORE admission"; getting that
# backwards is the mistake the pipeline leg's own comment says reds exactly
# there, and this is its sub-probe counterpart. A leg that asserted only "the
# trunk moved and integrate refused" would score green under this mutant, having
# observed a staleness that no longer exists.
#
# THE PAIR WITH M34, and the contrast is the point: M34 deletes the hazard, so
# the planted control reds. Here the hazard is intact — the trunk really did
# move, on the same disjoint path — so `planted?` is expected to HOLD while the
# refusal reds. Two mutants, two different clauses, and neither substitutes for
# the other.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

# Move it early: `conflict_stage_result` is the last thing to run before the leg
# mints its candidates, so wrapping it puts the advance on the near side of the
# pinning without restating either.
rebind conflict_stage_result
conflict_stage_result() {
  real_conflict_stage_result "$@"
  conflict_move_trunk
}

# … and neutralise the in-place move, so the scenario carries exactly ONE
# advance and the difference from a scored run is its POSITION, not its count.
rebind conflict_move_trunk
conflict_move_trunk_once=0
conflict_move_trunk() {
  [ "${conflict_move_trunk_once}" -eq 0 ] || return 0
  conflict_move_trunk_once=1
  real_conflict_move_trunk
}
