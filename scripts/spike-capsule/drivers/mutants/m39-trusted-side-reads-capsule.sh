#!/usr/bin/env bash
# M39 — THE CONTROL PLANE READS THE CAPSULE'S DECLARATION.
#
# The defect QUE-201 is actually worried about, injected at the read rather than
# argued about. `contract_field … verify` — the single place the trusted side
# resolves the command it will run — is rebound to prefer the capsule's own
# in-repo copy whenever one exists.
#
# Under test: whether guard (e)'s comparison can SEE a control plane that made
# this mistake. A byte-identical result is only evidence if the comparison would
# have been unequal under the substitution; this mutant is the run that makes it
# unequal.
#
# THE ISOLATION CONTROL IS THE F1 BASELINE, and it is exact rather than
# incidental: F1 keeps its declaration outside the clone, so `${copy}` does not
# exist, the wrapper falls through, and the baseline leg is byte-identical to an
# unmutated run. The mutant therefore perturbs ONLY the fixture that
# manufactures the exposure — which is what makes the reds on the F2 legs
# attributable to the substitution and not to the overlay being loaded at all.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind contract_field
contract_field() {
  local run=$1 field=$2 copy
  if [ "${field}" = verify ]; then
    copy="${run}/capsule/repo/interpretation-surface.txt"
    if [ -f "${copy}" ]; then
      declaration_field "${copy}" verify
      return 0
    fi
  fi
  real_contract_field "${run}" "${field}"
}
