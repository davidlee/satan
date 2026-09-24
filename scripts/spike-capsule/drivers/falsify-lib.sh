#!/usr/bin/env bash
# drivers/falsify-lib.sh — the falsifiability round's scaffolding (SL-241 T4).
# SOURCED by drivers/falsify-<task>.sh, never executed.
#
# ── why this is COMMITTED ───────────────────────────────────────────────────
#
# It was not, through T4a–T4e, and the cost landed in this session: the sweeps
# for four scored tasks were cited by path in a handover and none of the drivers
# existed anywhere on the filesystem (F-P05-39). A falsification claim whose
# driver cannot be re-run is prose. These live in the rig, beside the rows they
# perturb.
#
# ── the shape ───────────────────────────────────────────────────────────────
#
# A mutant is a FILE OF REBINDS, loaded into a real `rig c3 <row>` run through
# the `SPIKE_C3_MUTANT` overlay. The whole harness runs; only the named function
# is wrapped. Nothing here drives cells itself — a driver that reimplemented the
# cell loop would be falsifying its own copy of the harness, which is the exact
# error the wrapping discipline exists to prevent.
#
#   MUTANTS WRAP, THEY DO NOT RESTATE. `rebind` renames the original to
#   `real_<name>`; the mutant defines `<name>` to perturb and then call through.
#   A restated body proves the copy was broken; a wrapper proves the SUBJECT
#   was. (mem.pattern.tests.invert-ordering-by-wrapping)
#
# ── the three expectations, and the isolation control ───────────────────────
#
# Every mutant asserts TWO things, never one. The red says a clause noticed; the
# ISOLATION CONTROL says what still held — and the finding usually lives there,
# because a mutant that reds everything has shown nothing about which clause is
# load-bearing.
set -euo pipefail

FX_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
FX_RIG="${FX_DIR}/.."
FX_ROOT="${SPIKE_CAPSULE_ROOT:-${HOME}/capsules-shake}"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${FX_RIG}/lib/common.sh"

FX_OUT=''

# Which probe a sweep perturbs, and which variable carries its overlay. Two
# defaults rather than two parameters: P-C3 is the only probe through T5, so
# every existing call site stays byte-identical, and a driver for another probe
# states the pair once at the top instead of threading it through every run.
#
# The overlay names are per-probe on purpose. They are recorded in each results
# file's preamble as `MUTATED=`, so one shared name would let a mutated P-C3 run
# and a mutated guards run stamp the same marker into two files that mean
# different things by it.
FX_PROBE=c3
FX_MUTANT_ENV=SPIKE_C3_MUTANT

# fx_run <mutant-file> <subject> [more…]
#
# One `rig ${FX_PROBE} <subject>` run under the overlay, output captured. Never
# piped: a pipe reports the READER'S exit status, and the whole point here is
# the run's own.
fx_run() {
  local mutant=$1 subject=$2 log
  shift 2
  log=$(mktemp)
  env "${FX_MUTANT_ENV}=${mutant}" SPIKE_CAPSULE_ROOT="${FX_ROOT}" \
    "${FX_RIG}/rig" "${FX_PROBE}" "${subject}" >"${log}" 2>&1 || true
  FX_OUT=$(cat "${log}")
  rm -f -- "${log}"
}

# fx_case <label> <mutant-file> <subject> — header, then one run under the
# overlay, for a sweep that asserts FREELY over the capture afterwards.
#
# The three shapes below each bake in the red pattern they expect, which suits a
# matrix cell and does not suit a probe whose clauses have no common shape. T5
# kept this local on the "one caller does not earn a library entry" rule; T6 is
# the second caller, so it is lifted here as that note said it would be.
fx_case() {
  printf '\n───── %s ─────\n' "$1"
  fx_run "$2" "$3"
}

# fx_reds — how many assertions failed in the captured run.
fx_reds() { printf '%s' "$(printf '%s\n' "${FX_OUT}" | grep -c '^  FAIL' || true)"; }

# fx_show <n> — echo the captured assertion lines, indented, for the sweep log.
#
# `|| true` is not decoration: `head` closes the pipe, `grep` takes EPIPE, and
# under `set -o pipefail` a SUCCESSFUL display would abort the sweep. The same
# hazard `c3_lines_have` documents one library over.
fx_show() {
  { printf '%s\n' "${FX_OUT}" | grep -E '^  (ok|FAIL) ' | head -"${1:-40}" |
    sed 's/^/  | /'; } || true
}

# fx_red_on <label> <pattern> — a clause matching <pattern> FAILED.
fx_red_on() {
  rig_assert "$1" command grep -qE "^  FAIL .*$2" <<<"${FX_OUT}"
}

# fx_held <label> <pattern> — a clause matching <pattern> is still ok.
#
# THE ISOLATION CONTROL. `-q` on the ok line and NOT merely the absence of a
# FAIL: absence passes just as well when the clause never ran at all, which is
# the absence-shaped result this phase keeps meeting (H13's M6).
fx_held() {
  rig_assert "$1" command grep -qE "^  ok .*$2" <<<"${FX_OUT}"
}

# ── the three shapes ────────────────────────────────────────────────────────

# expect_planted <n> <mutant> <row> — the mutant must red `planted?`.
#
# For a perturbation that removes the PAYLOAD: the cell ran, and the control
# that exists to catch a silent pass caught it.
expect_planted() {
  local n=$1 mutant=$2 row=$3
  printf '\n───── %s ─────\n' "${n}"
  fx_run "${mutant}" "${row}"
  fx_red_on "${n}: planted? REDS" 'planted\?'
}

# expect_refusal <n> <mutant> <row> <want> — the OBSERVED BOUNDARY moves.
#
# For a perturbation that changes what the pipeline does, not what the row
# sees. `<want>` is a pattern the boundary assertion's failure must carry.
expect_refusal() {
  local n=$1 mutant=$2 row=$3 want=$4
  printf '\n───── %s ─────\n' "${n}"
  fx_run "${mutant}" "${row}"
  fx_red_on "${n}: the boundary REDS (${want})" "${want}"
}

# expect_assert <n> <mutant> <row> <pattern> [also]
#
# For a perturbation whose red lands inside `_assert` or `assert_outcome`
# rather than in `planted?`. <also> is an extra check run against the SAME
# capture — the shape a mutant needs when its red is in `assert_outcome`, which
# is not the row's own code and whose clauses the row cannot see. Default
# empty, so a mutant that does not need it is unaffected.
expect_assert() {
  local n=$1 mutant=$2 row=$3 pattern=$4 also=${5:-}
  printf '\n───── %s ─────\n' "${n}"
  fx_run "${mutant}" "${row}"
  fx_red_on "${n}: REDS on ${pattern}" "${pattern}"
  [ -z "${also}" ] || "${also}" "${n}"
}
