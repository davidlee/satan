#!/usr/bin/env bash
# control/probe-c3.sh — P-C3, THE HOSTILE MATRIX (EX-2, EX-3, EX-5, EX-12, VA-1).
#
#   usage: probe-c3.sh [row…]              (dispatched by `rig c3`)
#          probe-c3.sh --positive-control  the harness's OWN red/green; no
#                                          provisioning, no cells, no results.
#                                          Called DIRECTLY: `rig`'s parser owns
#                                          the flag space, and this check runs
#                                          at the head of every run regardless
#          rows: H1 … H16 — the § 5.6 rows, as named in probes/c3/matrix.tsv
#   env:   SPIKE_CAPSULE_ROOT  capsule / fixture root (default: ~/capsules)
#          SPIKE_C3_LEGS       pipeline | conflict | both (default: both)
#
# ── the loop is design § 5.4's, in that order, and the order is the point ────
#
#   guard_not_real_repo   (I6, before anything — `rig_enter`)
#   matrix_validate       (before anything is PROVISIONED — D-P05-3)
#   per (row, fixture, mechanism, alternative):
#     provision → Hnn_mutate → Hnn_planted? → harness leg → first refusing
#     stage+token → Hnn_assert → assert_outcome → emit result row
#
# The spec is READ, never re-parsed: `lib/matrix.sh` owns what a data line is
# and how it splits, so the harness and the validator cannot disagree about
# where a column starts — the one disagreement neither would report.
#
# ── one authored line, N scored entries ─────────────────────────────────────
#
# `expected-stage`/`expected-token` may carry a `|` ALTERNATION where § 5.6's
# re-derived boundary names more than one thing (D-P05-2). Every alternative
# must be OBSERVED, not merely permitted, so the harness runs one leg per
# alternative and records one entry per leg. `harness=both` is the same shape
# the design already uses: one authored line, two scored entries.
#
# ── what this harness will not do ───────────────────────────────────────────
#
# It will not run a row it has no instantiation for, and it will not record one
# as `n/a`. `n/a` names a STRUCTURAL absence — no `.envrc` to plant, no
# capsule-authored artifact to read — and never "not attempted" (R-C). A row
# whose `Hnn_*` functions are absent is a USAGE refusal, up front, naming the
# task that provides them: an unwritten row that scored `n/a` would cost the
# row its altitude and read in the table as a property of the capsule model.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=pipeline.sh
. "${RIG_DIR}/control/pipeline.sh"
# The fixture table (T6 lift). Needs `rig_die` from common.sh, which pipeline.sh
# has already sourced; it defines only functions and reads `RIG_ROOT` at CALL
# time, so it is inert until `rig_enter` has published one.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/fixtures.sh
. "${RIG_DIR}/lib/fixtures.sh"
# `lib/matrix.sh` needs `token_legal`, which pipeline.sh authors — sourced after.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/matrix.sh
. "${RIG_DIR}/lib/matrix.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/rows.sh
. "${RIG_DIR}/lib/rows.sh"
# The rows' own `H<n>_{mutate,planted,assert}`. Sourced LAST: the instantiations
# ride `contract_field`, `RIG_RESULT_REF` and `rig_assert` from the three above.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/instantiations.sh
. "${RIG_DIR}/lib/instantiations.sh"
# The H10/H16 conflict sub-probe (T5). Last, and after the instantiations: it
# reads `C3_STALE_MARK` and `C3_H16_TRUNK_PATH` from there rather than minting a
# second name for canonical's mover — one layer down, same actor.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/conflict.sh
. "${RIG_DIR}/lib/conflict.sh"
SPIKE_C3_MUTANT="${SPIKE_C3_MUTANT:-}"

# P-C3 records the spec's eleven columns: the derived verdict is spliced in at
# `outcome` (10), and the field the recorder refuses to finish without is
# `planted` (9) — this matrix's positive control, the per-cell answer to "did
# my own payload actually land".
ROWS_OUTCOME_FIELD=10
ROWS_OBSERVABLE_FIELD=9

# ── scoring: expected boundary vs observed boundary (S2) ────────────────────

