#!/usr/bin/env bash
# M33 — THE TWO HALVES AGREE.
#
# Canonical's half writes BYTE-IDENTICAL content to the capsule's, so the 3-way
# has nothing to reconcile: `candidate create` takes the merge cleanly and
# records `created`, not `conflicted`.
#
# Under test: the classification clause, and whether it MEASURES anything. A
# clause that read `conflicted` off a row which is always conflicted would be
# indistinguishable from one that worked — this is the run where the row is
# legitimately something else. It is H13's M6 lesson (an absence-shaped result
# proves nothing) applied to the ledger read.
#
# The `planted?` control is expected to red WITH it, and that is correct rather
# than sloppy: "the two halves disagree" is precisely the positive control for
# this perturbation, so a mutant that removed the conflict without reddening it
# would mean the control was not watching the conflict at all.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind conflict_peer_half
conflict_peer_half() {
  # `CONFLICT_RESULT_BODY`, not a copy of it: the two sides agree BY
  # CONSTRUCTION. A drifted literal would leave the conflict standing and the
  # mutant would score green having perturbed nothing.
  conflict_commit "${CONFLICT_REPO}" "$1" "${CONFLICT_RESULT_BODY}" \
    'peer lands the SAME content — nothing to reconcile' "${C3_STALE_MARK}"
}
