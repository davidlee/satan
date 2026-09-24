#!/usr/bin/env bash
# M27 — THE OVERSIZE IS NOT EMPTY.
#
# A byte is appended to the blob trusted-side, after the capsule has already
# taken SIGXFSZ. Everything about the refusal is unchanged; only the artifact
# the row reads no longer carries the signature of a REFUSED write.
#
# Under test: `H7_planted`'s zero-length half. A row that checked only for the
# blob's PRESENCE would score a completed oversize — a write the bound let
# through — identically to one the bound refused.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind H7_mutate
H7_mutate() {
  real_H7_mutate "$@"
  printf 'x' >>"$(c3_h7_blob "$1")"
}