# The four stages in pipeline order. `dissolution` is deliberately NOT here: it
# is not a stage that runs, and it has no position to be earlier or later than.
C3_STAGE_ORDER='harvest conform verify advance'

stage_index() {
  local stage=$1 i=0 s
  for s in ${C3_STAGE_ORDER}; do
    i=$((i + 1))
    [ "${s}" = "${stage}" ] && {
      printf '%s' "${i}"
      return 0
    }
  done
  return 1
}

# cell_score <expected-stage> <expected-token> <observed>  → pass|partial|fail
#
# `observed` is `stage/token`, or EMPTY when the run refused nowhere. One
# alternative per call — the caller has already split a `|` into legs, so this
# never sees an alternation and cannot pass a row on an alternative some other
# leg observed.
#
# S2's distinction, and it is the whole reason this is a function rather than
# an equality test: a kill at a LATER boundary than expected is a PARTIAL fail
# — the defence held, but the layer that was supposed to catch it is missing.
# No kill at all is a plain fail. Collapsing the two would report a missing
# layer as an intact one.
#
# A cell with no expected token is making a different claim. `dissolution` says
# the hazard has no refusing stage BY CONSTRUCTION (R-D), so ANY refusal
# falsifies it. A named stage with no token — H11's `verify`, H14's `harvest` —
# says "this row's boundary is that stage"; whether it happens to refuse there
# is not the claim, the row's own `Hnn_assert` observable is. So a refusal at
# that stage is accepted and a refusal elsewhere is not: something else killed
# the row before it ever reached the boundary under test.
cell_score() {
  local want_stage=$1 want_token=$2 observed=$3
  local obs_stage=${observed%%/*} want_i obs_i

  if [ -n "${want_token}" ]; then
    [ -n "${observed}" ] || {
      printf 'fail'
      return 0
    }
    [ "${observed}" = "${want_stage}/${want_token}" ] && {
      printf 'pass'
      return 0
    }
    if want_i=$(stage_index "${want_stage}") && obs_i=$(stage_index "${obs_stage}") &&
      [ "${obs_i}" -gt "${want_i}" ]; then
      printf 'partial'
      return 0
    fi
    printf 'fail'
    return 0
  fi

  [ -n "${observed}" ] || {
    printf 'pass'
    return 0
  }
  [ "${want_stage}" != dissolution ] && [ "${obs_stage}" = "${want_stage}" ] && {
    printf 'pass'
    return 0
  }
  printf 'fail'
}

# ── altitude (EX-5, VA-1, A-3) ──────────────────────────────────────────────

# cell_altitude <live-light> <pass-light> <live-heavy> <pass-heavy>
#
# Computed from the row's own legs, never authored — VA-1 asserts the authored
# column is empty precisely so this claim is checkable.
#
# A fixture HOLDS for the row when it has at least one live leg and every live
# leg passed. `n/a` legs are EXCLUDED, never counted as a hold (§ 5.4): a cell
# that could not be planted proves nothing, and counting it would stamp the
# strongest claim in the table onto a probe that never ran.
#
# The two one-fixture cases are NOT the same finding, which is why they get
# different values. Light is the TypeScript fixture and heavy is this Rust
# repository, so "heavy alone, because light had nothing to plant" is exactly
# `unproven-beyond-rust`. "One fixture held and the other FAILED" is a
# divergence — a real result about portability — and reads `client-local`.
# A row that holds nowhere makes no altitude claim at all: its legs already
# carry `fail`, and stamping a reach onto it would dress a failure as evidence.
cell_altitude() {
  local live_l=$1 pass_l=$2 live_h=$3 pass_h=$4
  local hold_l=0 hold_h=0
  [ "${live_l}" -gt 0 ] && [ "${pass_l}" -eq "${live_l}" ] && hold_l=1
  [ "${live_h}" -gt 0 ] && [ "${pass_h}" -eq "${live_h}" ] && hold_h=1

  if [ "${hold_l}" -eq 1 ] && [ "${hold_h}" -eq 1 ]; then
    printf 'model-level'
  elif [ "${hold_h}" -eq 1 ] && [ "${live_l}" -eq 0 ]; then
    printf 'unproven-beyond-rust'
  elif [ "${hold_l}" -eq 1 ] || [ "${hold_h}" -eq 1 ]; then
    printf 'client-local'
  else
    printf 'n/a'
  fi
}

# ── the derived outcome, with P-C3's third value ────────────────────────────

# `lib/rows.sh` derives `pass`/`FAIL` from the assertions the row actually made,
# and a caller may NOT pass an outcome in. P-C3's authored vocabulary has a
# third value — `partial` — so the derivation is EXTENDED here rather than the
# rule being broken: still derived, still from the assertions, never supplied.
#
# `partial` is reported only when the boundary comparison is the row's SOLE red.
# A leg that also broke its own observable is not "partial": two reds mean the
# row failed at something beyond a missing layer, and reporting the weaker word
# would hide it.
CELL_VERDICT=''

row_outcome() {
  local delta=$((RIG_ASSERT_FAILURES - ROW_FAILURES_AT_START))
  if [ "${delta}" -eq 0 ]; then
    printf 'pass'
  elif [ "${CELL_VERDICT}" = partial ] && [ "${delta}" -eq 1 ]; then
    printf 'partial'
  else
    printf 'fail'
  fi
}

# ── the harness's own red/green (EX-3) ──────────────────────────────────────
#
# Every cell the matrix scores is scored by the code below, so EX-3's "the
# harness is observed working" cannot be a claim about code — it has to be an
# observation. These run BEFORE any cell, on every invocation, because a
# scorer proven after the fact proves it for the next run and not for this one.
# They are pure string comparisons and cost nothing.

# Returns 0 when the guarded assertion REDS. The counter is reset in a subshell
# so a deliberate red does not poison the real tally (selftest.sh's precedent).
planted_guard_reds() {
  local planted=$1
  ! (
    RIG_ASSERT_FAILURES=0
    cell_assert_planted 'self-check' "${planted}" >/dev/null 2>&1
    [ "${RIG_ASSERT_FAILURES}" -eq 0 ]
  )
}

cell_assert_planted() {
  rig_assert "$1: planted? — this cell's own payload landed (F-7)" test -n "$2"
}

# outcome_for <verdict> <reds> — the derivation, exercised on a synthetic row.
# In a subshell so the real tally is untouched: `row_outcome` reads two counters
# and this states both, rather than the checks saving and restoring the live one.
outcome_for() (
  CELL_VERDICT=$1
  # Subshell-local is the POINT, not an accident: a synthetic count must not
  # reach the real tally. Same shape as selftest.sh's `outcome_reds`.
  # shellcheck disable=SC2030
  RIG_ASSERT_FAILURES=$2
  ROW_FAILURES_AT_START=0
  row_outcome
)

c3_positive_control() {
  printf '\nharness positive control — the scorer, before it scores anything (EX-3)\n'

  # THE ONE THE PHASE ASKS FOR BY NAME: a cell whose `planted?` is forced false
  # must RED, not pass. Without this, a mutate step that silently did nothing
  # would compute as "holds under both" and stamp the row `model-level` — the
  # strongest claim in the table, on a probe that never ran (§ 5.4, F-7).
  rig_assert 'a forced-false planted? REDS the cell' planted_guard_reds ''
  rig_assert_fails 'and a real observable does NOT red it' planted_guard_reds 'a sentinel at /host/path'

  # The expected boundary, hit exactly.
  rig_assert_eq 'exact boundary is pass' pass \
    "$(cell_score conform ancestry-not-descendant conform/ancestry-not-descendant)"
  # S2's partial: the defence held, one layer later than it should have.
  rig_assert_eq 'a kill at a LATER stage is partial' partial \
    "$(cell_score harvest oid-mismatch conform/undeclared-path)"
  # S2's plain fail: no kill at all.
  rig_assert_eq 'no kill where one was expected is fail' fail \
    "$(cell_score conform undeclared-path '')"
  # Earlier is not "partial" — the row never reached the boundary under test.
  rig_assert_eq 'a kill at an EARLIER stage is fail, not partial' fail \
    "$(cell_score advance stale-base harvest/fsck-failed)"
  # Right stage, wrong token. The distinction the whole closed vocabulary exists
  # for; scoring this `pass` would make attribution decorative.
  rig_assert_eq 'the right stage with the WRONG token is fail' fail \
    "$(cell_score conform gitlink conform/undeclared-path)"

  # Dissolution (R-D): no refusing stage BY CONSTRUCTION, so a refusal falsifies
  # it and an absence of one is the result — not a skip.
  rig_assert_eq 'a dissolution that refuses nowhere is pass' pass \
    "$(cell_score dissolution '' '')"
  rig_assert_eq 'a dissolution that DID refuse is fail' fail \
    "$(cell_score dissolution '' conform/forbidden-path)"
  # A named stage with no token: the row's boundary, not a refusal claim.
  rig_assert_eq 'a token-less stage row passes on no refusal' pass \
    "$(cell_score verify '' '')"
  rig_assert_eq 'a token-less stage row passes on a refusal AT that stage' pass \
    "$(cell_score verify '' verify/suite-failed)"
  rig_assert_eq 'a token-less stage row fails on a refusal ELSEWHERE' fail \
    "$(cell_score verify '' conform/undeclared-path)"

  # Altitude (EX-5). `n/a` excluded, never counted as a hold — the four shapes
  # that separate the three claims from each other.
  rig_assert_eq 'holds under both fixtures is model-level' model-level \
    "$(cell_altitude 2 2 2 2)"
  rig_assert_eq 'n/a on light, holding on heavy is unproven-beyond-rust' unproven-beyond-rust \
    "$(cell_altitude 0 0 2 2)"
  rig_assert_eq 'holding on one of two LIVE fixtures is client-local (a divergence)' client-local \
    "$(cell_altitude 2 2 2 1)"
  rig_assert_eq 'holding nowhere claims no altitude' n/a \
    "$(cell_altitude 2 1 2 0)"
  rig_assert_eq 'a single passing light leg with no heavy leg is client-local' client-local \
    "$(cell_altitude 1 1 0 0)"

  # The derived outcome, including the one place `partial` may be reported.
  rig_assert_eq 'no red on the row derives pass' pass "$(outcome_for pass 0)"
  rig_assert_eq 'one red, classified partial, derives partial' partial \
    "$(outcome_for partial 1)"
  rig_assert_eq 'a partial row with a SECOND red derives fail' fail \
    "$(outcome_for partial 2)"
  rig_assert_eq 'one red, classified fail, derives fail' fail "$(outcome_for fail 1)"
}

# ── argument parsing ────────────────────────────────────────────────────────

ALL_ROWS='H1 H2 H3 H4 H5 H6 H7 H8 H9 H10 H11 H12 H13 H14 H15 H16'

# Which legs this run covers. A run that skipped the conflict sub-probe must SAY
# so in the results file rather than look complete (F-9, EX-14): the selector is
# recorded in the preamble.
C3_LEGS="${SPIKE_C3_LEGS:-both}"
case "${C3_LEGS}" in
  pipeline | conflict | both) ;;
  *) rig_die "unknown SPIKE_C3_LEGS: ${C3_LEGS} (pipeline|conflict|both)" ;;
esac

self_check_only=0
rows=()
while [ $# -gt 0 ]; do
  case "$1" in
    --positive-control) self_check_only=1 ;;
    -h | --help)
      sed -n '2,9p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) rig_die "unknown flag: $1" ;;
    *)
      case " ${ALL_ROWS} " in
        *" $1 "*) rows+=("$1") ;;
        *) rig_die "unknown row: $1 (${ALL_ROWS})" ;;
      esac
      ;;
  esac
  shift
done
[ "${#rows[@]}" -gt 0 ] || read -r -a rows <<<"${ALL_ROWS}"

# I6 — FIRST, as a STATEMENT, before any provisioning (F-P01-1).
rig_enter

printf '\nP-C3 — the hostile matrix (EX-2, EX-3, EX-5, EX-12, VA-1)\n'

c3_positive_control
if [ "${self_check_only}" -eq 1 ]; then
  rig_assert_done 'probe-c3 --positive-control'
  exit 0
fi

# ── the spec, validated before anything is provisioned (D-P05-3) ────────────
#
# An authored `expected-token` outside the closed vocabulary would otherwise
# surface as `stage_emit`'s RIG DEFECT at run time — AFTER the cell had run,
# and attributed to the rig rather than to the file that has it.
printf '\nmatrix spec\n'
matrix_validate
# The live tally, not a subshell's: the self-check's synthetic counters are
# scoped to `outcome_for`/`planted_guard_reds` precisely so this read is real.
# shellcheck disable=SC2031
[ "${RIG_ASSERT_FAILURES}" -eq 0 ] ||
  rig_die 'the matrix spec is invalid — refusing to provision against it'

REPORT="${RIG_ROOT}/probes/c3/results.tsv"

selected() {
  case " ${rows[*]} " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# ── readiness (R-C: an unwritten row is a refusal, never an `n/a`) ──────────

row_implemented() {
  local row=$1 fn
  for fn in mutate planted assert; do
    declare -F "${row}_${fn}" >/dev/null || return 1
  done
}

# The selected rows carrying a conflict sub-probe leg — once per ROW, never per
# cell: the leg runs against F3, which has no fixture or mechanism dimension.
c3_conflict_rows() {
  local line seen=''
  local row fixture mechanism harness vclass inst stage token planted outcome altitude
  while IFS= read -r line; do
    matrix_read "${line}"
    if selected "${row}"; then
      case "${harness}" in
        conflict | both)
          case " ${seen} " in
            *" ${row} "*) ;;
            *) seen="${seen}${row} " ;;
          esac
          ;;
      esac
    fi
  done < <(matrix_rows)
  printf '%s' "${seen}"
}

c3_assert_ready() {
  local missing='' pending='' line
  local row fixture mechanism harness vclass inst stage token planted outcome altitude

  if [ "${C3_LEGS}" != conflict ]; then
    while IFS= read -r line; do
      matrix_read "${line}"
      if selected "${row}" && [ "${outcome}" != 'n/a' ] && [ "${harness}" != conflict ]; then
        if ! row_implemented "${row}"; then
          case " ${missing} " in
            *" ${row} "*) ;;
            *) missing="${missing}${row} " ;;
          esac
        fi
      fi
    done < <(matrix_rows)
    [ -z "${missing}" ] ||
      rig_die "no instantiation for: ${missing}— T4a..T4e provide Hnn_mutate / Hnn_planted / Hnn_assert. An unwritten row is not an 'n/a' (R-C)"
  fi

  if [ "${C3_LEGS}" != pipeline ] && ! declare -F conflict_subprobe >/dev/null; then
    pending=$(c3_conflict_rows)
    [ -z "${pending}" ] ||
      rig_die "no conflict sub-probe for: ${pending}— T5 provides 'conflict_subprobe'. SPIKE_C3_LEGS=pipeline covers the pipeline legs alone, and the selector is recorded in the results file rather than the run looking complete"
  fi
}

# What the selected rows OWE this run, counted FROM THE SPEC before anything
# runs. Completeness measured against a number derived from the file is the only
# form that can see a cell which never ran at all — counting what was recorded
# cannot (rows.sh, probe-c2's precedent).
c3_expected_entries() {
  local total=0 line
  local row fixture mechanism harness vclass inst stage token planted outcome altitude

  if [ "${C3_LEGS}" != conflict ]; then
    while IFS= read -r line; do
      matrix_read "${line}"
      if selected "${row}" && [ "${harness}" != conflict ]; then
        if [ "${outcome}" = 'n/a' ]; then
          total=$((total + 1))
        else
          total=$((total + $(cell_alternatives "${stage}" "${token}" | wc -w)))
        fi
      fi
    done < <(matrix_rows)
  fi

  if [ "${C3_LEGS}" != pipeline ]; then
    total=$((total + $(c3_conflict_rows | wc -w)))
  fi
  printf '%s' "${total}"
}

# ── the cell loop ───────────────────────────────────────────────────────────

# The alternatives a cell is scored on. `|` in `expected-token` splits into one
# leg per token; with no token, `|` in `expected-stage` splits into one leg per
# stage (H9's "scored as two"). Every alternative is OBSERVED by a leg of its
# own, rather than any one of them satisfying the cell.
cell_alternatives() {
  local stage=$1 token=$2
  if [ -n "${token}" ]; then printf '%s' "${token//|/ }"; else printf '%s' "${stage//|/ }"; fi
}

# Run the pipeline leg. PUBLISHES `CELL_OBSERVED`; prints nothing.
#
# `pipeline_run` is REDIRECTED, never piped and never substituted: a pipe or a
# `$( … )` subshells it, and a RIG DEFECT return could not reach this shell —
# the run would score as an ordinary refusal, which is the F-P01-1 family in the
# one place it would be least visible (selftest.sh:77-88 is the reference form).
cell_pipeline_leg() {
  local run=$1 mechanism=$2 rc=0
  pipeline_run "${run}" "${mechanism}" >"${run}/stages" || rc=$?
  if [ "${rc}" -eq "${RIG_EXIT_DEFECT}" ]; then
    rig_warn "P-C3: RIG DEFECT from the pipeline — not a result"
    exit "${RIG_EXIT_DEFECT}"
  fi
  CELL_OBSERVED=$(pipeline_first_refusal "${run}/stages")
}

# cell_run <row> <fixture> <mechanism> <harness> <vclass> <inst> <stage> <token> <alt>
#
# One leg, in design § 5.4's order. Returns 0 iff the leg scored `pass`, so the
# caller can count holds for the altitude computation without re-deriving them.
cell_run() {
  local row=$1 fixture=$2 mechanism=$3 harness=$4 vclass=$5 inst=$6
  local stage=$7 token=$8 alt=$9
  local at="${row}/${fixture}/${mechanism}/${alt}"
  local want_stage="${stage}" want_token='' run planted

  # With a token, the alternative IS the token and the stage is single (the
  # validator refuses a multi-stage cell that claims one). Without, the
  # alternative is the stage.
  if [ -n "${token}" ]; then want_token="${alt}"; else want_stage="${alt}"; fi

  row_begin "${at} — ${want_stage}${want_token:+/${want_token}}"
  CELL_VERDICT=''
  CELL_OBSERVED=''

  pipeline_setup "c3-${row}-${fixture}-${mechanism}-${alt}" \
    "$(fixture_repo "${fixture}")" "$(fixture_declaration "${fixture}")" \
    "$(fixture_slice "${fixture}")" "$(fixture_stub "${fixture}")"
  run="${PIPELINE_RUN}"

  # The verify bounds travel per fixture, set for this cell only. Scoped here
  # rather than exported once at the head of the run so that a cell reading them
  # cannot inherit the previous cell's fixture (D-P05-7).
  PIPELINE_VERIFY_TIMEOUT="$(fixture_verify_timeout "${fixture}")"
  PIPELINE_VERIFY_DISK_CAP="$(fixture_verify_disk_cap "${fixture}")"

  # The WORKER bounds travel per ROW, and they are set HERE for the same reason
  # the verify bounds are: a row's terms must not ride into the next row's
  # capsule. A row whose hazard is produced inside the capsule cannot reach it
  # from the plant seam (F-P05-37), so it states its terms declaratively and the
  # harness stays free of any row's body (D-P05-19). Both lookups return EMPTY
  # for every row but the one that asked, and empty means `pipeline.sh`'s own
  # default — so this is inert for the fifteen rows already scored.
  PIPELINE_WORKER_VEHICLE="$(c3_row_worker_vehicle "${row}")"
  PIPELINE_WORKER_DISK_CAP="$(c3_row_worker_disk_cap "${row}")"

  # The capsule phase and the pipeline are separate calls so the harness can
  # plant BETWEEN them (A-2, pipeline.sh:196-200). That seam is the whole
  # `Hnn_mutate` mechanism; the rig plays the adversary trusted-side.
  pipeline_capsule "${run}"
  "${row}_mutate" "${run}" "${fixture}" "${mechanism}" "${alt}"

  planted=$("${row}_planted" "${run}" "${fixture}" "${mechanism}" "${alt}") || planted=''
  cell_assert_planted "${at}" "${planted}"

  cell_pipeline_leg "${run}" "${mechanism}"

  "${row}_assert" "${run}" "${fixture}" "${mechanism}" "${alt}" "${CELL_OBSERVED}"
  assert_outcome "${run}" "${CELL_OBSERVED}"

  # Scored FIRST, then asserted on the verdict — not on a string equality with
  # the observation. A token-less row legitimately passes on either no refusal
  # or a refusal at its own stage, so an equality test here would red rows the
  # scorer passes, and the two would disagree about what the matrix says.
  CELL_VERDICT=$(cell_score "${want_stage}" "${want_token}" "${CELL_OBSERVED}")
  rig_assert_eq \
    "${at}: the boundary § 5.6 re-derives — observed ${CELL_OBSERVED:-no refusal}" \
    pass "${CELL_VERDICT}"

  # Trailing empty field: `altitude`, stamped once the whole row has run.
  record_row "${row}" "${fixture}" "${mechanism}" "${harness}" "${vclass}" \
    "${inst}" "${want_stage}" "${want_token}" "${planted}" ''

  pipeline_teardown "${run}"
  [ "${CELL_VERDICT}" = pass ]
}

# ── the row loop ────────────────────────────────────────────────────────────

# Altitude is a property of the ROW (does it hold under both fixtures?), but it
# is a COLUMN on every entry, and the recorder derives an entry's outcome at the
# moment that leg ends. So legs are recorded as they run with the column left
# empty, and the row stamps it afterwards. Appending is all that takes: the
# recorded line already ends in the empty eleventh field's tab.
c3_stamp_altitude() {
  local from=$1 altitude=$2 i
  for ((i = from; i < ${#ROWS_RECORDED[@]}; i++)); do
    ROWS_RECORDED[i]="${ROWS_RECORDED[i]}${altitude}"
  done
}

c3_run_row() {
  local want=$1 line from=${#ROWS_RECORDED[@]} alt reach
  local live_l=0 pass_l=0 live_h=0 pass_h=0
  local row fixture mechanism harness vclass inst stage token planted outcome altitude

  while IFS= read -r line; do
    matrix_read "${line}"
    if [ "${row}" = "${want}" ] && [ "${harness}" != conflict ]; then
      # An up-front `n/a` is a recorded outcome with its reason in
      # `instantiation` — legal, and EXCLUDED from the altitude computation
      # rather than counted as a hold (§ 5.4). It does not run, and it is not
      # silently dropped either.
      if [ "${outcome}" = 'n/a' ]; then
        row_begin "${row}/${fixture}/${mechanism} — n/a (${inst})"
        record_row_na "${row}" "${fixture}" "${mechanism}" "${harness}" "${vclass}" \
          "${inst}" "${stage}" "${token}" 'n/a' ''
      else
        for alt in $(cell_alternatives "${stage}" "${token}"); do
          case "${fixture}" in
            light) live_l=$((live_l + 1)) ;;
            heavy) live_h=$((live_h + 1)) ;;
          esac
          if cell_run "${row}" "${fixture}" "${mechanism}" "${harness}" "${vclass}" \
            "${inst}" "${stage}" "${token}" "${alt}"; then
            case "${fixture}" in
              light) pass_l=$((pass_l + 1)) ;;
              heavy) pass_h=$((pass_h + 1)) ;;
            esac
          fi
        done
      fi
    fi
  done < <(matrix_rows)

  reach=$(cell_altitude "${live_l}" "${pass_l}" "${live_h}" "${pass_h}")
  c3_stamp_altitude "${from}" "${reach}"

  # A row that holds on one LIVE fixture and not the other is a portability
  # result, not a rounding error — § 5.4 calls the divergence a finding, so it
  # is printed as one. The leg that did not hold has already reddened the run.
  if [ "${reach}" = client-local ] && [ "${live_l}" -gt 0 ] && [ "${live_h}" -gt 0 ]; then
    printf '  FINDING  %s: holds under one fixture only (light %s/%s, heavy %s/%s) — divergence\n' \
      "${want}" "${pass_l}" "${live_l}" "${pass_h}" "${live_h}"
  fi
  printf '  altitude %s: %s\n' "${want}" "${reach}"
}

# ── the conflict sub-probe leg (T5 provides the body) ───────────────────────
#
# `harness=both` means the row ALSO carries this leg: run ONCE PER ROW against
# F3, scored as a separate entry, and COUNTING TOWARD NOTHING (F-9). It is an
# incumbent-layer regression check, not capsule-model evidence, so it never
# enters the altitude computation or a coverage number.
c3_run_conflict() {
  local want=$1 before=${#ROWS_RECORDED[@]}
  conflict_subprobe "${want}"
  rig_assert_eq "${want}: the conflict sub-probe recorded exactly one entry (F-9)" \
    1 "$((${#ROWS_RECORDED[@]} - before))"
}

# ── run ─────────────────────────────────────────────────────────────────────

# ── the falsifiability overlay (F-P05-31's middle beat) ─────────────────────
#
# An OPTIONAL file of rebinds. A mutant WRAPS a row or harness function without
# owning a copy of its body — the only way its red is evidence about the real
# function rather than about a fork of it. Inert when unset, so a scored run is
# byte-identical to one without it.
#
# LOADED HERE, NOT BESIDE THE OTHER SOURCES, and the position is load-bearing:
# this file interleaves definitions with execution, so an overlay sourced at the
# top can only see the four libraries and not the harness's own functions. It
# refused `fixture_verify_timeout` from up there — correctly, which is why
# `rebind` fails closed on an unknown name.
#
# The same shape `RIG_DEFECT_CANONICAL_HOP` already uses one file over: a
# falsifiability affordance wired into the real path deliberately, because a
# clause shown to red against a REAL perturbation is worth more than one
# hand-waved against a hypothetical. The positive control above has already run
# UNMUTATED by this point, which is the right order — a mutant must not be able
# to quiet the harness's own red/green check.
if [ -n "${SPIKE_C3_MUTANT}" ]; then
  [ -r "${SPIKE_C3_MUTANT}" ] || rig_die "no such mutant overlay: ${SPIKE_C3_MUTANT}"
  rig_warn "FALSIFY MODE: overlay ${SPIKE_C3_MUTANT} — this run is NOT evidence"
  # shellcheck source=/dev/null
  . "${SPIKE_C3_MUTANT}"
fi

c3_assert_ready

expected=$(c3_expected_entries)

if [ "${C3_LEGS}" != conflict ]; then
  for row_id in "${rows[@]}"; do c3_run_row "${row_id}"; done
fi
if [ "${C3_LEGS}" != pipeline ]; then
  for row_id in $(c3_conflict_rows); do c3_run_conflict "${row_id}"; done
fi

# ── VA-1, made mechanical ───────────────────────────────────────────────────
#
# Two failures a results table is least able to show, and neither implies the
# other: a cell that ran but named no observable (its `planted?` was empty —
# the silent pass), and a cell that never ran at all.
printf '\n'
rows_assert_complete 'VA-1' "${expected}"

rows_write "${REPORT}" "${MATRIX_COLUMNS}" \
  "$(printf 'p-c3: %s\tin-jail\tlegs=%s\trows=%s%s' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${C3_LEGS}" "${rows[*]}" \
    "${SPIKE_C3_MUTANT:+$(printf '\tMUTATED=%s' "${SPIKE_C3_MUTANT##*/}")}")"

printf '\nresults: %s\n' "${REPORT}"
printf '%s\n' "${ROWS_RECORDED[@]}" | cut -f1,2,3,10,11 | sed 's/^/  /'

rig_assert_done 'probe-c3'
