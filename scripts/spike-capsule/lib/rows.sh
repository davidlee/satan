#!/usr/bin/env bash
# lib/rows.sh — how a probe matrix records a row. SOURCED, never executed.
#
# Lifted out of control/probe-c2.sh at PHASE-05 T3, unchanged in behaviour, so
# P-C2 and P-C3 share one recorder rather than growing two that drift. PHASE-04
# earned this shape; it is not a generalisation invented for a second caller.
#
# ── the one property everything here exists to hold ─────────────────────────
#
# **Outcome is DERIVED from the assertions the row actually made, never passed
# in.** A row that recorded `pass` while its own assertions reddened is the
# failure mode a results table is least able to show — the table would be
# evidence for the opposite of what happened, and nothing downstream could tell.
# So a caller cannot supply an outcome: it supplies the row's other fields and
# the recorder inserts the verdict it computed.
#
# `n/a` is the one authored outcome, and it is a legal recorded value with a
# reason (probe-specs § Order and gating). A SILENT PASS is not legal, which is
# what `rows_assert_complete` is for.
#
# ── what a caller parameterises ─────────────────────────────────────────────
#
# The two matrices have different columns — P-C2 records four, P-C3 eleven — so
# the recorder is told WHERE the outcome goes and WHICH field carries the row's
# observable, rather than knowing either. Both are 1-based field positions in
# the recorded line.
#
#   ROWS_OUTCOME_FIELD      the derived verdict is INSERTED here; the caller
#                           passes every other field, in order, and never this one
#   ROWS_OBSERVABLE_FIELD   the field `rows_assert_complete` requires non-empty —
#                           P-C2's named observable, P-C3's `planted` positive
#                           control. A row that left it empty is the silent pass.
#
# Defaults are P-C2's, because P-C2 is where the shape came from.

ROWS_RECORDED=()
ROWS_OUTCOME_FIELD=3
ROWS_OBSERVABLE_FIELD=2

ROW_FAILURES_AT_START=0

row_begin() {
  ROW_FAILURES_AT_START=${RIG_ASSERT_FAILURES}
  printf '\n%s\n' "$1"
}

row_outcome() {
  if [ "${RIG_ASSERT_FAILURES}" -eq "${ROW_FAILURES_AT_START}" ]; then
    printf 'pass'
  else
    printf 'FAIL'
  fi
}

# _rows_emit <outcome> <field…> — join with tabs, outcome spliced in at
# ROWS_OUTCOME_FIELD. Private: the two public verbs differ only in which outcome
# they splice, and that is the whole point of the split.
_rows_emit() {
  local outcome=$1 f
  shift
  local -a fields=()
  local i=1
  for f in "$@"; do
    if [ "${i}" -eq "${ROWS_OUTCOME_FIELD}" ]; then
      fields+=("${outcome}")
      i=$((i + 1))
    fi
    fields+=("${f}")
    i=$((i + 1))
  done
  # The outcome column can also be the LAST one, which the loop above never
  # reaches — an off-by-one that would silently drop the verdict rather than
  # misplace it.
  [ "${i}" -ne "${ROWS_OUTCOME_FIELD}" ] || fields+=("${outcome}")
  local IFS=$'\t'
  ROWS_RECORDED+=("${fields[*]}")
}

# record_row <field…>  — outcome derived, never supplied.
record_row() { _rows_emit "$(row_outcome)" "$@"; }

# record_row_na <field…> — `n/a` is a legal recorded outcome; a silent pass is
# not. The reason travels in the caller's own columns, because where a reason
# belongs is a property of the matrix, not of the recorder.
record_row_na() { _rows_emit 'n/a' "$@"; }

# rows_assert_complete <label> <expected-count>
#
# Completeness checked against the RECORDED ROWS rather than believed. Two
# distinct failures, and neither implies the other: a row that ran but named no
# observable, and a row that never ran at all.
rows_assert_complete() {
  local label=$1 expected=$2 entry
  for entry in "${ROWS_RECORDED[@]}"; do
    rig_assert "${label}: row '$(printf '%s' "${entry}" | cut -f1)' names its observable" \
      test -n "$(printf '%s' "${entry}" | cut -f"${ROWS_OBSERVABLE_FIELD}")"
  done
  rig_assert_eq "${label}: every requested row produced a recorded outcome" \
    "${expected}" "${#ROWS_RECORDED[@]}"
}

# rows_write <file> <header> [preamble]
#
# The header is written only into an empty/absent file, so repeated runs append
# rather than restating it. VA-1's "the run is recorded" is a file, not a memory
# of a terminal.
rows_write() {
  local file=$1 header=$2 preamble=${3:-}
  mkdir -p -- "$(dirname -- "${file}")"
  [ -s "${file}" ] || printf '%s\n' "${header}" >"${file}"
  {
    if [ -n "${preamble}" ]; then printf '%s\n' "${preamble}"; fi
    printf '%s\n' "${ROWS_RECORDED[@]}"
  } >>"${file}"
}
