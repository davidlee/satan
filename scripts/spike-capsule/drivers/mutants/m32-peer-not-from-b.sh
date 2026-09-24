#!/usr/bin/env bash
# M32 — CANONICAL'S HALF IS NOT FROM B.
#
# The pair still conflicts, on the same path, and `candidate create` still
# records `conflicted`. Only the PARENTAGE changes: an extra unrelated trunk
# commit lands first, so the peer's parent is that commit rather than the
# contracted base.
#
# Under test: `conflict_leg_H10`'s "child of B" clause. § 5.6 names H10 as a
# pair "from one base", and a peer parented anywhere would still produce a
# conflict — so without this clause the leg scores green while instantiating a
# row that is not H10. It is `c3_stale_planted`'s parentage clause, one layer
# down, and it is here for the same reason.
#
# The isolation control is the whole finding: the CLASSIFICATION must still
# hold. A mutant that reddened the conflict too would prove only that breaking
# the scenario breaks the leg.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind conflict_peer_half
conflict_peer_half() {
  conflict_commit "${CONFLICT_REPO}" 'docs/m32-unrelated.md' \
    'an unrelated trunk commit, so the peer is not a child of B' \
    'unrelated advance' "${C3_STALE_MARK}"
  real_conflict_peer_half "$@"
}
