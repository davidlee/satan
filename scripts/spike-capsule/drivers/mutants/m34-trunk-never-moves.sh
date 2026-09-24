#!/usr/bin/env bash
# M34 — TRUNK NEVER MOVES.
#
# Everything H16 does still happens — both candidates minted at B, both
# admitted — except the advance. The admitted close target therefore still
# fast-forwards, and integrate takes it.
#
# Under test: that the integrate clause is measuring STALENESS and not merely
# reporting that integration is hard. It is the pair to M35: this one removes
# the hazard, M35 keeps the hazard and moves it in time.
#
# The isolation control is `admit`: both admissions must still hold. They were
# never the thing that noticed, which is exactly the leg's finding — on this
# layer admission is indifferent to trunk, and only the CAS is not.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind conflict_move_trunk
conflict_move_trunk() { :; }
