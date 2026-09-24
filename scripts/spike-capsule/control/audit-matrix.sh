#!/usr/bin/env bash
# control/audit-matrix.sh — the P-C3 matrix spec's own gate (PHASE-05 T2, EX-1).
#
#   usage: audit-matrix.sh [matrix.tsv]
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# `probes/c3/matrix.tsv` is an AUTHORED input, and the harness reads it as
# instructions. So a typo in it is not a bad row — it is the harness being told
# to expect something the pipeline can never emit, and the pipeline would call
# that a RIG DEFECT at run time, after the cell had already run. The defect
# would be attributed to the rig rather than to the file that has it.
#
# This runs the same checks BEFORE anything is provisioned, which is the only
# time they are cheap. The checks themselves live in lib/matrix.sh beside the
# reader, so the harness and this audit cannot disagree about what a row is.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=pipeline.sh
. "${RIG_DIR}/control/pipeline.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/matrix.sh
. "${RIG_DIR}/lib/matrix.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,5p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
esac

# I6 — first, as every entry point does, even though this one provisions
# nothing. A guard applied only where it currently matters is a guard that stops
# being applied.
rig_enter

file=${1:-$(matrix_path)}

printf 'audit-matrix: %s\n' "${file}"
matrix_validate "${file}"
printf '\n%s\n' "shape — what the file says it covers"
printf '  %s rows x %s fixtures x %s mechanisms = %s cells, of which %s are n/a up front\n' \
  "$(matrix_rows "${file}" | cut -f1 | sort -u | wc -l)" \
  "$(matrix_rows "${file}" | cut -f2 | sort -u | wc -l)" \
  "$(matrix_rows "${file}" | cut -f3 | sort -u | wc -l)" \
  "$(matrix_rows "${file}" | wc -l)" \
  "$(matrix_rows "${file}" | awk -F'\t' '$10 == "n/a"' | wc -l)"
matrix_rows "${file}" | awk -F'\t' '$10 == "n/a" { printf "  n/a  %s/%s/%s — %s\n", $1, $2, $3, $6 }' |
  sort -u

rig_assert_done "audit-matrix"
