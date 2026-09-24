#!/usr/bin/env bash
# lib/matrix.sh — the P-C3 matrix SPEC: where it lives, how to read it, and what
# makes it legal (SL-241 PHASE-05, EX-1/EX-4/EX-8). SOURCED, never executed.
#
# Reader and validator sit together on purpose. A validator that re-derived "what
# a row is" could disagree with the harness about where a row starts — which is
# the one disagreement neither would report — so `matrix_rows` is the single
# definition of the data lines and both go through it. Same reasoning as
# `declaration_field` in lib/common.sh.
#
# Requires `token_legal` from control/pipeline.sh: the closed refusal-token
# vocabulary is authored THERE, and an authored `expected-token` that the
# pipeline would call a RIG DEFECT at run time must be caught here instead — a
# typo in the spec would otherwise score as a defect of the rig rather than of
# the file that has it.

# The column contract, § 5.4, in order. Asserted against the file's own header
# so a column inserted in the middle cannot slide the values one place left.
MATRIX_COLUMNS=$'row\tfixture\tmechanism\tharness\tvector-class\tinstantiation\texpected-stage\texpected-token\tplanted\toutcome\taltitude'
MATRIX_NCOLUMNS=11

# `dissolution` is a STAGE value here and nowhere else in the rig: it is not a
# stage the pipeline runs, it is the recorded absence of one (R-D). Keeping it in
# this list rather than in `token_legal`'s `case` is what stops it leaking into
# the closed refusal vocabulary, which `assert_outcome` keys off.
MATRIX_STAGES='harvest conform verify advance dissolution'
MATRIX_HARNESSES='pipeline conflict both'
MATRIX_FIXTURES='light heavy'
MATRIX_MECHANISMS='fetch bundle'

# CPT-001's trigger classes, and `-` for a row whose vector is not an
# interpretation-surface trigger at all. ASM-007 — the claim that these are
# EXHAUSTIVE — is invalidated, and its record says in terms: do not repair it by
# adding a sixth class. The taxonomy is not retired, only the claim about it, so
# this set is closed here and a new class is a governance change, not a cell edit.
MATRIX_CLASSES='1 2 3 3g 4 5'

# A TSV read with `IFS=$'\t'` SILENTLY COLLAPSES empty fields — tab is IFS
# whitespace, and a run of IFS whitespace is one delimiter — so `…dissolution\t\tn/a`
# reads back with the token column holding `n/a`. Every later column shifts left
# and the validator reports violations the file does not have (observed at T2:
# two invented failures on H12/light). Translating to a NON-whitespace separator
# first is what preserves them.
MATRIX_FS=$'\x1f'

# The sixteen § 5.6 rows, x two fixtures x two mechanisms. Stated as a number
# rather than derived from the file, because "every row is present" cannot be
# checked against the file that would be missing one.
MATRIX_NROWS=16
MATRIX_CELLS_PER_ROW=4

matrix_path() {
  printf '%s' "${RIG_DIR}/probes/c3/matrix.tsv"
}

matrix_header() {
  command grep -v '^#' -- "${1:-$(matrix_path)}" | command head -1
}

# The data lines: comments stripped, header dropped.
matrix_rows() {
  command grep -v '^#' -- "${1:-$(matrix_path)}" | command tail -n +2
}

