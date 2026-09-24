#!/usr/bin/env bash
# M29 — THE PATHOLOGICAL TREE NEVER LANDED.
#
# The blob and the refusal are untouched; only the row's SECOND vector is
# removed. Under test: `H7_planted`'s depth clause, and with it the matrix's
# claim that this row plants two things rather than one.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind H7_mutate
H7_mutate() {
  real_H7_mutate "$@"
  rm -rf -- "$(c3_h7_deep "$1")"
}
