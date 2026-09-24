#!/usr/bin/env bash
# lib/measure.sh — the cost-probe measurement terms, defined ONCE.
#
# Extracted from `probe-c1a.sh` when P-C1b needed every one of them (PHASE-06).
# A second copy would be two definitions of what a recorded measurement IS, and
# the two probes' rows land in sibling files that a reader compares — the exact
# condition under which a drifted primitive is invisible until it matters. Same
# reasoning as `pipeline_quarantine` and `pipeline_harvester` being extracted
# rather than re-rolled per caller.
#
# Nothing here is P-C1a-specific: every term is "how a cost probe measures and
# records", and the probes supply what they measure.
#
# ── absolutes, never deltas (VA-2) ───────────────────────────────────────────
#
# Design § 9 records wall-clock and disk per accepted phase as **not measured**
# on the incumbent side: no instrumented incumbent run is in scope. There is no
# before column to subtract from, so these probes bank ABSOLUTES. Inventing a
# delta would manufacture the comparison § 9 declines to make, and it would read
# in the go/no-go as evidence rather than as arithmetic over one measured side
# and one guess. `REPORT_COLUMNS` carries no incumbent and no delta column, and
# each probe ASSERTS that rather than leaving it to a future edit.
#
# ── measurements are taken TRUSTED-SIDE ──────────────────────────────────────
#
# Wall clock is taken around each invocation and never read out of anything the
# capsule wrote. Not I5 pedantry applied to a number: the capsule's stdout is
# untrusted text, and a measurement parsed from it would be the one place in the
# rig where capsule content decides a recorded value.
#
# P-C1b has exactly one measurement that CANNOT meet this bar — token usage,
# whose only possible source is the harness running inside the capsule
# (F-P06-5). It is streamed to the parent rather than filed in the capsule's rw
# root, it is recorded and never asserted, and the measurement table names it
# capsule-reported. It does not go through the terms below.

# Guard, not an assumption. `%N` is a GNU extension and a non-GNU `date` emits it
# literally, which would silently produce garbage arithmetic rather than an
# error — so it is probed once, at source time, for every consumer.
case "$(date +%N)" in
  *[!0-9]* | '') rig_die "date +%N is not nanoseconds here — cannot measure wall clock" ;;
esac

STEP_T0=0
step_start() { STEP_T0=$(date +%s%N); }

# Milliseconds elapsed since `step_start`, as seconds to 3dp. Integer maths on
# nanoseconds, formatted at the end: shell has no floats, and rounding at the
# division would lose the sub-second steps entirely.
step_elapsed() {
  local ms=$((($(date +%s%N) - STEP_T0) / 1000000))
  printf '%d.%03d' $((ms / 1000)) $((ms % 1000))
}

# Peak disk is a MAXIMUM over the run, not the final size: `npm run clean` and
# the pipeline's own teardown would otherwise hide the high-water mark. Absolute
# bytes (VA-2), per capsule.
capsule_disk() { du -s -B1 -- "$1" 2>/dev/null | cut -f1; }

PEAK_WORKER=0
peak_worker() {
  local now
  now=$(capsule_disk "$1")
  [ "${now:-0}" -gt "${PEAK_WORKER}" ] && PEAK_WORKER=${now}
  return 0
}

# ── the recorded rows ────────────────────────────────────────────────────────
#
# Built in memory first so a probe's shape assertions run against what is about
# to be written, not against a file another run also appended to.

REPORT_COLUMNS=$'step\toutcome\tvalue\tunit\tdetail'
ROWS=()

record() {
  ROWS+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\t'"$5")
  printf '  %-9s %-8s %8s %-4s %s\n' "$1" "$2" "$3" "$4" "$5"
}

row_field() {
  local step=$1 field=$2 row
  for row in ${ROWS[@]+"${ROWS[@]}"}; do
    case "${row}" in
      "${step}"$'\t'*) printf '%s' "${row}" | cut -f"${field}" ;;
    esac
  done
}

# The banner names the RIG STATE, not just the clock. These result files are
# appended to across runs (R5 — they are the only thing the driving session
# reads), so a run taken before a rig fix and one taken after sit in the same
# file looking alike. P-C1a has already had one such boundary: F-P04-7's
# capsule-identity fix moved the headline number by more than an order of
# magnitude, and a reader quoting the earlier rows would be quoting a resolver
# timeout.
rig_state() {
  local repo oid
  repo=$(rig_repo_root) || {
    printf 'unknown'
    return 0
  }
  oid=$(git -C "${repo}" rev-parse --short HEAD 2>/dev/null) || {
    printf 'unknown'
    return 0
  }
  [ -z "$(git -C "${repo}" status --porcelain -- "${RIG_DIR}")" ] || oid="${oid}+dirty"
  printf '%s' "${oid}"
}

# The VA-2 shape claim, stated as a property of the header a probe is about to
# write. Left in prose it would be true today and quietly false after one edit.
assert_absolutes_only() {
  rig_assert_eq 'VA-2: the results header is absolutes-only (no before/delta column)' \
    "${REPORT_COLUMNS}" "$(printf '%s' "${REPORT_COLUMNS}" |
      tr '\t' '\n' | grep -viE '^(before|incumbent|delta|baseline)$' | paste -sd'\t' -)"
}