matrix_in_set() {
  case " $2 " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# matrix_read <line>
#
# THE split of a data line into its eleven columns, assigned into the CALLER's
# `row fixture mechanism harness vclass inst stage token planted outcome
# altitude` (bash's dynamic scoping, so the caller declares them `local`).
#
# One function rather than one per reader, and that is the whole point: the
# `\x1f` translation above is a correctness fix, not a formatting choice, and a
# second reader spelling the split for itself would silently re-acquire the
# collapse (F-P05-7). The validator and the P-C3 harness both come through here.
matrix_read() {
  IFS="${MATRIX_FS}" read -r row fixture mechanism harness vclass inst \
    stage token planted outcome altitude <<<"${1//$'\t'/${MATRIX_FS}}"
}

# matrix_validate [file]
#
# One assertion per INVARIANT, each naming its own offending cells — not one
# assertion per cell, which would bury a single real violation under five
# hundred `ok` lines.
matrix_validate() {
  local file=${1:-$(matrix_path)}

  rig_assert "matrix spec exists: ${file}" test -f "${file}"
  [ -f "${file}" ] || return 0

  rig_assert_eq "columns are exactly § 5.4's, in order" \
    "${MATRIX_COLUMNS}" "$(matrix_header "${file}")"
  rig_assert_eq "every cell line carries all ${MATRIX_NCOLUMNS} columns" \
    "" "$(matrix_rows "${file}" | awk -F'\t' -v n="${MATRIX_NCOLUMNS}" \
      'NF != n { printf "%s(%d fields) ", $1, NF }')"

  local bad_dim='' bad_class='' bad_stage='' bad_token='' bad_dissolution='' \
    bad_generated='' bad_altitude='' bad_reason=''
  local line row fixture mechanism harness vclass inst stage token planted outcome altitude
  local at c s t

  while IFS= read -r line; do
    matrix_read "${line}"
    at="${row}/${fixture}/${mechanism}"

    matrix_in_set "${fixture}" "${MATRIX_FIXTURES}" &&
      matrix_in_set "${mechanism}" "${MATRIX_MECHANISMS}" &&
      matrix_in_set "${harness}" "${MATRIX_HARNESSES}" ||
      bad_dim="${bad_dim}${at} "

    # `/` composes classes for a row with more than one vector (H5 is 3g and 4);
    # `-` is the whole cell, and means "not a trigger" rather than "unclassified".
    if [ "${vclass}" != '-' ]; then
      for c in ${vclass//\// }; do
        matrix_in_set "${c}" "${MATRIX_CLASSES}" || bad_class="${bad_class}${at}:${c} "
      done
    fi

    # `|` is an alternation, so every alternative is checked, not just the first.
    for s in ${stage//|/ }; do
      matrix_in_set "${s}" "${MATRIX_STAGES}" || bad_stage="${bad_stage}${at}:${s} "
    done

    if [ -n "${token}" ]; then
      case "${stage}" in
        # A multi-stage cell with a token cannot say which stage the token
        # belongs to, and a `dissolution` has no refusing stage to emit one.
        *'|'* | dissolution) bad_dissolution="${bad_dissolution}${at} " ;;
        *)
          for t in ${token//|/ }; do
            token_legal "${stage}" "${t}" || bad_token="${bad_token}${at}:${stage}/${t} "
          done
          ;;
      esac
    fi

    # `planted` and `outcome` are the harness's to fill. The ONE authored value
    # is an up-front `n/a`, and it is authored in both or in neither: a cell
    # planted `n/a` whose outcome is open would be scored as a live cell that
    # never ran (F-7).
    case "${planted}|${outcome}" in
      '|' | 'n/a|n/a') ;;
      *) bad_generated="${bad_generated}${at} " ;;
    esac

    # VA-1: altitude is verified GENERATED, not hand-authored. An authored value
    # here would make that claim uncheckable, so the check is that there is none.
    [ -z "${altitude}" ] || bad_altitude="${bad_altitude}${at} "

    # R-C: every `n/a` costs altitude, so every `n/a` states its reason in the
    # instantiation column — and a cell with no instantiation at all is a row
    # nobody has decided how to plant yet.
    case "${outcome}:${inst}" in
      'n/a:n/a '*) ;;
      'n/a:'*) bad_reason="${bad_reason}${at}(reason must open with 'n/a') " ;;
      *':') bad_reason="${bad_reason}${at}(no instantiation) " ;;
    esac
  done < <(matrix_rows "${file}")

  rig_assert_eq "fixture / mechanism / harness are from their vocabularies" "" "${bad_dim}"
  rig_assert_eq "every vector-class is a CPT-001 class, or '-' (no sixth class)" "" "${bad_class}"
  rig_assert_eq "every expected-stage is a stage or 'dissolution'" "" "${bad_stage}"
  rig_assert_eq "every expected-token is in the CLOSED vocabulary (token_legal)" "" "${bad_token}"
  rig_assert_eq "no dissolution or multi-stage cell claims a refusal token" "" "${bad_dissolution}"
  rig_assert_eq "planted/outcome are authored only as an up-front n/a, in both or neither" "" "${bad_generated}"
  rig_assert_eq "the authored altitude column is empty everywhere (VA-1)" "" "${bad_altitude}"
  rig_assert_eq "every n/a states a reason; every live cell states its instantiation" "" "${bad_reason}"

  # Completeness. Counting from the file cannot show an absent row, so the
  # expected shape is stated here and the file is measured against it.
  rig_assert_eq "the matrix carries exactly ${MATRIX_NROWS} rows (§ 5.6)" \
    "${MATRIX_NROWS}" "$(matrix_rows "${file}" | cut -f1 | sort -u | wc -l)"
  rig_assert_eq "every row carries ${MATRIX_CELLS_PER_ROW} DISTINCT (fixture, mechanism) cells" \
    "" "$(matrix_rows "${file}" | cut -f1-3 | sort | uniq -c |
      awk '$1 != 1 { printf "%s/%s/%s(x%d) ", $2, $3, $4, $1 }')"
  rig_assert_eq "cell count is ${MATRIX_NROWS} x ${MATRIX_CELLS_PER_ROW}" \
    "$((MATRIX_NROWS * MATRIX_CELLS_PER_ROW))" "$(matrix_rows "${file}" | wc -l)"
}
