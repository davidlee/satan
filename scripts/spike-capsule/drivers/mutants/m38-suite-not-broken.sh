#!/usr/bin/env bash
# M38 — GUARD (d) WITH AN HONEST SUITE.
#
# Everything guard (d) does still happens — both capsule-authored runners are
# planted, `audit-i4a` still refuses the mutated capsule — except that the
# module the test file imports is left intact, so `npm test` PASSES.
#
# Under test: the discrimination the leg is built on. With an honest suite the
# real runner and the planted one give the SAME answer (0), so the run ends in
# a pass and the leg observes nothing about I4a whatsoever. This is the mutant
# that falsifies the leg's design rather than one of its clauses: it is the run
# guard (d) would have been, had the broken suite been left out.
#
# THE ISOLATION CONTROLS ARE THE FINDING. `audit-i4a REFUSES the mutated
# capsule` and `the planted runner exits 0` BOTH still hold — the two clauses
# that look most like proof of I4a — while the guard was never exercised at all.
# Two green controls around a hollow observation is precisely the failure mode
# EX-3's per-cell positive control exists for, met here at the leg level.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

# Wrapped, not deleted: every OTHER plant this leg makes must still land, or the
# mutant would be perturbing the whole leg rather than the one thing under test.
rebind c3_plant_file
c3_plant_file() {
  [ "$2" = src/money.ts ] && return 0
  real_c3_plant_file "$@"
}
