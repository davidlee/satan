#!/usr/bin/env bash
# M28 — THE CAPSULE DIED HOLDING NOTHING.
#
# The published ref and the bundle are removed after the capsule ran, so the
# capsule blew its bound WITHOUT leaving a harvestable result behind.
#
# THIS IS THE MUTANT THE ROW EXISTS TO SURVIVE. The refusal token, the boundary,
# the ingestion clause and the blast radius are ALL unchanged — a capsule that
# merely died is indistinguishable from one that died holding a valid result on
# every observable except `H7_assert`'s second clause. Without it the row would
# claim the cap arrived BEFORE ingestion while only ever having shown that there
# was nothing to ingest.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind H7_mutate
H7_mutate() {
  real_H7_mutate "$@"
  git -C "$(c3_capsule_repo "$1")" update-ref -d "${RIG_RESULT_REF}"
  rm -f -- "$1/capsule/${RIG_BUNDLE}"
}
