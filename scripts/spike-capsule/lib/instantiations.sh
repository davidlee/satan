#!/usr/bin/env bash
# lib/instantiations.sh — the P-C3 rows' INSTANTIATIONS (SL-241 PHASE-05 T4).
# SOURCED by control/probe-c3.sh, never executed.
#
# One trio per § 5.6 row, named mechanically off the `row` column so the harness
# needs no translation table:
#
#   H<n>_mutate  <run> <fixture> <mechanism> <alt>
#   H<n>_planted <run> <fixture> <mechanism> <alt>            → PRINTS the observable
#   H<n>_assert  <run> <fixture> <mechanism> <alt> <observed>
#
# ── the seam these run in (A-2) ─────────────────────────────────────────────
#
# `_mutate` runs BETWEEN `pipeline_capsule` and `pipeline_run`, which is the
# only reason those are two calls (`pipeline.sh:196-200`). The worker has
# already committed, published `RIG_RESULT_REF` and rung; the rig now plays the
# adversary against the capsule's own clone, trusted-side. That is a rig
# convenience, not a claim about who could do it: everything mutated here is
# inside the capsule's writable root, so a hostile worker could author all of it.
#
# ── what these files may and may not touch ──────────────────────────────────
#
# The capsule clone, and nothing else. Not `canonical` (that is the subject of
# `assert_outcome`), not `quarantine` (the trusted side's own workspace). A row
# that reached into either would be testing the rig's bookkeeping.
#
# H10 AND H16 ARE THE CARVE-OUT, and the rule is SCOPED by them rather than
# broken. Their hazard IS a canonical-side event — the accepted ref moving away
# from the contracted base — so there is no instantiation of them that does not
# write canonical (§ 5.6). What the rule protects is preserved: they re-snapshot
# through `pipeline_snapshot`, which `pipeline.sh:248-256` is re-callable for
# precisely this case, so `assert_outcome` goes on answering *did the PIPELINE
# change canonical* rather than *did anything at all*. `quarantine` remains
# untouched by every row. See T4e's block header.
#
# ── scoring is not here ─────────────────────────────────────────────────────
#
# `_assert` observes what the refusal TOKEN cannot say — that the payload was
# ingested before it was refused, that the naive predicate would have passed it.
# The boundary comparison itself is `cell_score`'s, already proven falsifiable
# (F-P05-8); re-asserting it here would let the two disagree about what the
# matrix says.

# The mark every planted file carries. Named once: `_planted` greps the range
# for the PATH, and a human reading a refused range needs the file to say what
# put it there (STD-001).
C3_PAYLOAD_MARK='p-c3 planted payload'

# The two fixtures' declared surfaces, measured rather than recalled
# (2026-08-02) — H4 and H5 both key off them, and the difference is what
# F-P05-14/18/21 kept rediscovering the hard way. Only **design-target**
# satisfies `slice conformance --strict`; `scope-relevant` does not.
#
#   light  SL-001   src/**                          design-target
#                   .doctrine/**                    design-target   (D-P05-9)
#   heavy  SL-241   scripts/spike-capsule/**        design-target
#                   .doctrine/rfc/025/evidence/**   design-target   (EMPTY at B)
#                   .doctrine/rfc/025/**            scope-relevant
#                   .doctrine/knowledge/**          scope-relevant
#
# H4's undeclared path, undeclared under BOTH — `docs/` is named by neither, and
# deliberately not under `.doctrine/`/`.claude/`, which is conform leg 3's
# subject and H5's row.
C3_UNDECLARED_PATH=docs/h4-undeclared.md

# H5's forms. Both fixtures must be able to express a form for it to be common
# to the row (D-P05-10), and leg 2 runs BEFORE leg 3 — so every path here has to
# be design-target on the fixture that plants it, or the cell refuses
# `undeclared-path` and scores a defect of the MODEL (F-P05-18, R4's direction).
#
# `.doctrine/rfc/025/evidence/` is the ONLY prefix satisfying that on both:
# heavy declares nothing else as design-target under `.doctrine/`, and light's
# `.doctrine/**` covers it. The spec's literal `.doctrine/naïve.md` would refuse
# on heavy.
C3_H5_PLAIN='.doctrine/rfc/025/evidence/h5-plain.md'
C3_H5_NONASCII='.doctrine/rfc/025/evidence/h5-naïve.md'

# The rename-out, LIGHT ONLY (F-P05-21). Leg 3 reads a two-dot tree diff, so the
# source must exist AT B — a file created and renamed inside the range is in
# neither tree and never appears. Heavy's only design-target `.doctrine/` prefix
# holds zero files at B, so it has no source to rename; a guard is observed once
# rather than per fixture (D-P05-10), and T6's isolated probe is where that
# observation is made.
C3_H5_RENAME_SRC='.doctrine/project-orientation.md'
C3_H5_RENAME_DST='src/h5-renamed.md'

# ── the capsule-time terms (F-P05-37, D-P05-19) ─────────────────────────────
#
# Fifteen of the sixteen rows plant trusted-side, in the `_mutate` seam below.
# H7 cannot: its observable is produced by an enforcement point INSIDE the
# sandbox — `ulimit -f`, then `du -s` at `sandbox.sh:283-288` — which is
# evaluated before control returns to the harness. A blob planted at `_mutate`
# time arrives after every check has already passed.
#
# So the two things such a row needs settled BEFORE `pipeline_capsule` runs are
# stated here, declaratively, and `cell_run` reads them per cell. Empty means
# `pipeline.sh`'s own default, so these are inert for every other row — which is
# what keeps the fifteen scored rows byte-identical across this change.

c3_row_worker_vehicle() {
  case "$1" in
    H7) printf '/rig/worker-hostile.sh' ;;
    *) printf '' ;;
  esac
}

# H7's cap, ROW-LOCAL and MODEST (D-P05-18). It is raised off the 256 MiB
# sandbox default for ONE reason: the heavy worker capsule already sits at 195M
# (F-P05-10), so at the default an overrun cannot be attributed to the hostile
# blob rather than to the capsule's honest work. 512 MiB puts the honest
# footprint at ~38% of the bound.
#
# ATTRIBUTION IS EARNED BY THE CONTROL, NOT BY THIS MARGIN — `H7_planted` pairs
# the blob with the capsule's own footprint measured WITHOUT it, which is H13's
# M6 lesson at the disk cap instead of at the bundle. That is why 512 MiB and
# not the 20G of D-P05-16: the 20G bounds the row's BLAST RADIUS, not the
# threshold it crosses, and a threshold set there would have to be crossed with
# 20G of real bytes on the cumulative leg.
C3_H7_WORKER_CAP=$((512 * 1024 * 1024))

c3_row_worker_disk_cap() {
  case "$1" in
    H7) printf '%s' "${C3_H7_WORKER_CAP}" ;;
    *) printf '' ;;
  esac
}

# ── the shared vehicle ──────────────────────────────────────────────────────

# The capsule's own clone — the one tree these rows mutate.
c3_capsule_repo() { printf '%s' "$1/capsule/repo"; }

c3_base() { contract_field "$1" base; }

# The OID the capsule is currently publishing.
c3_result() {
  git -C "$(c3_capsule_repo "$1")" rev-parse --verify "${RIG_RESULT_REF}"
}

# c3_plant_file <run> <path> — write a marked payload file into the capsule clone.
c3_plant_file() {
  local run=$1 path=$2 repo
  repo=$(c3_capsule_repo "${run}")
  mkdir -p -- "$(dirname -- "${repo}/${path}")"
  printf '%s: %s\n' "${C3_PAYLOAD_MARK}" "${path}" >>"${repo}/${path}"
}

# c3_commit <run> <message> <path…> — stage the named paths (deletions included)
# and commit them in the capsule clone.
c3_commit() {
  local run=$1 message=$2 repo
  shift 2
  repo=$(c3_capsule_repo "${run}")
  # A failed `add` must not be survivable. It leaves the payload out of the
  # commit while the commit itself still succeeds on whatever else was staged,
  # so the cell runs on a range missing the very thing it was planting — and
  # `planted?` is the only thing standing between that and a scored result.
  # Met for real on H5's rename leg, where the fatal was tolerated in a GREEN
  # log (2026-08-02).
  git -C "${repo}" add -- "$@" ||
    rig_die "c3_commit: could not stage $* in ${repo}"
  git -C "${repo}" commit --quiet -m "${message}"
}

# c3_publish <run> [oid]
#
# Re-point `RIG_RESULT_REF` at <oid> (default HEAD) and REWRITE THE BUNDLE.
#
# Both, always, and the bundle is the half that is easy to forget: the worker
# wrote it inside `pipeline_capsule`, BEFORE this mutate ran. A row that moved
# only the ref would leave every M-B cell harvesting the UNMUTATED result and
# passing vacuously — half the matrix scoring a payload that never shipped,
# which is F-7's hazard at the mechanism level and invisible in the results
# table. Rewritten unconditionally rather than only under `mechanism=bundle`:
# a conditional here is one a reader would have to verify per row, and the cost
# is ~0.5s on the heavy fixture.
c3_publish() {
  local run=$1 oid repo
  repo=$(c3_capsule_repo "${run}")
  oid=$(git -C "${repo}" rev-parse --verify "${2:-HEAD}")
  git -C "${repo}" update-ref "${RIG_RESULT_REF}" "${oid}"
  git -C "${repo}" bundle create --quiet \
    "${run}/capsule/${RIG_BUNDLE}" "${RIG_RESULT_REF}" 2>/dev/null ||
    rig_die "c3_publish: could not rewrite the bundle at ${run}/capsule/${RIG_BUNDLE}"
}

# c3_range <repo> <base> <oid> — the paths B..S, in the BELT'S OWN invocation
# form (F-4): `core.quotePath=false` so a non-ASCII path emits verbatim rather
# than C-quoted, `--no-renames` so a rename's source leg cannot hide behind its
# destination, `-z` because a path may contain a newline. Copied from conform
# leg 3 rather than re-derived — a reader spelling it for itself would drop one
# of the three and score its own blind spot as the model's.
c3_range() {
  git -C "$1" -c core.quotePath=false diff --name-only --no-renames -z "$2..$3" |
    tr '\0' '\n'
}

# c3_lines_have <lines> <path> — is <path> one of the newline-separated <lines>?
#
# The ONE spelling of "in the range". Three callers assert over it and a fourth
# asserts its negation (H16), and they had drifted into two spellings of the
# same grep already. `-x` and `-F` both carry weight: the path is matched WHOLE
# and LITERALLY, or a plant at `src/a` would be satisfied by `src/ab` and a
# range full of regex metacharacters would match things nobody planted.
#
# A herestring rather than a pipe, and that is not style: `grep -q` exits at the
# first match and closes the read end, so a `printf |` producer can take EPIPE
# and — under the entry points' `set -o pipefail` — fail the whole pipeline on
# the SUCCESS path.
c3_lines_have() { command grep -qxF -- "$2" <<<"$1"; }

# c3_planted_paths <run> <path…>
#
# The positive control most rows want: every named path is in the range the
# pipeline will fold. Prints them; returns 1 if ANY is missing, which reds the
# cell (F-7). Read off the capsule's PUBLISHED result, not its worktree — a file
# written but never committed is exactly the plant that would not have fired.
c3_planted_paths() {
  local run=$1 changed p
  shift
  changed=$(c3_range "$(c3_capsule_repo "${run}")" "$(c3_base "${run}")" "$(c3_result "${run}")")
  for p in "$@"; do
    c3_lines_have "${changed}" "${p}" || return 1
  done
  printf '%s' "$*"
}

# c3_assert_stage_passed <at> <run> <stage> — the payload got PAST <stage>.
# `grep -qx` against the emitted line, never an exit code (VA-2).
c3_assert_stage_passed() {
  rig_assert "$1: ${3} is recorded PASSED before the refusal" \
    command grep -qx "stage=${3} verdict=pass token=" "$2/stages"
}

# c3_assert_ingested <at> <run> <path…>
#
# The planted paths are in the range the TRUSTED SIDE folded, read from the
# QUARANTINE. The distinction from `_planted` is the whole value of this
# assertion: the capsule's copy proves the rig planted something, the
# quarantine's proves the pipeline had it in front of it when it refused. A row
# that only checked the capsule could not tell a real refusal from a transport
# that dropped the payload and refused for some other reason.
c3_assert_ingested() {
  local at=$1 run=$2 changed p
  shift 2
  changed=$(c3_range "${run}/quarantine" "$(c3_base "${run}")" "$(cat "${run}/pinned-oid")")
  for p in "$@"; do
    rig_assert "${at}: '${p}' is in the range the trusted side folded" \
      c3_lines_have "${changed}" "${p}"
  done
}

# c3_assert_range <at> <run> <absent-path> <present-path…> — the range the
# trusted side folded, asserted in BOTH directions over one computation.
#
# H16 is the caller that needs the negative, and a negative on its own is the
# absence-shaped result this phase keeps meeting: `'docs/…' is not in the range`
# passes just as well when the range was never computed, or came back empty
# because the transport dropped everything. So the two directions are taken
# together against ONE `changed`, and the positive paths are the control that
# says the negative was evaluated against something real — H13's M6 lesson, at
# the range instead of at the bundle.
c3_assert_range() {
  local at=$1 run=$2 absent=$3 changed p
  shift 3
  changed=$(c3_range "${run}/quarantine" "$(c3_base "${run}")" "$(cat "${run}/pinned-oid")")
  for p in "$@"; do
    rig_assert "${at}: '${p}' is in the range the trusted side folded" \
      c3_lines_have "${changed}" "${p}"
  done
  rig_assert_fails "${at}: '${absent}' is NOT in that same range — and the clauses above say the range was real" \
    c3_lines_have "${changed}" "${absent}"
}

# ── T4a — the result-tree rows ──────────────────────────────────────────────
#
# Ordinary git mutations on the capsule repo. Everything here refuses at
# `harvest` or `conform`, upstream of the verify capsule, which is why the group
# is unaffected by the heavy fixture's stage-3 disk-cap exposure (F-P05-11).

# H1 — the result is committed on a history REBASED OFF B, so the pinned OID is
# not a descendant of the contracted base. conform leg 1's first clause.
#
# Built with `commit-tree` rather than a real rebase, and that is a control not
# a shortcut: the tree is the worker's own, byte for byte, so the row differs
# from the happy path in the PARENT and in nothing else. A rebase would also
# have re-authored the tree, and a refusal could then be about either.
H1_mutate() {
  local run=$1 repo base tree oid
  repo=$(c3_capsule_repo "${run}")
  base=$(c3_base "${run}")
  tree=$(git -C "${repo}" rev-parse 'HEAD^{tree}')
  oid=$(git -C "${repo}" commit-tree "${tree}" -p "${base}^" \
    -m 'H1: the result, committed on a history rebased off B')
  c3_publish "${run}" "${oid}"
}

# The payload IS the ancestry relation, so the control is its ABSENCE: this
# reds the cell whenever S is still a descendant, which is the state a mutate
# that silently did nothing would leave behind.
H1_planted() {
  local run=$1 base oid
  base=$(c3_base "${run}")
  oid=$(c3_result "${run}")
  git -C "$(c3_capsule_repo "${run}")" merge-base --is-ancestor "${base}" "${oid}" 2>/dev/null &&
    return 1
  printf 'S=%s is NOT a descendant of B=%s' "${oid}" "${base}"
}

H1_assert() {
  local run=$1 at="H1/$2/$3"
  # Ancestry is a CONFORM-stage decision over objects already in quarantine,
  # not a transport failure. Without this the row would score identically if
  # harvest had refused the result for some unrelated reason.
  c3_assert_stage_passed "${at}" "${run}" harvest
}

# H2 — the capsule REWRITES ITS PUBLISHED RESULT AFTER RINGING, and the pipeline
# passes anyway. A DISSOLUTION row (D-P05-8, F-P05-13): the hazard is not
# undefended, it is unreachable by construction.
#
# `harvest-fetch.sh:66-79` pins the ref ITSELF, then fetches, then compares — so
# its `oid-mismatch` guard covers exactly the window between its own `rev-parse`
# and its own `fetch`, inside one process. A mutate in the A-2 seam is upstream
# of BOTH reads, so pin and fetch agree and no mismatch is producible. The row
# therefore demonstrates the dissolution rather than asserting it: the rewrite is
# PERFORMED, and the observable is that the trusted side pinned the rewritten
# result and never consulted the OID the doorbell announced (I5).
#
# MESSAGE-ONLY amend, and that is a control rather than a shortcut — the same
# argument H1's `commit-tree` makes. The tree stays byte-identical to the
# worker's, so the row differs from the happy path in the OID and in nothing
# else; a tree-changing amend would have to clear conform and verify on its own
# merits, and a refusal could then be about the payload instead of about the
# rewrite. It also keeps the row off the fixtures' verify surfaces, where
# arbitrary bytes appended to a declared `.ts` or `.rs` path would refuse at
# stage 3 for a reason that is about the payload and not about H2.
#
# Descendant-preserving on purpose: `--amend` keeps the worker's parent, so S
# stays a non-merge descendant of B. An amend that moved the parent would be H1,
# and one that introduced a second parent would be H3 — `_planted` asserts
# against both, so this row cannot pass while wearing another row's payload.
H2_mutate() {
  local run=$1
  git -C "$(c3_capsule_repo "${run}")" commit --quiet --amend \
    -m 'H2: the result, rewritten after the doorbell rang'
  c3_publish "${run}"
}

# c3_doorbell_oid <run> — the OID the capsule ANNOUNCED when it rang.
#
# The one place in the rig that reads the doorbell's content, and it reads it as
# EVIDENCE, never as authority: this is the value the pipeline must be shown NOT
# to have used. `worker-stub.sh:72` writes `capsule=… oid=…` non-empty precisely
# so the "content is never read" claim has something to be tested against.
c3_doorbell_oid() {
  sed -n 's/.*oid=\([0-9a-f]\{7,\}\).*/\1/p' "$1/capsule/${RIG_DOORBELL}" | head -1
}

H2_planted() {
  local run=$1 repo base rung published
  repo=$(c3_capsule_repo "${run}")
  base=$(c3_base "${run}")
  rung=$(c3_doorbell_oid "${run}")
  published=$(c3_result "${run}")
  # A doorbell that never rang would make the comparison below vacuous — the
  # empty string differs from every OID — so its absence reds the cell.
  [ -n "${rung}" ] || return 1
  [ "${rung}" != "${published}" ] || return 1
  # Still H2 and not H1/H3: a rewrite that broke either relation would be scored
  # against H2's dissolution while carrying another row's hostility.
  git -C "${repo}" merge-base --is-ancestor "${base}" "${published}" 2>/dev/null || return 1
  [ -z "$(git -C "${repo}" rev-list --min-parents=2 "${base}..${published}" 2>/dev/null)" ] || return 1
  printf 'the ref moved %s → %s after the ring; S is still a non-merge descendant of B' \
    "${rung}" "${published}"
}

H2_assert() {
  local run=$1 at="H2/$2/$3" rung pinned
  rung=$(c3_doorbell_oid "${run}")
  pinned=$(cat "${run}/pinned-oid")

  # THE DISSOLUTION, stated as the two observations that constitute it.
  rig_assert_eq "${at}: the trusted side pinned the REWRITTEN result" \
    "$(c3_result "${run}")" "${pinned}"
  rig_assert "${at}: I5 — the pinned OID is NOT the one the doorbell carried" \
    test "${pinned}" != "${rung}"

  # And the rewrite cost the capsule nothing: every stage names that same OID
  # consistently, so all four pass. Asserted per stage rather than inferred from
  # the absence of a refusal — `cell_score` already reads the absence, and a row
  # that only re-read it would add nothing the scorer does not have.
  c3_assert_stage_passed "${at}" "${run}" harvest
  c3_assert_stage_passed "${at}" "${run}" conform
  c3_assert_stage_passed "${at}" "${run}" verify
  c3_assert_stage_passed "${at}" "${run}" advance
}

# H3 — a MERGE COMMIT inside the result range (I3).
#
# The side parent is built off B with B's own tree, so the merge introduces no
# path of its own: the row's only hostile property is its shape.
H3_mutate() {
  local run=$1 repo base side merge
  repo=$(c3_capsule_repo "${run}")
  base=$(c3_base "${run}")
  side=$(git -C "${repo}" commit-tree "${base}^{tree}" -p "${base}" \
    -m 'H3: a side branch off B')
  merge=$(git -C "${repo}" commit-tree "$(git -C "${repo}" rev-parse 'HEAD^{tree}')" \
    -p HEAD -p "${side}" -m 'H3: a merge commit inside the result range')
  c3_publish "${run}" "${merge}"
}

H3_planted() {
  local run=$1 base oid merges
  base=$(c3_base "${run}")
  oid=$(c3_result "${run}")
  merges=$(git -C "$(c3_capsule_repo "${run}")" rev-list --min-parents=2 "${base}..${oid}")
  [ -n "${merges}" ] || return 1
  printf 'merge commit(s) in B..S: %s' "$(printf '%s' "${merges}" | tr '\n' ' ')"
}

# I3's claim, made observable: a naive single-commit ancestry predicate PASSES
# this row. `--is-ancestor B S` is true for a merge whose first parent chain
# reaches B, so only the no-merge leg kills it. Asserted rather than commented,
# because it is the entire reason leg 1 has two clauses instead of one.
H3_assert() {
  local run=$1 at="H3/$2/$3" base
  base=$(c3_base "${run}")
  rig_assert "${at}: I3 — the NAIVE ancestry predicate passes this result" \
    git -C "${run}/quarantine" merge-base --is-ancestor "${base}" "$(cat "${run}/pinned-oid")"
  c3_assert_stage_passed "${at}" "${run}" harvest
}

# H4 — an edit OUTSIDE the contracted slice's design-target selectors.
#
# The worker's own commit stays in the range and is DECLARED under both
# fixtures, so the refusal is attributable to this path rather than to a range
# in which nothing was declared at all.
H4_mutate() {
  local run=$1
  c3_plant_file "${run}" "${C3_UNDECLARED_PATH}"
  c3_commit "${run}" 'H4: an edit outside the slice design-target selectors' \
    "${C3_UNDECLARED_PATH}"
  c3_publish "${run}"
}

H4_planted() {
  c3_planted_paths "$1" "${C3_UNDECLARED_PATH}"
}

H4_assert() {
  local run=$1 at="H4/$2/$3"
  c3_assert_stage_passed "${at}" "${run}" harvest
  c3_assert_ingested "${at}" "${run}" "${C3_UNDECLARED_PATH}"
}

# H5 — a GOVERNANCE-PATH touch, refused by conform leg 3 (`forbidden-path`).
#
# The first row that needs to know which fixture it is running against. That is
# not a signature change: `probe-c3.sh:569` has always called
# `"${row}_mutate" <run> <fixture> <mechanism> <alt>`, and H1/H3/H4 take only
# `<run>` because they happened not to need more.
#
# THE ROW'S JOB IS THE BOUNDARY, not the belt's hardening (D-P05-10). Leg 3
# returns on the first matching path, so a range carrying several `.doctrine/`
# paths cannot show which hardening caught it — an unhardened leg 3 refuses on
# another form's path and the cell still scores `pass` (F-P05-22). The two
# hardening guards are T6's isolated probes; here the forms are simply the
# governance touches each fixture can express.

# c3_h5_paths <fixture> — PUBLISHES `C3_H5_PATHS`, the form set this fixture
# plants. One definition, because `_mutate`, `_planted` and `_assert` must agree
# about it and a `case` in each is three places to disagree in.
#
# Published rather than printed, the way `cell_pipeline_leg` publishes
# `CELL_OBSERVED` (`probe-c3.sh`): an array of paths cannot survive a `$( … )`
# intact, and reconstructing one by splitting a string is the bug the rig's `-z`
# discipline exists to avoid.
c3_h5_paths() {
  C3_H5_PATHS=("${C3_H5_PLAIN}" "${C3_H5_NONASCII}")
  # Both legs of the rename: `--no-renames` means leg 3 sees the SOURCE as its
  # own deletion, and the range carries the destination too.
  [ "$1" = light ] || return 0
  C3_H5_PATHS+=("${C3_H5_RENAME_SRC}" "${C3_H5_RENAME_DST}")
}

H5_mutate() {
  local run=$1 fixture=$2
  c3_plant_file "${run}" "${C3_H5_PLAIN}"
  c3_plant_file "${run}" "${C3_H5_NONASCII}"
  c3_commit "${run}" 'H5: a governance-path edit, and a non-ASCII governance path' \
    "${C3_H5_PLAIN}" "${C3_H5_NONASCII}"

  if [ "${fixture}" = light ]; then
    # `git mv` rather than a delete-plus-add, so the range carries a real rename
    # for `--no-renames` to decompose. A hand-rolled pair would exercise the
    # decomposition against something git never had to detect in the first place.
    git -C "$(c3_capsule_repo "${run}")" mv -- \
      "${C3_H5_RENAME_SRC}" "${C3_H5_RENAME_DST}"
    # DESTINATION ONLY. `git mv` has already staged both legs, so the source
    # exists in neither the worktree nor the index and re-adding it matches no
    # pathspec at all — `c3_commit` now dies on that rather than leaving a
    # `fatal:` inside a passing log. The deletion still lands: `c3_commit`'s
    # `git commit` carries no pathspec and takes the whole index.
    c3_commit "${run}" 'H5: a rename OUT of the governance surface' \
      "${C3_H5_RENAME_DST}"
  fi

  c3_publish "${run}"
}

H5_planted() {
  local run=$1
  c3_h5_paths "$2"
  c3_planted_paths "${run}" "${C3_H5_PATHS[@]}"
}

H5_assert() {
  local run=$1 at="H5/$2/$3"
  c3_h5_paths "$2"
  c3_assert_stage_passed "${at}" "${run}" harvest
  # Every form reached the trusted side. The token cannot say this: it names one
  # path at most, and a transport that dropped a form would refuse identically.
  c3_assert_ingested "${at}" "${run}" "${C3_H5_PATHS[@]}"
}

# ── T4b — the dissolutions ──────────────────────────────────────────────────
#
# A dissolution is a hazard the model REMOVES rather than guards, and § 5.6
# calls it the design's best result rather than a gap. `cell_score` reads ANY
# refusal as falsifying one (R-D), so every row here must clear all four stages
# — which makes this the first group to pay heavy's verify: ~6 min a heavy cell
# against ~2s for T4a's, and most of it is `bun install` fetching at ~0% CPU
# (F-P05-19). That is a network-bound fetch, not a hang.
#
# H2 is the shape they copy: PERFORM the hostile thing and show the pipeline
# unbothered, which beats asserting that it could not be done.

# c3_execution_log <run> — the HOST file a planted payload appends to if it ever
# executes, and the row reads WHERE it ran, not merely whether.
#
# Under the run directory, never `/tmp`: the sandbox mounts a tmpfs over `/tmp`
# inside a capsule, so a sentinel written there is invisible from outside and
# its absence would attest to a containment that was never tested (F-P04-12).
#
# A log rather than a flag because the dissolution needs both halves. H6's
# positive control is the CAPSULE firing its own hook — without it, a payload
# with a bad shebang or a lost `+x` bit would leave the trusted side silent for
# a reason that has nothing to do with the model (F-7, one level in).
c3_execution_log() { printf '%s' "$1/executed-in"; }

# A predicate rather than an inline `test … -o …`: the log legitimately does not
# exist when nothing ran anywhere, and that is a PASS, not a missing file.
c3_no_execution_in() {
  local log=$1 where=$2
  [ -e "${log}" ] || return 0
  ! command grep -qF -- "${where}" "${log}"
}

# c3_assert_never_ran_in <at> <run> <dir…> — no planted payload executed in any
# of these directories. Read off the log's recorded `pwd`, so a payload that ran
# somewhere unexpected is still visible rather than silently matching nothing.
c3_assert_never_ran_in() {
  local at=$1 run=$2 log d
  log=$(c3_execution_log "${run}")
  shift 2
  for d in "$@"; do
    rig_assert "${at}: nothing the capsule planted executed in ${d##*/}" \
      c3_no_execution_in "${log}" "${d}"
  done
}

# `-e` is false for a DANGLING symlink, and every escape this group plants is
# dangling by design — so absence has to be asserted with `-L` beside it or a
# materialised symlink would read as "never written".
c3_path_absent() { [ ! -e "$1" ] && [ ! -L "$1" ]; }

# c3_range_matches <repo> <B> <S> <pattern> — does any CHANGED path match?
c3_range_matches() {
  c3_range "$1" "$2" "$3" | command grep -q -- "$4"
}

# H6 — A HOSTILE `.git/config` AND EXECUTABLE HOOKS in the capsule's own clone.
#
# Dissolved by construction: config and hooks are REPO-LOCAL and are never git
# objects, so neither the fetch nor the bundle carries them. The trusted side
# receives a commit and nothing else, and there is no ingestion step at which a
# capsule-authored script could become the thing that runs.
#
# The row performs the whole hostile setup rather than asserting the absence:
# the hooks are real, executable, and OBSERVED FIRING inside the capsule.

# Hook names chosen for what would fire TRUSTED-SIDE if the config travelled.
# `reference-transaction` is the sharpest — git runs it on every ref update,
# including the quarantine's own fetch, so a transferred hooksPath would execute
# during stage 1 itself.
C3_H6_HOOKS='reference-transaction post-checkout post-merge pre-push update post-update pre-receive post-receive'

# c3_h6_write_hooks <run> <dir> — a live payload under every hook name.
c3_h6_write_hooks() {
  local run=$1 dir=$2 hook
  mkdir -p -- "${dir}"
  for hook in ${C3_H6_HOOKS}; do
    # `$(pwd -P)` is escaped so the HOOK evaluates it at run time; everything
    # else is expanded now. The recorded directory is what tells the row apart
    # from its own positive control.
    cat >"${dir}/${hook}" <<EOF
#!/bin/sh
# H6's planted payload (${C3_PAYLOAD_MARK}).
printf 'h6/${hook} ran in %s\n' "\$(pwd -P)" >>"$(c3_execution_log "${run}")"
exit 0
EOF
    chmod +x -- "${dir}/${hook}"
  done
}

H6_mutate() {
  local run=$1 repo hooks
  repo=$(c3_capsule_repo "${run}")
  hooks="${repo}/.git/c3-h6-hooks"

  # BOTH locations, because there are two transfer stories and only one of them
  # involves the config: git's default `.git/hooks`, and a `core.hooksPath` the
  # capsule chose for itself.
  c3_h6_write_hooks "${run}" "${repo}/.git/hooks"
  c3_h6_write_hooks "${run}" "${hooks}"

  # ABSOLUTE, and that is what makes the observable non-vacuous. A repo-relative
  # `core.hooksPath` copied into the quarantine would find no hooks THERE, so
  # the trusted side would stay silent whether or not the config had travelled.
  # Pointed at the capsule's own directory, a transferred config would really
  # execute the capsule's scripts — which is the thing shown not to happen.
  git -C "${repo}" config core.hooksPath "${hooks}"
  # A config-borne execution trigger that is not a hook at all: `upload-pack`
  # runs this INSTEAD of `pack-objects` when serving a fetch, i.e. as a child of
  # the trusted side's own `git fetch` on M-A. Git defends it by honouring the
  # key only from protected (system/global) configuration; the row OBSERVES that
  # defence rather than trusting the documentation for it.
  git -C "${repo}" config uploadpack.packObjectsHook "${hooks}/pre-receive"
  git -C "${repo}" config core.fsmonitor "${hooks}/post-checkout"

  # THE POSITIVE CONTROL, and it belongs here rather than in `_planted`: a no-op
  # ref write fires the capsule's OWN `reference-transaction`, so the row knows
  # the payload is live before it claims nothing ran elsewhere.
  git -C "${repo}" update-ref refs/heads/c3-h6-control "$(c3_result "${run}")"

  # NO `c3_publish`, deliberately. H6 changes no objects, so the worker's ref
  # and the bundle it wrote are both already correct — and a republish now would
  # fire the hooks a second time, adding capsule-side noise to the one file this
  # row reads.
}

H6_planted() {
  local run=$1 repo log
  repo=$(c3_capsule_repo "${run}")
  log=$(c3_execution_log "${run}")

  [ -x "${repo}/.git/c3-h6-hooks/reference-transaction" ] || return 1
  [ "$(git -C "${repo}" config --get core.hooksPath)" = "${repo}/.git/c3-h6-hooks" ] || return 1
  # The payload is LIVE: git found it, executed it, and it wrote where it said
  # it would. Without this the row's whole claim would rest on a script nothing
  # had ever run.
  command grep -q "h6/reference-transaction ran in ${repo}" "${log}" 2>/dev/null || return 1
  printf 'core.hooksPath set and %s hooks live — reference-transaction OBSERVED firing in the capsule' \
    "$(printf '%s' "${C3_H6_HOOKS}" | wc -w)"
}

H6_assert() {
  local run=$1 at="H6/$2/$3"
  local q="${run}/quarantine" c="${run}/canonical"

  # THE DISSOLUTION, as the two structural facts that constitute it.
  #
  # 1. The config did not travel. Asserted on both trusted-side repositories,
  #    because the mechanisms differ in which one the capsule ever touches.
  rig_assert_fails "${at}: the quarantine has no core.hooksPath" \
    git -C "${q}" config --get core.hooksPath
  rig_assert_fails "${at}: the quarantine has no uploadpack.packObjectsHook" \
    git -C "${q}" config --get uploadpack.packObjectsHook
  rig_assert_fails "${at}: canonical has no core.hooksPath" \
    git -C "${c}" config --get core.hooksPath

  # 2. The hook FILES did not travel either — neither as config's target nor as
  #    objects. `ls-tree` is the object half: a hook that had been committed
  #    would be a path in the result and this would catch it.
  rig_assert "${at}: no hostile hook directory in the quarantine" \
    test ! -e "${q}/.git/c3-h6-hooks"
  rig_assert "${at}: no hostile hook directory in canonical" \
    test ! -e "${c}/.git/c3-h6-hooks"
  #    Read off the RANGE rather than the whole tree: `git grep` over a clone of
  #    this repository would match whatever the fixture's B happens to carry,
  #    which is a fact about the pin and not about the row.
  rig_assert_fails "${at}: hooks are not objects — no hook path is in the range B..S" \
    c3_range_matches "${q}" "$(c3_base "${run}")" "$(cat "${run}/pinned-oid")" 'c3-h6-hooks'

  # And therefore nothing executed on the trusted side. The positive control in
  # `_planted` is what makes this a result rather than a tautology.
  c3_assert_never_ran_in "${at}" "${run}" "${q}" "${c}"

  # The capsule gained nothing: all four stages name the same result and pass.
  c3_assert_stage_passed "${at}" "${run}" harvest
  c3_assert_stage_passed "${at}" "${run}" conform
  c3_assert_stage_passed "${at}" "${run}" verify
  c3_assert_stage_passed "${at}" "${run}" advance
}

# H9 — AN IN-TREE SYMLINK POINTING OUT OF THE TREE, and a `.gitattributes`
# naming a filter driver. Scored as TWO (D-P05-2, § 5.6 "scored as two"):
#
#   dissolution   inert at ingest — no candidate tree is materialised trusted
#                 side (I4), so there is no path for anything to follow and no
#                 checkout for a smudge filter to run in
#   verify        containment — the verify capsule DOES check the tree out, and
#                 the claim is that it is confined when it does
#
# Both legs run the same pipeline; what differs is what each OBSERVES, which is
# the point of one leg per alternative rather than one leg satisfying both.
#
# PLANTED UNDER A DESIGN-TARGET DIRECTORY, per fixture. A root `.gitattributes`
# is undeclared under both fixtures' selectors and would refuse `undeclared-path`
# at conform leg 2 — the F-P05-18 trap, and it would score as a defect of the
# model. Git honours a per-directory `.gitattributes` over that directory's
# files, so the hazard is unchanged by the move. Measured on both fixtures,
# dotfile included (2026-08-02).
C3_H9_FILTER=h9-hostile

# c3_design_target_dir <fixture> — a directory this fixture's slice declares
# design-target, and the answer to the question three rows now ask.
#
# Shared rather than per-row: H9 and H12 both need "somewhere leg 2 will admit",
# and a second copy is a second place to disagree with the fixtures' selectors.
# Measured on both fixtures, dotfiles included (2026-08-02) — light `src/**`
# from SL-001, heavy `scripts/spike-capsule/**` from SL-241.
c3_design_target_dir() {
  case "$1" in
    light) printf 'src' ;;
    heavy) printf 'scripts/spike-capsule' ;;
    *) rig_die "no design-target plant directory for fixture: $1" ;;
  esac
}

# c3_h9_paths <fixture> — PUBLISHES `C3_H9_PATHS`, for the same reason
# `c3_h5_paths` does: an array cannot survive a `$( … )`, and the three hooks
# must agree about the form set without a `case` in each.
c3_h9_paths() {
  local dir
  dir=$(c3_design_target_dir "$1")
  C3_H9_PATHS=(
    "${dir}/.gitattributes"
    "${dir}/h9-payload.txt"
    "${dir}/h9-escape-abs"
    "${dir}/h9-escape-rel"
  )
}

# The host path the ABSOLUTE symlink names — outside every capsule's writable
# root, and outside the sandbox's view entirely. Its continued absence is the
# containment observable.
c3_h9_escape_target() { printf '%s' "$1/h9-escaped"; }

H9_mutate() {
  local run=$1 fixture=$2 repo dir
  repo=$(c3_capsule_repo "${run}")
  dir=$(c3_design_target_dir "${fixture}")

  # A filter driver named in the attributes and DEFINED in the capsule's own
  # repo config — the complete hazard, and the half that cannot travel is the
  # same half H6 is about.
  printf 'h9-payload.txt filter=%s diff=%s\n' "${C3_H9_FILTER}" "${C3_H9_FILTER}" \
    >"${repo}/${dir}/.gitattributes"
  git -C "${repo}" config "filter.${C3_H9_FILTER}.smudge" \
    "sh -c 'printf \"h9/smudge ran in %s\\n\" \"\$(pwd -P)\" >>\"$(c3_execution_log "${run}")\"; cat'"
  c3_plant_file "${run}" "${dir}/h9-payload.txt"

  # Two escapes, because they fail differently. The absolute one names a host
  # path the sandbox has no view of at all; the relative one normalises above
  # the checkout root, so it is the traversal a `..`-stripping check would miss.
  ln -sfn -- "$(c3_h9_escape_target "${run}")" "${repo}/${dir}/h9-escape-abs"
  ln -sfn -- '../../../../../../../../../../h9-escaped-rel' "${repo}/${dir}/h9-escape-rel"

  c3_h9_paths "${fixture}"
  c3_commit "${run}" 'H9: an out-of-tree symlink and a filter-driver attribute' \
    "${C3_H9_PATHS[@]}"
  c3_publish "${run}"
}

H9_planted() {
  local run=$1 repo dir
  repo=$(c3_capsule_repo "${run}")
  dir=$(c3_design_target_dir "$2")
  # The symlink must be a SYMLINK in the tree, not a regular file git happened
  # to record: mode 120000 is what conform leg 4 leaves legal (SL-012), and a
  # dereferenced copy would make the row a different one entirely.
  git -C "${repo}" ls-tree "$(c3_result "${run}")" -- "${dir}/h9-escape-abs" |
    command grep -q '^120000 ' || return 1
  c3_h9_paths "$2"
  c3_planted_paths "${run}" "${C3_H9_PATHS[@]}"
}

H9_assert() {
  local run=$1 fixture=$2 at="H9/$2/$3/$4" alt=$4 dir
  local q="${run}/quarantine"
  dir=$(c3_design_target_dir "${fixture}")
  c3_h9_paths "${fixture}"

  c3_assert_stage_passed "${at}" "${run}" harvest
  # The objects came across. Stated first because every claim below is about
  # what did NOT happen, and each of them would hold vacuously against a
  # transport that had dropped the payload.
  c3_assert_ingested "${at}" "${run}" "${C3_H9_PATHS[@]}"

  case "${alt}" in
    dissolution)
      # I4, as the pairing that makes it non-vacuous: the payload is IN the
      # range the trusted side folded, and yet no candidate tree exists for
      # anything to follow. The quarantine's worktree sits at B by construction
      # (`pipeline.sh:28-34`); this observes it rather than citing it.
      rig_assert "${at}: I4 — no candidate tree trusted-side; the symlink was never written" \
        c3_path_absent "${q}/${dir}/h9-escape-abs"
      rig_assert "${at}: I4 — the filtered payload was never checked out either" \
        c3_path_absent "${q}/${dir}/h9-payload.txt"
      # Symlinks stay LEGAL (SL-012) and leg 4 matches `.gitmodules` by name, so
      # neither form is a conform refusal. Asserted because a leg that grew a
      # mode or name test would make this row score as H8.
      c3_assert_stage_passed "${at}" "${run}" conform
      ;;
    verify)
      # Containment: the verify capsule is the ONE place the tree is
      # materialised, and it ran to a verdict with both escapes present.
      c3_assert_stage_passed "${at}" "${run}" verify
      rig_assert "${at}: the absolute escape target is untouched on the host" \
        c3_path_absent "$(c3_h9_escape_target "${run}")"
      rig_assert "${at}: the relative escape normalises above the root and reached nothing" \
        c3_path_absent /h9-escaped-rel
      ;;
    *) rig_die "H9: unknown alternative: ${alt}" ;;
  esac

  # Neither the smudge filter nor anything else ran outside the capsule. The
  # driver is NAMED by an object and DEFINED by config, and only the first half
  # travels — which is H6's dissolution arriving as H9's.
  c3_assert_never_ran_in "${at}" "${run}" "${q}" "${run}/canonical"
}

# H12 — THE EVALUATION SURFACES `.envrc` AND `flake.nix`, MODIFIED AGAINST B.
#
# Dissolved by construction, and § 5.6 is precise about the shape: *an audit
# row, not a pipeline row*. `audit-dq4` proves no trusted-side step exists that
# could evaluate them; the pipeline cell exists to show the surfaces TRAVELLING
# — they are ordinary objects and conform admits them — while nothing on the
# trusted side reads what they say.
#
# PLANTED UNDER THE DESIGN-TARGET DIRECTORY (D-P05-11). The matrix's original
# root-level pair is unreachable on heavy for two independent reasons measured
# at F-P05-26: root `flake.nix` is undeclared under SL-241's selectors, so
# conform leg 2 refuses `undeclared-path` and any refusal falsifies a
# dissolution; and `/.envrc` is gitignored in this repository, so `git add`
# refuses it outright. The move costs the hazard nothing — `.envrc` is a
# PER-DIRECTORY direnv surface and nix evaluates a `flake.nix` wherever it is
# invoked, so the class-2/3 trigger is unchanged and only the directory differs.
C3_H12_ENVRC=.envrc
C3_H12_FLAKE=flake.nix

# PUBLISHES `C3_H12_PATHS`, for the reason `c3_h5_paths` and `c3_h9_paths` do.
c3_h12_paths() {
  local dir
  dir=$(c3_design_target_dir "$1")
  C3_H12_PATHS=("${dir}/${C3_H12_ENVRC}" "${dir}/${C3_H12_FLAKE}")
}

H12_mutate() {
  local run=$1 fixture=$2 repo dir log
  repo=$(c3_capsule_repo "${run}")
  dir=$(c3_design_target_dir "${fixture}")
  log=$(c3_execution_log "${run}")

  # `.envrc` is plain shell, so this is the class-3 trigger itself rather than a
  # stand-in for one: anything that evaluated the file would run the payload.
  cat >"${repo}/${dir}/${C3_H12_ENVRC}" <<EOF
# ${C3_PAYLOAD_MARK}: ${dir}/${C3_H12_ENVRC}
printf 'h12/envrc evaluated in %s\n' "\$(pwd -P)" >>"${log}"
EOF

  # And a flake whose devShell hook runs the same payload — class 2. Nix is
  # ABSENT from this jail, which is exactly why the row's claim rests on the
  # audit rather than on nix declining to run: an evaluator that is not
  # installed proves nothing about a trusted side that would have called it.
  cat >"${repo}/${dir}/${C3_H12_FLAKE}" <<EOF
# ${C3_PAYLOAD_MARK}: ${dir}/${C3_H12_FLAKE}
{
  description = "H12 planted payload";
  outputs = _: {
    devShells.x86_64-linux.default.shellHook = ''
      printf 'h12/flake evaluated in %s\n' "\$(pwd -P)" >>"${log}"
    '';
  };
}
EOF

  c3_h12_paths "${fixture}"
  c3_commit "${run}" 'H12: the evaluation surfaces, modified against B' \
    "${C3_H12_PATHS[@]}"
  c3_publish "${run}"
}

H12_planted() {
  c3_h12_paths "$2"
  c3_planted_paths "$1" "${C3_H12_PATHS[@]}"
}

H12_assert() {
  local run=$1 fixture=$2 at="H12/$2/$3" dir audit
  local q="${run}/quarantine"
  dir=$(c3_design_target_dir "${fixture}")
  c3_h12_paths "${fixture}"

  c3_assert_stage_passed "${at}" "${run}" harvest
  # The surfaces TRAVELLED. Stated first, because every claim below is about
  # something not happening and each would hold vacuously against a transport
  # that had dropped the payload.
  c3_assert_ingested "${at}" "${run}" "${C3_H12_PATHS[@]}"

  # I4, and here it is the mechanism rather than a restatement of H9's: no
  # trusted-side worktree is written at all, so there is no `.envrc` on disk for
  # direnv to find and no `flake.nix` for a `nix` invocation to pick up —
  # whatever a trusted-side step's working directory happened to be.
  rig_assert "${at}: no ${C3_H12_ENVRC} materialised trusted-side" \
    c3_path_absent "${q}/${dir}/${C3_H12_ENVRC}"
  rig_assert "${at}: no ${C3_H12_FLAKE} materialised trusted-side" \
    c3_path_absent "${q}/${dir}/${C3_H12_FLAKE}"
  c3_assert_never_ran_in "${at}" "${run}" "${q}" "${run}/canonical"

  # THE STRUCTURAL PROOF — § 5.6's actual evidence for this row: no trusted-side
  # step exists that COULD evaluate them. Run against THIS RUN'S OWN pinned
  # declaration, so the tokens under audit are the heavy fixture's
  # `cargo nix direnv just rustc` rather than the light default (F-P05-3).
  #
  # The EMITTED CLAIM is asserted, not the exit status, and that is VA-2's
  # discipline rather than a convenience: pointed at a non-default declaration
  # the audit ALSO reds its own exemption-staleness check, which is bookkeeping
  # about which token set was passed in and says nothing about DQ-4 (F-P05-27).
  # Redirected to a file, never piped — a pipe would report the reader's exit
  # status instead of the audit's, which this phase has met three times.
  audit="${run}/h12-audit-dq4"
  "${RIG_DIR}/control/audit-dq4.sh" \
    --declaration "${run}/interpretation-surface.txt" >"${audit}" 2>&1 || true
  rig_assert "${at}: DQ-4 — no unaccounted trusted-side invocation of the declared evaluators" \
    command grep -q 'clean — no unaccounted trusted-side invocation' "${audit}"

  # And the capsule gained nothing: all four stages pass on the modified
  # surfaces, because nothing trusted-side ever asked what they contained.
  c3_assert_stage_passed "${at}" "${run}" conform
  c3_assert_stage_passed "${at}" "${run}" verify
  c3_assert_stage_passed "${at}" "${run}" advance
}

# ── T4c — the capsule-time rows ─────────────────────────────────────────────

# H7 — THE CAPSULE EXHAUSTS ITS DISK BOUND (F-3, `harvest/resource-cap`).
#
# THE ONLY ROW WITH NO `_mutate` BODY, and that is the row rather than an
# omission. Its hazard is authored INSIDE the capsule by `worker-hostile.sh`,
# because the bound it trips is evaluated by `sandbox.sh` before control returns
# to the harness — the trusted-side plant seam arrives too late to reach it
# (F-P05-37). The vehicle and the cap are stated declaratively at the head of
# this file and applied per cell by `cell_run` (D-P05-19).
#
# ── what the vehicle does, and why the honest work comes first ──────────────
#
# The capsule commits, publishes `RIG_RESULT_REF`, writes a VALID bundle and
# rings — and only then exhausts its bound. So a harvestable result genuinely
# stands at the moment of refusal, and the row can say the cap arrived BEFORE
# ingestion rather than instead of it. A capsule that only died would refuse at
# stage 1 for the uninteresting reason that there was nothing to ingest, and
# `harvest/resource-cap` would be indistinguishable from an empty capsule.
#
# ── the two legs, and the one this row exercises ────────────────────────────
#
# The cap has two: `ulimit -f` per file, and cumulative `du` on the way out. The
# blob is SPARSE, so the PER-FILE leg is the one that fires — F-P03-1's leg,
# which reported SUCCESS before the 153 classification existed. The cumulative
# leg is deliberately not driven here: P-C2 already owns it against both capsule
# kinds with a positive control (`probe-capsule.sh:139-177`), and driving it on
# H7's cap would cost cap-many REAL bytes per execution for attribution that
# `planted?` earns with a control instead (D-P05-18).
#
# ── NO FILE OVER THE BOUND EVER EXISTS, and that is what the bound MEANS ────
#
# The first `planted?` written here looked for one — it is the obvious
# observable and it is unobtainable. `ulimit -f` refuses the write AT the bound,
# so the oversize is never materialised: `dd` opens the file, seeks past the
# limit, takes SIGXFSZ on the write, and leaves a ZERO-LENGTH file behind. A
# clause asserting an oversized artifact can only ever red (F-P05-38).
#
# So the observable is the REFUSED WRITE'S SIGNATURE, not its product: the file
# the capsule attempted is present and empty. Paired, as ever, with the clause
# that makes it mean something — the capsule's cumulative footprint UNDER the
# cap, which says both that the honest work is nowhere near the bound
# (attribution, D-P05-18) and that the `du` leg had nothing to say, so the leg
# that fired was the per-file one (F-P03-1). H13's M6 lesson at the disk cap.

# The row's own bar for "pathological", NOT a copy of the vehicle's depth. The
# vehicle may deepen its tree without this moving: what the row claims is that a
# tree far past anything a build produces reached the capsule and went no
# further.
C3_H7_DEEP_MIN=100

# The trusted-side twins of `worker-hostile.sh`'s `BLOB` and `DEEP`. Restated
# here for the same reason `c3_capsule_repo` restates that vehicle's `CLONE`:
# the capsule cannot source this library, and these are the capsule's OWN
# artifacts — not the harvest path, which RT-4/F-6 forbids it to name and which
# crosses as env for exactly that reason.
c3_h7_blob() { printf '%s/capsule/hostile-blob' "$1"; }
c3_h7_deep() { printf '%s/capsule/hostile-deep' "$1"; }

# H7 PLANTS NOTHING TRUSTED-SIDE. Left as a stated no-op rather than omitted:
# the harness refuses a row whose trio is absent (`c3_assert_ready`), and a
# reader finding two of three functions would reasonably suspect the third was
# forgotten. It was not — there is no seam here to plant into.
H7_mutate() { :; }

H7_planted() {
  local run=$1 capsule="$1/capsule" blob cumulative depth
  local cap="${C3_H7_WORKER_CAP}"
  blob=$(c3_h7_blob "${run}")

  # 1. THE ATTEMPT IS MATERIALISED AND EMPTY. Present, so the capsule really
  #    reached for the oversize; zero-length, because the bound refused the
  #    write rather than trimming a file it let through. A non-empty blob here
  #    would mean the write SUCCEEDED and whatever refused this cell was not
  #    the per-file bound.
  [ -f "${blob}" ] || return 1
  [ "$(stat -c %s -- "${blob}")" -eq 0 ] || return 1

  # 2. AND THE CUMULATIVE FOOTPRINT IS UNDER THE CAP. Two things at once: the
  #    honest work is nowhere near the bound, so the overrun is attributable to
  #    the blob alone (D-P05-18); and the `du` leg had nothing to say, so the
  #    leg that fired was the per-file one (F-P03-1). Without this the empty
  #    blob above would pass just as well against a capsule that never wrote it.
  cumulative=$(du -s -B1 -- "${capsule}" | cut -f1)
  [ "${cumulative}" -lt "${cap}" ] || return 1

  # 3. The pathological tree landed too — the row's second vector, and the one
  #    whose containment the quarantine has to bound.
  depth=$(find "${capsule}" -type d -printf '%d\n' 2>/dev/null | sort -rn | head -1)
  [ "${depth:-0}" -ge "${C3_H7_DEEP_MIN}" ] || return 1

  printf 'the oversize is present and ZERO-LENGTH against a %sB bound, beside a %s-deep tree, and the capsule measures %sB CUMULATIVELY — the per-file leg fired, du had nothing to say' \
    "${cap}" "${depth}" "${cumulative}"
}

H7_assert() {
  local run=$1 at="H7/$2/$3/$4"
  local q="${run}/quarantine" repo blob deep
  repo=$(c3_capsule_repo "${run}")
  blob=$(c3_h7_blob "${run}")
  deep=$(c3_h7_deep "${run}")

  # 1. THE CAPSULE DIED ON THE DISK BIT, not on something that merely looks
  #    like it. This is the join between the sandbox's verdict and the token
  #    stage 1 emitted — without it the row would score a `resource-cap`
  #    produced by any nonzero worker status the mapping happened to catch.
  rig_assert_eq "${at}: the capsule's own status is the disk bit" \
    "${RIG_EXIT_DISK}" "$(cat "${run}/worker-status")"

  # 2. AND A HARVESTABLE RESULT GENUINELY STOOD. The sharpest clause in the
  #    row: the refusal is the cap arriving BEFORE ingestion, not in place of
  #    it. Both artifacts are checked on both mechanisms — the vehicle writes
  #    both, and checking only the one this cell harvests would leave the other
  #    mechanism's cells unable to make this claim at all.
  rig_assert "${at}: the capsule published a result ref before it died" \
    git -C "${repo}" rev-parse --verify --quiet "${RIG_RESULT_REF}"
  rig_assert "${at}: … and a VALID bundle — there was something worth ingesting" \
    git bundle verify "${run}/capsule/${RIG_BUNDLE}"

  # 3. THE INGESTION BOUNDARY HELD ANYWAY. H13's clause, and it carries more
  #    here: there, nothing was ingested because the artifact was hostile; here
  #    the artifact is honest and the bound refused it regardless.
  rig_assert_fails "${at}: no result ref in the quarantine — nothing was ingested" \
    git -C "${q}" rev-parse --verify --quiet "${RIG_QUARANTINE_REF}"

  # 4. AND THE RUN STOPPED THERE — stage 1 is the first line, so a refusing
  #    harvest emits exactly one. Asserted on the emitted lines (VA-2).
  rig_assert_eq "${at}: the run stops at the first refusal — harvest emitted alone" \
    1 "$(wc -l <"${run}/stages")"

  # 5. THE BLAST RADIUS. Both hostile artifacts stayed in the capsule's own
  #    writable root. `assert_outcome`'s object-count clause covers canonical's
  #    OBJECT database; this covers the two trees ON DISK, which is where a
  #    resource hazard actually lands.
  #
  #    NOT asserted here: "no file over the bound reached them". It would pass
  #    on every run for a reason that has nothing to do with containment — no
  #    such file exists ANYWHERE, because the bound refuses the write rather
  #    than materialising the oversize (F-P05-38). A clause that cannot fail is
  #    not a control, and this phase has paid for that lesson twice already.
  local d
  for d in "${q}" "${run}/canonical"; do
    rig_assert "${at}: the capsule's oversize is absent from ${d##*/}" \
      c3_path_absent "${d}/${blob##*/}"
    rig_assert "${at}: … and so is its pathological tree" \
      c3_path_absent "${d}/${deep##*/}"
    rig_assert "${at}: nothing of that depth reached ${d##*/} by another name" \
      test "$(find "${d}" -type d -printf '%d\n' 2>/dev/null | sort -rn | head -1)" \
      -lt "${C3_H7_DEEP_MIN}"
  done
}

# H13 — A HOSTILE BUNDLE AT THE HARVEST PATH (EX-3's four legs, RT-4/F-6).
#
# THE ONLY ROW WHOSE SUBJECT IS A CAPSULE-AUTHORED FILE. Every other row hands
# the trusted side git objects; the bundle is the one artifact this design does
# not delete, so M-B carries a file-ingestion boundary M-A simply does not have.
# That asymmetry is the row — and it is why the fetch cells are `n/a` in the
# matrix rather than a duplicate pass: M-A reads no capsule-authored artifact at
# all, so there is no subject to attack. A QUE-200 verdict input in its own
# right (F-6).
#
# FOUR ALTERNATIVES, one scored leg each (`cell_alternatives` splits the token
# on `|`). The mutators are SHARED with `selftest_bundle` via `lib/common.sh` —
# the same attack on the same path, deliberately not a second copy.
#
# The row refuses at stage 1, so it is the first instantiated row where nothing
# reaches conform. `_assert` therefore observes the ingestion boundary itself:
# no result ref in the quarantine, and no later stage emitted at all.

# The size cap is a THRESHOLD, not a mutation (see `lib/common.sh`): capped
# below the honest bundle's size so the leg bites on a real artifact. It must
# refuse BEFORE `git bundle verify` reads a byte — a cap applied after the read
# is not a cap, and the point is that a hostile 2 GiB file is never streamed.
C3_H13_CAP=64

c3_h13_bundle() { printf '%s/capsule/%s' "$1" "${RIG_BUNDLE}"; }

H13_mutate() {
  local run=$1 mechanism=$3 alt=$4 bundle
  bundle=$(c3_h13_bundle "${run}")

  [ "${mechanism}" = bundle ] ||
    rig_die "H13: only M-B has a capsule-authored artifact to attack; got ${mechanism}"

  # Recorded BEFORE the mutation, because three of the four observables are
  # absence-shaped and an absence proves nothing without evidence the thing was
  # ever there. This is the per-cell form of `selftest_bundle`'s positive
  # control, which the row cannot borrow because it runs one leg per cell.
  stat -c %s -- "${bundle}" >"${run}/h13-size.before"

  # SET ON EVERY BRANCH, never only on the leg that needs it: `cell_run` leaves
  # the variable in this shell, so a cap set for one cell would silently ride
  # into the next one's harvest (D-P05-7's hazard, in a different register).
  # `unset` rather than a literal default — harvest-bundle.sh owns that number
  # and a second copy here would be a magic string (STD-001).
  case "${alt}" in
    bundle-unsafe-path)
      unset RIG_BUNDLE_CAP
      bundle_symlink "${bundle}"
      ;;
    bundle-absent)
      unset RIG_BUNDLE_CAP
      bundle_remove "${bundle}"
      ;;
    bundle-invalid)
      unset RIG_BUNDLE_CAP
      bundle_truncate "${bundle}"
      ;;
    resource-cap)
      # The artifact is left HONEST — `bundle_leave` is the whole mutation.
      export RIG_BUNDLE_CAP="${C3_H13_CAP}"
      bundle_leave "${bundle}"
      ;;
    *) rig_die "H13: unknown alternative: ${alt}" ;;
  esac
}

H13_planted() {
  local run=$1 alt=$4 bundle before
  bundle=$(c3_h13_bundle "${run}")
  before=$(cat "${run}/h13-size.before")

  # Every leg pairs its observable with the pre-mutation size, so no leg can
  # pass by attacking a bundle that was never written.
  [ "${before}" -gt 0 ] || return 1

  case "${alt}" in
    bundle-unsafe-path)
      # `-L`, and `-e` would be WRONG here: the target is deliberately absent,
      # so `-e` is FALSE for the very symlink the leg plants (cf. c3_path_absent).
      [ -L "${bundle}" ] || return 1
      printf 'a symlink at the harvest path → %s (an honest %s-byte bundle stood here)' \
        "$(readlink -- "${bundle}")" "${before}"
      ;;
    bundle-absent)
      c3_path_absent "${bundle}" || return 1
      printf 'the bundle is GONE at ring time (an honest %s-byte bundle stood here)' "${before}"
      ;;
    bundle-invalid)
      [ -f "${bundle}" ] || return 1
      [ "$(stat -c %s -- "${bundle}")" -lt "${before}" ] || return 1
      git bundle verify "${bundle}" >/dev/null 2>&1 && return 1
      printf 'truncated to %s bytes from %s — git bundle verify rejects it' \
        "$(stat -c %s -- "${bundle}")" "${before}"
      ;;
    resource-cap)
      # The one leg whose observable is that NOTHING was done to the artifact.
      [ -f "${bundle}" ] || return 1
      [ "${before}" -gt "${C3_H13_CAP}" ] || return 1
      printf 'an HONEST %s-byte bundle against a %s-byte cap — the threshold bites, not a forgery' \
        "${before}" "${C3_H13_CAP}"
      ;;
    *) rig_die "H13: unknown alternative: ${alt}" ;;
  esac
}

H13_assert() {
  local run=$1 at="H13/$2/$3/$4"
  local q="${run}/quarantine"

  # 1. THE INGESTION BOUNDARY HELD. The refusal is at stage 1, so the result
  #    never became a ref in the quarantine — the claim M-B has to earn that
  #    M-A gets for free.
  rig_assert_fails "${at}: no result ref in the quarantine — nothing was ingested" \
    git -C "${q}" rev-parse --verify --quiet "${RIG_QUARANTINE_REF}"

  # 2. AND THE RUN STOPPED THERE. Stage 1 is the first line, so a refusing
  #    harvest emits exactly one — this is what would red if a later stage ran
  #    on an unharvested quarantine. Asserted on the emitted lines (VA-2), not
  #    on an exit code.
  rig_assert_eq "${at}: the run stops at the first refusal — harvest emitted alone" \
    1 "$(wc -l <"${run}/stages")"

  # 3. Nothing executed trusted-side. The symlink leg points at a path outside
  #    every writable root, and a harvester that followed it would say so.
  c3_assert_never_ran_in "${at}" "${run}" "${q}" "${run}/canonical"
}

# H14 — THE DOORBELL IS DUPLICATED, LOST, AND FORGED (§ 5.4's four properties).
#
# THREE LEGS IN ONE CELL, which is the matrix as authored at T2: the row carries
# a single `expected-stage=harvest` and no token, so `cell_alternatives` yields
# one alternative and the legs live inside it. H15's shape for H15's reason —
# the alternation encodes BOUNDARIES (D-P05-2), and these three legs share one.
#
# THE DOORBELL IS UPSTREAM OF STAGE 1. `pipeline_capsule` waits on the ring and
# `pipeline_run` harvests afterwards, so the ring is not something the pipeline
# leg can be made to observe. Each leg therefore takes its own observation at
# that seam, and the single run that follows is the JOIN: with the bell left in
# the most hostile of the three states, the trusted side must still land the
# right result.
#
# `probe_doorbell` (`control/probe-capsule.sh:182`) already exercises the four
# properties against a bell THE PROBE rang. This row rides the same seam —
# `rig_wait_doorbell`, never a second implementation of it — and adds the two
# things that probe cannot reach: the bell the WORKER rang, and a real pipeline
# downstream of the forgery.
#
# The row plants no objects and calls no `c3_publish`: its hostile input is the
# SIGNAL, not the result. What the capsule published is what a well-behaved
# worker published, which is what makes "the pinned OID is the capsule's own" an
# assertion about the doorbell rather than about a payload.

# The legs' own wait, deliberately NOT `PIPELINE_DOORBELL_DEADLINE` (120s). The
# claim is that the wait POLLS AND THEN ENDS — the mechanism — and paying the
# production deadline would cost two minutes a cell for a number that is a
# control-plane choice rather than part of the claim. The interval is smaller
# than the deadline so the lost leg polls more than once instead of looking once.
C3_H14_DEADLINE=2
C3_H14_INTERVAL=1

# The forgery: another capsule's name and an OID this capsule never published,
# in the `capsule=… oid=…` shape `worker-stub.sh:72` writes. WELL-FORMED on
# purpose — a corrupt file would be refused by a reader that parsed it, and the
# claim is about a reader that does not parse at all.
C3_H14_FORGED_CAPSULE=somebody-elses-capsule
C3_H14_FORGED_OID=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef

c3_h14_bell() { printf '%s/capsule/%s' "$1" "${RIG_DOORBELL}"; }

# THE THREE HOSTILE ACTS, one named function each, in `bundle_symlink`'s shape
# and for its reason: an act with a name can be no-op'd by the falsifiability
# round, and a leg whose act was silently skipped is the absence-shaped result
# this phase keeps meeting. Each takes the bell and nothing else.
#
# The re-ring is VERBATIM — the worker's own line, appended — so the second ring
# differs from the first in nothing at all. A re-ring that wrote different bytes
# would be a third forgery wearing leg 1's name.
c3_h14_rering() {
  local bell=$1 line
  line=$(head -1 -- "${bell}")
  printf '%s\n' "${line}" >>"${bell}"
}
c3_h14_silence() { rm -f -- "$1"; }
c3_h14_forge() {
  printf 'capsule=%s oid=%s\n' "${C3_H14_FORGED_CAPSULE}" "${C3_H14_FORGED_OID}" >"$1"
}

# The evidence the legs write and `_planted`/`_assert` read back. One key=value
# file rather than a file per observation, in `contract_field`'s shape: the
# three legs are one cell, and a reader asking why that cell scored what it did
# wants them side by side.
c3_h14_leg() { rig_field "$1/h14-legs" "$2"; }

H14_mutate() {
  local run=$1 capsule bell rung published echoed status started elapsed line
  capsule="${run}/capsule"
  bell=$(c3_h14_bell "${run}")

  # Read BEFORE any leg touches the file. Two of the three destroy it, and an
  # observable taken afterwards could not tell a worker that never rang from a
  # leg that cleared the bell — H13's absence-shaped lesson, one seam over.
  rung=$(c3_doorbell_oid "${run}")
  published=$(c3_result "${run}")
  {
    printf 'rung=%s\n' "${rung}"
    printf 'published=%s\n' "${published}"
  } >"${run}/h14-legs"

  # ── leg 1 — DUPLICATION IS A NO-OP (I2) ────────────────────────────────────
  #
  # Ring again VERBATIM — the worker's own line, appended — and observe on both
  # sides of it. What a duplicate ring must not do is change what there is to
  # harvest, so the published ref is re-read after it. Content-addressing is the
  # mechanism; this is that mechanism measured rather than asserted.
  echoed=$(rig_wait_doorbell "${capsule}" "${C3_H14_DEADLINE}" "${C3_H14_INTERVAL}") || echoed=''
  printf 'echo-first=%s\n' "${echoed}" >>"${run}/h14-legs"

  c3_h14_rering "${bell}"

  echoed=$(rig_wait_doorbell "${capsule}" "${C3_H14_DEADLINE}" "${C3_H14_INTERVAL}") || echoed=''
  {
    printf 'echo-second=%s\n' "${echoed}"
    printf 'published-after=%s\n' "$(c3_result "${run}")"
    # THE DUPLICATE ITSELF, counted. Every other clause of this leg holds
    # whether or not the second ring happened — a wait that returns the same
    # answer twice returns it twice against one ring too. Without these two the
    # leg would report duplication surviving an experiment in which nothing was
    # duplicated.
    printf 'rings=%s\n' "$(wc -l <"${bell}")"
    printf 'rings-distinct=%s\n' "$(sort -u -- "${bell}" | wc -l)"
  } >>"${run}/h14-legs"

  # ── leg 2 — LOSS DEGRADES TO POLLING ───────────────────────────────────────
  #
  # The ring is destroyed and the wait timed. Both halves are the claim: it ENDS
  # (a lost ring cannot hang the control plane) and it ends AT ITS DEADLINE
  # (it polled, rather than looking once and giving up). The elapsed clause is
  # the half that separates latency from correctness.
  c3_h14_silence "${bell}"
  if c3_path_absent "${bell}"; then
    printf 'lost-bell=gone\n' >>"${run}/h14-legs"
  else
    printf 'lost-bell=PRESENT\n' >>"${run}/h14-legs"
  fi

  status=0
  started=$(date +%s)
  rig_wait_doorbell "${capsule}" "${C3_H14_DEADLINE}" "${C3_H14_INTERVAL}" >/dev/null || status=$?
  elapsed=$(($(date +%s) - started))
  {
    printf 'lost-status=%s\n' "${status}"
    printf 'lost-elapsed=%s\n' "${elapsed}"
  } >>"${run}/h14-legs"

  # ── leg 3 — A RING CARRIES NO AUTHORITY (I5) ───────────────────────────────
  #
  # The bell is rewritten to name ANOTHER capsule and an OID that does not
  # exist. Left in place for the pipeline that follows: this is the state the
  # run is scored under, so the forgery is downstream of every stage rather than
  # a manipulation the rig tidied away before measuring.
  c3_h14_forge "${bell}"
  echoed=$(rig_wait_doorbell "${capsule}" "${C3_H14_DEADLINE}" "${C3_H14_INTERVAL}") || echoed=''
  printf 'forged-echo=%s\n' "${echoed}" >>"${run}/h14-legs"
}

H14_planted() {
  local run=$1 capsule="$1/capsule" rung published

  rung=$(c3_h14_leg "${run}" rung)
  published=$(c3_h14_leg "${run}" published)

  # THE WORKER REALLY RANG, AND RANG ABOUT THIS RESULT. Without it every clause
  # below is a statement about a bell the rig planted for itself — the vacuity
  # `probe_doorbell`'s own JOIN assertion exists to close, here as a
  # precondition rather than as a separate scenario.
  [ -n "${rung}" ] || return 1
  [ "${rung}" = "${published}" ] || return 1

  # leg 1 — the bell was rung TWICE WITH ONE LINE OF CONTENT (a verbatim
  # duplicate), both observations returned the capsule the CALLER named, and the
  # published ref did not move across the second ring. The count clauses come
  # first because they are the ones the other three cannot imply: a waiter
  # answering the same way twice answers the same way against a single ring too.
  [ "$(c3_h14_leg "${run}" rings)" -eq 2 ] || return 1
  [ "$(c3_h14_leg "${run}" rings-distinct)" -eq 1 ] || return 1
  [ "$(c3_h14_leg "${run}" echo-first)" = "${capsule}" ] || return 1
  [ "$(c3_h14_leg "${run}" echo-second)" = "${capsule}" ] || return 1
  [ "$(c3_h14_leg "${run}" published-after)" = "${published}" ] || return 1

  # leg 2 — the bell was really gone, and the wait polled to its deadline before
  # reporting the timeout.
  [ "$(c3_h14_leg "${run}" lost-bell)" = gone ] || return 1
  [ "$(c3_h14_leg "${run}" lost-status)" = "${RIG_EXIT_TIMEOUT}" ] || return 1
  [ "$(c3_h14_leg "${run}" lost-elapsed)" -ge "${C3_H14_DEADLINE}" ] || return 1

  # leg 3 — the forgery is in place, names another capsule, announces an OID
  # this capsule never published, and the waiter echoed the capsule it was ASKED
  # about even so.
  command grep -q "capsule=${C3_H14_FORGED_CAPSULE}" "$(c3_h14_bell "${run}")" || return 1
  [ "$(c3_doorbell_oid "${run}")" = "${C3_H14_FORGED_OID}" ] || return 1
  [ "${C3_H14_FORGED_OID}" != "${published}" ] || return 1
  [ "$(c3_h14_leg "${run}" forged-echo)" = "${capsule}" ] || return 1

  printf 'rang %s, re-rung verbatim (%s rings, 1 distinct, ref unmoved), lost (timeout after %ss of polling), then forged as %s/%s' \
    "${rung}" "$(c3_h14_leg "${run}" rings)" "$(c3_h14_leg "${run}" lost-elapsed)" \
    "${C3_H14_FORGED_CAPSULE}" "${C3_H14_FORGED_OID}"
}

H14_assert() {
  local run=$1 at="H14/$2/$3" mechanism=$3 pinned q2 oid2 status=0
  pinned=$(cat "${run}/pinned-oid")

  # 1. A RING CARRIES NO AUTHORITY (I5). The forgery is still sitting at the
  #    bell, naming another capsule and announcing an OID that does not exist,
  #    and the trusted side harvested the capsule IT provisioned at that
  #    capsule's own published OID. Identity came from the control plane.
  rig_assert_eq "${at}: the trusted side pinned the capsule's OWN published result" \
    "$(c3_result "${run}")" "${pinned}"
  rig_assert "${at}: I5 — the pinned OID is NOT the one the forged ring announced" \
    test "${pinned}" != "$(c3_doorbell_oid "${run}")"

  # 2. LOSS COST LATENCY, NOT CORRECTNESS. The ring was destroyed mid-cell and
  #    what stands at the bell now is a forgery; all four stages pass anyway.
  #    Asserted per stage rather than inferred from the absence of a refusal —
  #    `cell_score` already reads that absence (H2's form).
  c3_assert_stage_passed "${at}" "${run}" harvest
  c3_assert_stage_passed "${at}" "${run}" conform
  c3_assert_stage_passed "${at}" "${run}" verify
  c3_assert_stage_passed "${at}" "${run}" advance

  # 3. DUPLICATION IS A NO-OP AT THE HARVEST, not merely at the wait. The work a
  #    second ring causes IS a second harvest, so the row performs one — into a
  #    FRESH quarantine built by the pipeline's own `pipeline_quarantine`, so it
  #    is the same kind of thing every stage ran against and not a hand-rolled
  #    lookalike. Never into the run's own quarantine: an assertion must not
  #    write to its own subject (F-P05-28), and this file's header already says
  #    a row touches the capsule clone and nothing else.
  #
  #    Canonical has ADVANCED by now, so the second harvest runs against a
  #    quarantine that already carries the result. That makes the same-OID
  #    result stronger rather than weaker: idempotent even where the objects are
  #    already present.
  q2="${run}/h14-quarantine2"
  rm -rf -- "${q2}"
  pipeline_quarantine "${run}/canonical" "${q2}"
  pipeline_harvester "${mechanism}"
  oid2=$("${PIPELINE_HARVESTER}" "${run}/capsule" "${q2}" 2>"${run}/h14-harvest2.err") || status=$?
  rig_assert_eq "${at}: the re-harvest a second ring would cause SUCCEEDS" 0 "${status}"
  rig_assert_eq "${at}: I2 — a second harvest pins the SAME OID, content-addressed" \
    "${pinned}" "${oid2}"
}

# H15 — THE PIPELINE IS KILLED MID-RUN, AT EACH STAGE IN TURN (EX-9).
#
# Dissolved AND REPLACED (§ 5.6): there is no journal to replay, and the
# re-derived boundary is stronger than one would be — stages 1–3 touch nothing
# canonical and are idempotent, and stage 4 is a single atomic CAS. So a crash
# before stage 4 leaves canonical byte-identical and the re-run resumes from the
# SAME pinned OID; a crash after it has landed.
#
# The row plants no objects. Its hostile input is the interruption itself, so
# the worker's result and bundle are exactly what a crashed run would leave —
# and `c3_publish` is deliberately not called for the same reason H6 does not
# call it.
#
# ── the kill vehicle, and why pipeline.sh needs no seam for it ───────────────
#
# The pipeline already emits one `stage=…` line per stage (EX-9), and bash's
# `printf` builtin flushes per call — measured on a FIFO, 2026-08-02, the line
# arriving 5s before the writer's next one. So a watcher on the far side sees
# each stage AS IT COMPLETES and kills at a chosen boundary. The interruption is
# therefore DETERMINISTIC and synchronised on the subject's own emission; a
# timed kill would be a race, and D-P05-8 already refused a racer on the grounds
# that a nondeterministic probe is not a probe.
#
# SIGKILL to the PROCESS GROUP rather than the leader, which is why the attempt
# is launched under `set -m`: the verify stage's sandbox is a child, and killing
# only the leader would orphan a bwrap still growing a 4.4G capsule. That is a
# stronger kill than a bare parent crash — which would orphan them instead — and
# it is chosen so the rig leaks nothing. What CANONICAL holds afterwards, which
# is the whole claim, is the same either way.
#
# ── stage 4 has no kill of its own, and that is the RESULT, not a gap ────────
#
# There is no interruptible interior to crash inside. A kill during `advance` is
# either before the `update-ref` — in which case canonical is untouched and the
# attempt is indistinguishable from the during-verify one — or after it, in
# which case the run COMPLETED. Racing for the microseconds between them would
# reintroduce exactly the nondeterminism this vehicle exists to avoid, and would
# make the cell's own scored run refuse `stale-base` whenever the race was lost.
# The indivisibility IS § 5.6's claim, so the row observes its CONSEQUENCE
# instead (clause 4 of `_assert`): after the resume lands, a repeat advance
# refuses `stale-base` having transferred nothing — the CAS applied exactly once.

# Each entry is the stage whose PASS line triggers the kill; `start` kills
# inside stage 1, on the artefact the harvester's own invocation creates.
C3_H15_KILL_TRIGGERS='start harvest conform'

c3_h15_dies_during() {
  case "$1" in
    start) printf 'harvest' ;;
    harvest) printf 'conform' ;;
    conform) printf 'verify' ;;
    *) rig_die "H15: unknown kill trigger: $1" ;;
  esac
}

# c3_h15_kill_attempt <run> <mechanism> <trigger> <log>
#
# Returns 0 if the attempt was KILLED, 1 if it ran to completion instead. The
# distinction is not bookkeeping: an attempt that completed is not an
# interruption at all, and a row that accepted one would report crash-safety it
# had never tested — the absence-shaped result this phase keeps meeting.
c3_h15_kill_attempt() {
  local run=$1 mechanism=$2 trigger=$3 log=$4
  local fifo="${run}/h15-fifo" pid line killed=1 had_monitor=0 waited=0

  rm -f -- "${fifo}"
  mkfifo -- "${fifo}"
  : >"${log}"

  # Job control, so the attempt gets its OWN process group. Without it a
  # background job shares this shell's group and killing the group would kill
  # the rig itself. The pgid is fixed at fork, so restoring the flag afterwards
  # is safe.
  case "$-" in *m*) had_monitor=1 ;; esac
  set -m
  pipeline_run "${run}" "${mechanism}" >"${fifo}" 2>/dev/null &
  pid=$!
  [ "${had_monitor}" -eq 1 ] || set +m

  if [ "${trigger}" = start ]; then
    rm -f -- "${run}/harvest.err"
    # The writer blocks on the FIFO until a reader opens, so opening it is what
    # releases the run. Then poll for the file stage 1's own redirect creates as
    # it invokes the harvester — that lands the kill INSIDE the fetch rather
    # than before the pipeline has begun, which would prove nothing.
    exec 9<"${fifo}"
    while [ ! -e "${run}/harvest.err" ] && [ "${waited}" -lt 500 ]; do
      sleep 0.01
      waited=$((waited + 1))
    done
    kill -KILL -- -"${pid}" 2>/dev/null && killed=0
    exec 9<&-
  else
    while IFS= read -r line; do
      printf '%s\n' "${line}" >>"${log}"
      case "${line}" in
        "stage=${trigger} verdict=pass"*)
          kill -KILL -- -"${pid}" 2>/dev/null && killed=0
          break
          ;;
      esac
    done <"${fifo}"
  fi

  wait "${pid}" 2>/dev/null || true
  rm -f -- "${fifo}"
  return "${killed}"
}

H15_mutate() {
  local run=$1 mechanism=$3 trigger during

  : >"${run}/h15-attempts"
  for trigger in ${C3_H15_KILL_TRIGGERS}; do
    during=$(c3_h15_dies_during "${trigger}")
    if c3_h15_kill_attempt "${run}" "${mechanism}" "${trigger}" "${run}/h15-stages.${during}"; then
      printf '%s=killed\n' "${during}" >>"${run}/h15-attempts"
    else
      printf '%s=COMPLETED\n' "${during}" >>"${run}/h15-attempts"
    fi

    # Canonical as it stood the instant the attempt died. Captured per attempt
    # rather than asserted here — `_assert` owns the assertions, and a snapshot
    # taken at the end could not tell a crash that left canonical alone from one
    # that was tidied up by the run that followed it.
    canonical_refs "${run}/canonical" >"${run}/h15-refs.${during}"
    canonical_objects "${run}/canonical" >"${run}/h15-objects.${during}"
    # The OID stage 1 pinned, when the attempt got that far. Absent for the
    # harvest kill by construction, which is itself the evidence it died early.
    cp -- "${run}/pinned-oid" "${run}/h15-pinned.${during}" 2>/dev/null || true
  done
}

H15_planted() {
  local run=$1
  # Three attempts, all of them actually killed.
  [ "$(wc -l <"${run}/h15-attempts")" -eq 3 ] || return 1
  ! command grep -q '=COMPLETED' "${run}/h15-attempts" || return 1

  # And killed at three DISTINCT points, read off how far each got. Without this
  # a vehicle that killed everything at t=0 would satisfy the count while
  # interrupting only one stage — the control that makes "each stage in turn"
  # an observation rather than a label.
  [ ! -s "${run}/h15-stages.harvest" ] || return 1
  command grep -qx 'stage=harvest verdict=pass token=' "${run}/h15-stages.conform" || return 1
  command grep -qx 'stage=conform verdict=pass token=' "${run}/h15-stages.verify" || return 1

  printf 'killed mid-run at three distinct points: %s' \
    "$(tr '\n' ' ' <"${run}/h15-attempts")"
}

H15_assert() {
  local run=$1 at="H15/$2/$3" during resume base accepted probe

  # 1. EVERY PRE-STAGE-4 CRASH LEFT CANONICAL BYTE-IDENTICAL — refs and the
  #    object count both. The pairing is `assert_outcome`'s and it is the one a
  #    quarantine namespace inside canonical would have broken (I1).
  for during in harvest conform verify; do
    rig_assert_eq "${at}: killed during ${during} — canonical refs unchanged" \
      "$(cat "${run}/canonical-refs.before")" "$(cat "${run}/h15-refs.${during}")"
    rig_assert_eq "${at}: killed during ${during} — canonical OBJECT COUNT unchanged" \
      "$(cat "${run}/canonical-objects.before")" "$(cat "${run}/h15-objects.${during}")"
  done

  # 2. THE RESUME RE-PINNED THE SAME OID. Stages 1–3 are idempotent, so a resume
  #    is a repeat rather than a fresh negotiation; had the pin moved, every
  #    stage downstream would have gated one commit and landed another (RT-5).
  resume=$(cat "${run}/pinned-oid")
  for during in conform verify; do
    rig_assert_eq "${at}: the resume re-pinned the OID the ${during} attempt held" \
      "$(cat "${run}/h15-pinned.${during}")" "${resume}"
  done

  # 3. And the resume COMPLETED: the crashes cost latency, not the result.
  c3_assert_stage_passed "${at}" "${run}" harvest
  c3_assert_stage_passed "${at}" "${run}" conform
  c3_assert_stage_passed "${at}" "${run}" verify
  c3_assert_stage_passed "${at}" "${run}" advance

  # 4. STAGE 4 APPLIED EXACTLY ONCE — the atomicity claim, observed where a
  #    fourth kill cannot go. `advance_stage` is called directly rather than
  #    through a second pipeline: what is being observed is the CAS, and a full
  #    run would spend another six heavy minutes re-deriving a verify pass that
  #    is not part of the claim.
  #
  #    AGAINST A THROWAWAY COPY OF CANONICAL, and that is a correctness fix
  #    rather than fastidiousness. `advance_stage` MUTATES — precondition,
  #    transfer, CAS. Pointed at the real canonical it is only harmless while
  #    the resume actually landed; when the resume REFUSES, the precondition
  #    still holds, so the assertion itself transfers the objects and moves the
  #    ref — landing the result it was supposed to be observing, and destroying
  #    the state `assert_outcome` reads immediately afterwards. Observed doing
  #    exactly that on H15/heavy/bundle (F-P05-28), where it turned one honest
  #    refusal into seven reds and briefly looked like a canonical-safety
  #    failure. An assertion must not write to its own subject; this file's
  #    header already says rows touch the capsule clone and nothing else, and
  #    `_assert` is not exempt from it.
  base=$(c3_base "${run}")
  accepted=$(contract_field "${run}" accepted)
  probe="${run}/h15-advance-probe"
  rm -rf -- "${probe}"
  git clone --no-hardlinks --quiet -- "${run}/canonical" "${probe}"
  rig_assert_eq "${at}: a repeat advance refuses stale-base — the CAS applied once" \
    stale-base \
    "$(advance_stage "${probe}" "${run}/quarantine" "${accepted}" "${base}" "${resume}" || true)"
}

# ── T4d — the payload rows ──────────────────────────────────────────────────

# H8 — A GITLINK AND A `.gitmodules`, EACH AT A DECLARED PATH (leg 4, F-2).
#
# TWO ALTERNATIVES, ONE SCORED LEG EACH, AND THEY ARE PLANTED SEPARATELY rather
# than together as the matrix's prose reads. Leg 4 returns on the first entry
# matching either arm, so a tree carrying both refuses once and the other
# alternative's leg would score another form's refusal as its own — F-P05-22's
# short-circuit arriving from a second direction. The `instantiation` column
# describes the attack; the alternation is what splits it into observations.
#
# THE ROW EXISTS BECAUSE EVERY OTHER LEG PASSES IT (F-2). `reject_submodules`
# (`src/git.rs:2432`) scans `git ls-files --stage` and is INDEX-scoped, so it is
# unreachable from an object-only pipeline: before leg 4 this was a real hole
# rather than a defended hazard. `_assert` therefore MEASURES that, running
# leg 2's own verb over the same range and observing it ACCEPT — the kill is
# leg 4's alone, stated as an observation rather than as a claim about code that
# is not being run.
#
# Both forms sit under the fixture's design-target directory for D-P05-11's
# reason: leg 2 runs BEFORE leg 4, so a form at an undeclared path refuses
# `undeclared-path` and the cell scores a defect of the MODEL — F-P05-14,
# F-P05-18/21 and F-P05-26 are the same trap three times. For `.gitmodules`
# that means a NESTED one, which leg 4's `*/.gitmodules` arm matches
# deliberately.
#
# WHAT THIS ROW DOES NOT SHOW: that a ROOT `.gitmodules` — the only one git
# itself reads — is reachable under these fixtures' selectors. It is not, and
# that is a fact about a selector list rather than about the model. The guard is
# observed firing on the name, which is what leg 4 is written to do.

C3_H8_GITLINK=h8-gitlink
C3_H8_GITMODULES=.gitmodules

# c3_h8_path <fixture> <alt> — the declared path this alternative plants at. One
# definition, because `_mutate`, `_planted` and `_assert` must agree about it.
c3_h8_path() {
  local dir
  dir=$(c3_design_target_dir "$1")
  case "$2" in
    gitlink) printf '%s/%s' "${dir}" "${C3_H8_GITLINK}" ;;
    gitmodules) printf '%s/%s' "${dir}" "${C3_H8_GITMODULES}" ;;
    *) rig_die "H8: unknown alternative: $2" ;;
  esac
}

H8_mutate() {
  local run=$1 fixture=$2 alt=$4 repo path
  repo=$(c3_capsule_repo "${run}")
  path=$(c3_h8_path "${fixture}" "${alt}")

  case "${alt}" in
    gitlink)
      # Planted through the INDEX because a gitlink has no worktree form to
      # `git add`: `update-index --cacheinfo` is the way to author a 160000
      # entry without checking out a real submodule. It names the CONTRACTED
      # BASE, so the entry points at a commit that genuinely exists — a dangling
      # gitlink could be refused for being dangling, which is a different guard.
      git -C "${repo}" update-index --add \
        --cacheinfo "160000,$(c3_base "${run}"),${path}" ||
        rig_die "H8: could not author the gitlink at ${path}"
      git -C "${repo}" commit --quiet -m 'H8: a gitlink at a declared path'
      ;;
    gitmodules)
      c3_plant_file "${run}" "${path}"
      c3_commit "${run}" 'H8: a .gitmodules at a declared path' "${path}"
      ;;
    *) rig_die "H8: unknown alternative: ${alt}" ;;
  esac
  c3_publish "${run}"
}

H8_planted() {
  local run=$1 fixture=$2 alt=$4 path mode
  path=$(c3_h8_path "${fixture}" "${alt}")

  # In the range leg 2 folds — the clause that keeps this row off F-P05-14's
  # trap, and it is checked before the mode so a path that never landed reds
  # here rather than through an empty `ls-tree`.
  c3_planted_paths "${run}" "${path}" >/dev/null || return 1

  mode=$(git -C "$(c3_capsule_repo "${run}")" ls-tree \
    "$(c3_result "${run}")" -- "${path}" | awk '{print $1}')

  case "${alt}" in
    gitlink)
      [ "${mode}" = 160000 ] || return 1
      printf 'a %s gitlink at the DECLARED path %s, naming %s' \
        "${mode}" "${path}" "$(c3_base "${run}")"
      ;;
    gitmodules)
      # A REGULAR FILE, asserted: leg 4's two arms are mode and name, and a
      # `.gitmodules` that arrived as a gitlink would be refused by the other
      # arm — the row would then report this guard firing while the observation
      # belonged to its sibling.
      [ "${mode}" = 100644 ] || return 1
      printf 'a regular-file %s at the DECLARED path %s' "${C3_H8_GITMODULES}" "${path}"
      ;;
    *) rig_die "H8: unknown alternative: ${alt}" ;;
  esac
}

H8_assert() {
  local run=$1 at="H8/$2/$3/$4" fixture=$2 alt=$4 path slice doctrine rc=0
  path=$(c3_h8_path "${fixture}" "${alt}")

  c3_assert_stage_passed "${at}" "${run}" harvest
  c3_assert_ingested "${at}" "${run}" "${path}"

  # F-2, MEASURED. Leg 2's own verb accepts this range, so what refused is leg 4
  # and nothing else. Redirected to a file, never piped — a pipe would report
  # the reader's exit status, which this phase has met three times.
  slice=$(contract_field "${run}" slice)
  doctrine=$(rig_doctrine_bin)
  "${doctrine}" slice conformance "${slice}" -p "${run}/quarantine" \
    --against "$(c3_base "${run}")..$(cat "${run}/pinned-oid")" --strict \
    >"${run}/h8-conformance" 2>&1 || rc=$?
  rig_assert_eq "${at}: F-2 — leg 2's OWN verb ACCEPTS this range; only leg 4 kills it" \
    0 "${rc}"
}

# H11 — A HOSTILE TEST-TIME PAYLOAD THAT ACTUALLY RUNS.
#
# The one row in T4 whose subject is EXECUTION rather than admission, and so the
# only one whose payload has to survive all four legs of conform to say anything
# at all. Every row above it is refused before the verify capsule is built; H11
# asks what the sandbox profile does with code the pipeline ADMITTED.
#
# ── S3: the payload goes into the capsule RESULT, never the fixture ─────────
#
# `control/fixture-light.sh` runs `npm` TRUSTED-SIDE while assembling the
# fixture from this repo's own authored sources. A payload-bearing fixture that
# reused that loop would execute the payload on the control plane and break DQ-4
# for real — `audit-dq4.sh:77` says exactly that, conditionally, and this row is
# the condition it names. So the plant rides the same A-2 seam as every other
# row: into the capsule's clone, after the worker has published.
#
# ── the two observables, and why only one of them is scored ─────────────────
#
# The matrix asks for `sentinel-absent on the HOST path` AND `canary unreached`.
# Both were measured against the profile itself before this row was written
# (`drivers/T4d-h11-probe.log`):
#
#   filesystem escape   CONTAINED — the host path is not in the namespace at all
#   network canary      REACHED   — two clients, two arrivals, trusted-side log
#
# The second is not a defect this row discovered; it is the profile behaving as
# specified. `sandbox.sh` carries `--unshare-all` and then `--share-net`, and
# `--kind` is validated once and never reaches the mount array — EX-2's claim is
# that both capsule kinds get the SAME posture, and EX-7 wants egress for the
# worker capsule because the agent needs the API. "Canary unreached" is
# therefore an inherited expectation that no mechanism makes, and § 5.6's
# verdict on it is a re-derivation rather than a bug report (F-P05-32).
#
# So this row MEASURES the canary and refuses to score it, pending the
# operator's call. Asserting it either way would settle a design question from
# inside a test: `unreached` reds a profile that is behaving as designed, and
# `reached` quietly enshrines egress as intended. What IS scored is the half a
# mechanism does claim — containment of the filesystem escape — together with
# the non-vacuity clauses without which that claim means nothing.
#
# ── THE TWO FIXTURES REFUSE THIS ROW AT DIFFERENT BOUNDARIES (D-P05-15) ────
#
# H11's payload must be BOTH admitted by conform AND executed by the fixture's
# own `verify:` command, and no other row needs both. Where those two sets fall
# is a property of the fixture, and the two fixtures differ:
#
#   light   `npm test` is `node --test src/*.test.ts`, and `src/**` is SL-001's
#           design target. The sets INTERSECT: the payload is admitted, and the
#           test runner's own glob executes it. The claim is CONTAINMENT, at
#           `verify`, and it is the only place in the matrix the sandbox profile
#           is the thing under test.
#   heavy   `just web-build && cargo test` evaluates build systems for real —
#           `cargo` runs a root `build.rs`, which is the class-2 trigger this
#           row is named for. But the root is not under `scripts/spike-capsule/**`,
#           so conform REFUSES it at leg 2 and the sandbox is never reached.
#
# The earlier reading of this was "heavy is not instantiable" (F-P05-33), and
# the disposition it proposed was an `n/a`. That understates what was measured.
# Class-2 triggers live at repo ROOTS (`build.rs`, `package.json`); slice design
# targets are SUBDIRECTORIES. So conform's default-deny dissolves the hazard
# unless a slice declares a root build file — a property of the MODEL, holding
# on both fixtures, and a better result than the row was written expecting.
# Heavy therefore scores at `conform/undeclared-path`: the trigger is live, and
# the selector gate is what stops it.
#
# What that costs, stated rather than implied: the sandbox-containment claim is
# exercised on LIGHT ONLY. The row's altitude is earned by two different
# boundaries, which the results table cannot say — F-P05-35 says it instead.
#
# The vacuity trap is still the thing to fear here, and it moved rather than
# went away: on heavy the payload must be planted where cargo REALLY runs it, or
# the refusal is of an inert file at an undeclared path and says nothing about a
# trigger. `c3_h11_reachable` is that question asked mechanically, per fixture.

C3_H11_PAYLOAD_LIGHT=h11-payload.test.ts
# The root build script, and nothing else will do: cargo auto-detects
# `build.rs` at the package root and runs it before it compiles anything. A
# `build.rs` planted anywhere else is a file cargo never opens.
C3_H11_PAYLOAD_HEAVY=build.rs
C3_H11_RECORD=h11-executed
C3_H11_CANARY_PORT=45711
# The listener's own deadline, and it has to EXCEED the verify bound it spans
# (`fixture_verify_timeout`: 300 light, 900 heavy) or the canary would stop
# listening while the payload was still being built. It is a backstop for a run
# that dies between the plant and the assert, never the reaping path — that is
# `c3_h11_canary_stop`.
C3_H11_CANARY_TTL=1200
C3_H11_CANARY_MARK='h11 payload reached the canary'
C3_H11_CANARY_KNOCK='h11 rig knock'
C3_H11_CANARY_PID=''

# c3_h11_path <fixture> — where the payload goes, and the ONE row where this is
# not `c3_design_target_dir` plus a name. Every other row plants somewhere
# conform will admit; this one plants where the `verify:` command will RUN, and
# on heavy those are different places. Choosing the executed path over the
# admitted one is what makes heavy's refusal a measurement instead of a
# tautology.
c3_h11_path() {
  case "$1" in
    light) printf '%s/%s' "$(c3_design_target_dir "$1")" "${C3_H11_PAYLOAD_LIGHT}" ;;
    heavy) printf '%s' "${C3_H11_PAYLOAD_HEAVY}" ;;
    *) rig_die "no H11 payload path for fixture: $1" ;;
  esac
}

# c3_h11_reachable <fixture> <path> — DOES THIS FIXTURE'S `verify:` COMMAND
# EXECUTE THIS PATH? F-P05-33's question, asked mechanically so the next
# execution row cannot forget to ask it.
#
# Light's glob is a TRANSCRIPTION of its `package.json` `test` script, measured
# 2026-08-02: `node --test src/*.test.ts`. The declaration only says `npm test`,
# so the glob cannot be derived from it and has to be stated here — with the
# script it mirrors named, so a fixture that changed its runner is one grep away.
#
# ANSWERS rather than dies, including on an unknown fixture: `_planted` calls it
# from inside a `$( … )`, where a `rig_die` would end only the substitution's
# subshell and the caller would carry on with an empty observable (F-P01-1).
# `_mutate` is where an unusable fixture is fatal.
c3_h11_reachable() {
  case "$1" in
    light) case "$2" in src/*.test.ts) return 0 ;; esac ;;
    # Heavy's is not a glob but a fixed filename at a fixed place, because
    # that is how cargo finds a build script: package root, `build.rs`, run
    # before the crate compiles. Reachable and UNDECLARED are both true here,
    # and the row exists to show they can be.
    heavy) case "$2" in build.rs) return 0 ;; esac ;;
  esac
  return 1
}

# The host path the payload tries to write, and the containment observable. It
# points INSIDE the rig's own disposable run directory on purpose: if the
# profile ever failed open, the escape lands somewhere `pipeline_teardown` will
# remove rather than somewhere real.
c3_h11_escape_target() { printf '%s/h11-escaped' "$1"; }

c3_h11_canary_log() { printf '%s/h11-canary.log' "$1"; }

# c3_h11_canary_start <run> — arm the trusted-side canary.
#
# A listener OUTSIDE the sandbox, because egress has to be observed where it
# ARRIVES. The capsule's own note that it connected is a capsule-authored file,
# and I4's rule about verdicts applies one level down to observations too.
#
# ── SOCAT, AND NOT NODE, AND THE AUDIT IS WHY (DQ-4) ────────────────────────
#
# The first version of this listener was six lines of `node`, and `audit-dq4`
# refused it on sight: `node` is one of the LIGHT declaration's `exec:` tokens,
# and DQ-4's condition is that the control plane never runs the project's
# toolchain. It is a structural guard, deliberately not a judgement call — the
# listener reads no project content, and that is exactly the argument an
# exemption would be built on. F-P05-3 predicted this audit would be the thing
# that caught a payload-bearing row reaching for the project's tools; it was,
# on the first run, against the row it was predicted for.
#
# `socat` is in neither fixture's `exec:` list and does the job more directly:
# it appends the BYTES IT RECEIVES, never the fact of a connection.
c3_h11_canary_start() {
  local run=$1 log tries=0
  log=$(c3_h11_canary_log "${run}")
  command -v socat >/dev/null ||
    rig_die 'H11: socat is missing — the canary has no listener, and node is DQ-4-forbidden here'

  : >"${log}"
  # `timeout` forwards the signal it receives to the command it manages, so
  # killing this pid still reaps the socat underneath it.
  timeout "${C3_H11_CANARY_TTL}" \
    socat -u "TCP-LISTEN:${C3_H11_CANARY_PORT},reuseaddr,fork" \
    "OPEN:${log},creat,append" >/dev/null 2>&1 &
  C3_H11_CANARY_PID=$!

  # READINESS AND OWNERSHIP IN ONE OBSERVATION. Knock, then wait for the knock
  # to appear IN THIS LOG. A port that merely answers is not enough: a leaked
  # listener from an earlier run would answer too, while logging somewhere else,
  # and this cell would then read its own silence as containment. Because the
  # log is keyed on BYTES, an unanswered knock leaves nothing behind.
  until command grep -qF -- "${C3_H11_CANARY_KNOCK}" "${log}"; do
    (printf '%s\n' "${C3_H11_CANARY_KNOCK}" >"/dev/tcp/127.0.0.1/${C3_H11_CANARY_PORT}") 2>/dev/null || true
    tries=$((tries + 1))
    [ "${tries}" -lt 100 ] ||
      rig_die "H11: nothing of ours is listening on :${C3_H11_CANARY_PORT} — held by an earlier run?"
    sleep 0.1
  done

  # Truncated AFTER the knock lands, so `planted?`'s quiet clause means "quiet
  # since this cell armed it" rather than "never used by anyone".
  : >"${log}"
}

# c3_h11_canary_stop — reap it. Called from `_assert`, which runs in the same
# shell as `_mutate`, so `wait` really can reap the child.
#
# The pid is a SHELL GLOBAL rather than a file in the run directory, and that is
# not a style preference: `pipeline_teardown` removes the run directory, so a
# pid file is a record that dies before the process it names. A caller that
# never reaches `_assert` — the falsifiability round's `_planted` cases, which
# stop at the plant — could then not reap the listener at all, and the next case
# would meet its own predecessor holding the port. The TTL inside the listener
# is the backstop for the case where the shell itself goes.
c3_h11_canary_stop() {
  [ -n "${C3_H11_CANARY_PID}" ] || return 0
  kill "${C3_H11_CANARY_PID}" 2>/dev/null || true
  wait "${C3_H11_CANARY_PID}" 2>/dev/null || true
  C3_H11_CANARY_PID=''
}

# c3_h11_write_payload <file> <escape-target>
#
# Plain JS in a `.ts` file — node strips types and the fixture's own tests are
# written the same way, so the payload is indistinguishable from project code
# until it runs.
#
# IT NEVER THROWS. The row's claim is containment, not the suite's verdict, and
# a payload that reds `npm test` would move the observed refusal to
# `verify/suite-failed` — scoring a different row, at the same boundary, for a
# reason that has nothing to do with the hazard.
c3_h11_write_payload() {
  cat >"$1" <<PAYLOAD
import { test } from 'node:test'
import fs from 'node:fs'
import net from 'node:net'

// ${C3_PAYLOAD_MARK}: planted by the P-C3 rig (SL-241 PHASE-05, H11).
const RECORD = '${C3_H11_RECORD}'
const ESCAPE = '$2'
const CANARY_PORT = ${C3_H11_CANARY_PORT}

const note = (line) => fs.appendFileSync(RECORD, line + '\n')

test('h11 hostile payload', async () => {
  note('cwd=' + process.cwd())

  // 1 — the filesystem escape, at a HOST path outside every mount the profile
  // grants. The sentinel's absence trusted-side is the verdict; this line is
  // what stops that absence being an absence of anything having been tried.
  try {
    fs.writeFileSync(ESCAPE, 'h11 escaped\n')
    note('escape=WROTE')
  } catch (e) {
    note('escape=denied:' + (e && e.code))
  }

  // 2 — the network canary. What lands in the canary's own log is the
  // observation; this records only that the attempt was made.
  await new Promise((resolve) => {
    const sock = net.connect(CANARY_PORT, '127.0.0.1')
    const done = (what) => { note('canary=' + what); sock.destroy(); resolve() }
    sock.setTimeout(5000, () => done('timeout'))
    sock.on('error', (e) => done('refused:' + (e && e.code)))
    sock.on('connect', () => sock.write('${C3_H11_CANARY_MARK}\n', () => done('connected')))
  })
})
PAYLOAD
}

# c3_h11_write_payload_rs <file> <escape-target>
#
# Heavy's half, and it is a REAL build script rather than a stand-in. Nothing
# runs it — conform refuses the path two stages upstream — so the temptation is
# to plant a marker file and call it a build.rs. That would make the refusal a
# refusal of a text file that happens to be named `build.rs`, and the row's
# claim is about a LIVE trigger being stopped by the selector gate rather than
# by luck. What is planted is what cargo would compile and run.
#
# It mirrors the light payload act for act — escape, then canary — so the two
# fixtures differ in ecosystem and in nothing else. `main()` is the whole build
# script: cargo builds this file and executes the binary before it touches the
# crate, which is precisely why class 2 is worth a row of its own.
c3_h11_write_payload_rs() {
  cat >"$1" <<PAYLOAD
// ${C3_PAYLOAD_MARK}: planted by the P-C3 rig (SL-241 PHASE-05, H11).
use std::fs;
use std::io::Write;
use std::net::TcpStream;

fn main() {
    let mut note = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("${C3_H11_RECORD}")
        .expect("h11: the execution record is the row's non-vacuity clause");
    let _ = writeln!(note, "cwd={}", std::env::current_dir().unwrap_or_default().display());

    // 1 — the filesystem escape, at a HOST path outside every mount the
    // profile grants.
    match fs::write("$2", "h11 escaped\n") {
        Ok(()) => { let _ = writeln!(note, "escape=WROTE"); }
        Err(e) => { let _ = writeln!(note, "escape=denied:{:?}", e.kind()); }
    }

    // 2 — the network canary. The attempt is recorded here; the ARRIVAL is
    // recorded trusted-side, because a capsule's account of its own egress is
    // capsule-authored and I4's rule about verdicts applies to observations.
    match TcpStream::connect(("127.0.0.1", ${C3_H11_CANARY_PORT})) {
        Ok(mut s) => {
            let _ = s.write_all(b"${C3_H11_CANARY_MARK}\n");
            let _ = writeln!(note, "canary=connected");
        }
        Err(e) => { let _ = writeln!(note, "canary=refused:{:?}", e.kind()); }
    }

    // NEVER FAIL THE BUILD. A build script exiting nonzero moves the observed
    // refusal to \`verify/suite-failed\` — a different row, at the same
    // boundary, for a reason that has nothing to do with the hazard.
    println!("cargo:rerun-if-changed=build.rs");
}
PAYLOAD
}

H11_mutate() {
  local run=$1 fixture=$2 repo path
  repo=$(c3_capsule_repo "${run}")
  path=$(c3_h11_path "${fixture}")

  # Still fatal, and for the reason it always was: a payload the `verify:`
  # command never runs is a plant that cannot fire, and its absent sentinel
  # reads exactly like containment. What changed is that heavy now HAS such a
  # path — it is simply one conform will not admit (D-P05-15).
  c3_h11_reachable "${fixture}" "${path}" ||
    rig_die "H11: ${fixture}'s verify command never executes ${path} — an inert plant would score as containment"

  mkdir -p -- "$(dirname -- "${repo}/${path}")"
  case "${fixture}" in
    light)
      # The canary is armed for the fixture that REACHES the sandbox and
      # nowhere else. On heavy the pipeline refuses two stages upstream, so a
      # listener would only ever record silence, and silence from a payload that
      # never ran is the measurement this row refuses to take.
      c3_h11_canary_start "${run}"
      c3_h11_write_payload "${repo}/${path}" "$(c3_h11_escape_target "${run}")"
      ;;
    heavy) c3_h11_write_payload_rs "${repo}/${path}" "$(c3_h11_escape_target "${run}")" ;;
  esac
  c3_commit "${run}" "H11: a hostile ${path} the verify command runs" "${path}"
  c3_publish "${run}"
}

H11_planted() {
  local run=$1 fixture=$2 path repo
  path=$(c3_h11_path "${fixture}")

  # ── heavy: the trigger is LIVE, and that is the whole positive control ─────
  #
  # There is no canary and no sandbox here, so what has to be shown is that the
  # thing conform refuses is a build script cargo would really have run. Read
  # off the TREE (a `Cargo.toml` beside it at the package root) rather than off
  # `c3_h11_reachable`'s case statement, which is the rig agreeing with itself.
  if [ "${fixture}" = heavy ]; then
    repo=$(c3_capsule_repo "${run}")
    c3_h11_reachable "${fixture}" "${path}" || return 1
    c3_planted_paths "${run}" "${path}" >/dev/null || return 1
    [ -f "${repo}/Cargo.toml" ] || return 1
    [ "$(dirname -- "${path}")" = '.' ] || return 1
    printf 'a hostile %s at the cargo package root, which "%s" runs; undeclared by the fixture slice' \
      "${path}" "$(contract_field "${run}" verify)"
    return 0
  fi

  # Reachability FIRST, because it is this row's version of "the payload
  # landed": a file the `verify:` command never runs is a plant that cannot
  # fire, and its absent sentinel reads exactly like containment (F-P05-33).
  c3_h11_reachable "${fixture}" "${path}" || return 1
  c3_planted_paths "${run}" "${path}" >/dev/null || return 1

  # Armed AND quiet. Without the second half, a mark found afterwards could have
  # been left at this port by an earlier run rather than by this payload; the
  # arming half is a live listener rather than a file, because a file saying
  # "listening" outlives the process that wrote it.
  #
  # The emptiness test is NOT redundant with the signal below, and M18 is what
  # says so: `kill -0 0` addresses the CALLER'S OWN PROCESS GROUP and succeeds,
  # so a never-armed canary read as armed and the clause passed vacuously. A
  # `${x:-0}` default that lands on a meaningful pid is a default that answers a
  # different question.
  [ -n "${C3_H11_CANARY_PID}" ] || return 1
  kill -0 "${C3_H11_CANARY_PID}" 2>/dev/null || return 1
  [ ! -s "$(c3_h11_canary_log "${run}")" ] || return 1

  printf 'an executable payload at %s, which "%s" runs; canary armed and quiet on :%s' \
    "${path}" "$(contract_field "${run}" verify)" "${C3_H11_CANARY_PORT}"
}

H11_assert() {
  local run=$1 fixture=$2 at="H11/$2/$3/$4" path record arrivals
  path=$(c3_h11_path "${fixture}")

  # ── heavy: refused at conform, and the row says what that does NOT prove ───
  if [ "${fixture}" = heavy ]; then
    c3_assert_stage_passed "${at}" "${run}" harvest
    c3_assert_ingested "${at}" "${run}" "${path}"
    # THE CLAUSE THAT KEEPS THIS HONEST. Everything a containment row asserts is
    # shaped like an absence, and every one of those absences holds here for a
    # reason that has nothing to do with the sandbox: it was never built. Saying
    # so mechanically means a later change that DID admit this path — a fixture
    # slice declaring `build.rs`, say — reds this cell instead of quietly
    # rescoring it as containment evidence.
    rig_assert "${at}: the verify capsule was NEVER BUILT — this cell claims no containment" \
      c3_no_execution_in "${run}/stages" 'stage=verify'
    return 0
  fi

  # The capsule's writable root is bound at /capsule and provisioned to
  # /capsule/repo, so what the payload wrote relative to its cwd is readable
  # here without the rig ever entering the sandbox.
  record="${run}/verify-capsule/repo/${C3_H11_RECORD}"
  c3_h11_canary_stop

  c3_assert_stage_passed "${at}" "${run}" harvest
  c3_assert_ingested "${at}" "${run}" "${path}"
  # Conform is a CLAUSE of this row, not scaffolding: the payload has to be
  # admitted at a declared path for stage 3 to see it at all, and that is the
  # half of F-P05-33 heavy cannot satisfy.
  c3_assert_stage_passed "${at}" "${run}" conform

  # NON-VACUITY, FIRST. Everything below is about what did NOT happen, and each
  # of those clauses holds against a payload that never executed — the failure
  # this row exists to avoid.
  rig_assert "${at}: the payload EXECUTED — the verify capsule ran it" \
    test -s "${record}"
  rig_assert_eq "${at}: and it ran inside the capsule's own clone" \
    /capsule/repo "$(rig_field "${record}" cwd)"
  c3_assert_stage_passed "${at}" "${run}" verify

  # THE CLAIM A MECHANISM MAKES: the filesystem escape is contained.
  rig_assert "${at}: the escape sentinel is ABSENT on the host path" \
    c3_path_absent "$(c3_h11_escape_target "${run}")"
  rig_assert_eq "${at}: … and the payload TRIED — denied by the profile, not skipped" \
    denied "$(rig_field "${record}" escape | cut -d: -f1)"

  # THE CLAUSE HELD OPEN (F-P05-32). Measured, named, and deliberately not
  # scored: `--share-net` is in the profile by EX-2's construction, so neither
  # verdict is this row's to reach. The pairing below is what keeps the
  # measurement honest — an arrival count means nothing unless an attempt was
  # made, and the attempt means nothing unless the canary was listening.
  rig_assert "${at}: the canary attempt was MADE — the measurement is of something" \
    test -n "$(rig_field "${record}" canary)"
  arrivals=$(command grep -cF -- "${C3_H11_CANARY_MARK}" "$(c3_h11_canary_log "${run}")" 2>/dev/null || true)
  rig_warn "${at}: F-P05-32 NOT SCORED — payload attempt '$(rig_field "${record}" canary)', arrivals at the canary: ${arrivals}"
}

# ── T4e — the staleness rows: H10 and H16 ───────────────────────────────────
#
# THE ONLY TWO ROWS THAT WRITE CANONICAL — see "what these files may and may
# not touch" at the head of this file for why that is a scoping of the rule
# rather than a breach of it.
#
# Neither row plants a payload. Their hazard is the accepted ref having MOVED
# since the contract pinned B, which stage 4 meets at its PRECONDITION and
# refuses `advance/stale-base` having transferred nothing — so both keep the
# STRICT `assert_outcome` clause (F-14, design § 5.5 I1). `advance_stage`'s own
# comment (`pipeline.sh:560-566`) names these two rows as the reason its
# internal ordering reads the precondition before the transfer.
#
# `selftest.sh:251-272` is the reference scenario and these rows ride its
# shape: provision the capsule, move the accepted ref, RE-SNAPSHOT, run. The
# mutate seam sits exactly where that scenario's move sits — between
# `pipeline_capsule` and `pipeline_run` — so neither row needs a harness change
# (D-P05-5).
#
# ── the two rows score IDENTICALLY, and that is the RESULT ──────────────────
#
# Both refuse `advance/stale-base`. Their whole difference is WHO moved the
# ref: H10's mover is a peer capsule result contracted from the SAME base B,
# conflicting with this one on the same path; H16's is an ordinary trunk
# advance touching a path this result never names, which a three-way merge
# would take without a murmur. Stage 4 compares two OIDs and never reads a
# tree, so it cannot tell them apart — the genuinely conflicting pair and the
# trivially mergeable one get the same token and the same refusal.
#
# That indistinguishability IS § 5.1's split made observable: the capsule model
# HAS the safety claim and does NOT have the resolution one, and F-9/QUE-202
# own the gap. Neither row can be SCORED for it, the token being the same on
# both, so each carries it in `_planted` and `_assert` — which is precisely
# what those exist for (what the refusal token cannot say).

# What a canonical-side mover writes, so a reader of a refused run can tell the
# trunk's content from the capsule's at a glance — `C3_PAYLOAD_MARK`'s opposite
# number, and named for the same reason (STD-001).
C3_STALE_MARK='p-c3 canonical mover'

# H16's mover path. It must be DISJOINT from everything the capsule's result
# names, and it is spelled here rather than at its use site so the disjointness
# is checkable against one string. Deliberately not `C3_UNDECLARED_PATH`: that
# one is H4's subject inside the capsule, and a reader meeting it on canonical
# would reasonably expect a conform interaction that this row does not have.
#
# H10 needs no constant. Its conflicting pair meets on the FIXTURE'S OWN STUB
# PATH, the one path both halves are guaranteed to touch — the worker stub
# appends to it (`capsule/worker-stub.sh:52`) and the contract records it
# because it is a join with the slice's selectors (`pipeline.sh:203-207`). So
# the capsule's half of the pair needs no plant at all; the row supplies only
# the peer, and reads the path from the contract rather than re-deriving it.
C3_H16_TRUNK_PATH='docs/h16-trunk-moved.md'

# c3_path_blob <repo> <rev> <path> — the blob OID at <path> in <rev>, or EMPTY
# if the path is not there.
#
# Empty is a legitimate answer rather than an error: a fixture's stub path need
# not exist at B, and a caller comparing two of these wants "absent" to compare
# equal to "absent" instead of dying inside a command substitution.
c3_path_blob() {
  git -C "$1" rev-parse --verify --quiet "$2:$3" 2>/dev/null || true
}

# c3_accepted_oid <run> — what canonical's accepted ref holds RIGHT NOW.
#
# Read through the contract's `accepted` field rather than through HEAD: the
# two agree by construction, but the contract is what stage 4 itself keys off
# (`pipeline.sh:309`), and a row asking a different question than the stage it
# is measuring would eventually answer one.
c3_accepted_oid() {
  git -C "$1/canonical" rev-parse --verify "$(contract_field "$1" accepted)"
}

# c3_move_accepted <run> <message> <path> — advance canonical's accepted ref by
# one commit touching <path>, then RE-SNAPSHOT.
#
# Committed on canonical's WORKTREE, which is the accepted ref by construction:
# `pipeline_setup` reads `accepted` off `symbolic-ref HEAD` (`pipeline.sh:180`).
# A row spelling a branch name here would pass on heavy and break on light,
# whose trunk is `mainline` precisely so that anything assuming `main` breaks
# loudly (D5).
#
# THE RE-SNAPSHOT IS LOAD-BEARING, not tidiness. `assert_outcome` compares
# canonical against `canonical-refs.before` / `canonical-objects.before`, and
# this move is SCENARIO STATE rather than a pipeline effect — without
# re-snapshotting, the cell reds on its own setup and looks exactly like the
# assertion working (`pipeline.sh:248-256`).
#
# The identity is passed EXPLICITLY. Canonical is a clone, and `git clone` does
# not copy the source's local config, so the fixture's own `user.email`
# (`fixture-light.sh:88`) does not travel. Git's implicit `user@host` fallback
# happens to resolve in this jail — which means a row leaning on it would fail
# somewhere else rather than here, and the failure would arrive as a mutate
# that silently planted nothing.
c3_move_accepted() {
  local run=$1 message=$2 path=$3
  local canonical="${run}/canonical"

  mkdir -p -- "$(dirname -- "${canonical}/${path}")"
  printf '%s: %s\n' "${C3_STALE_MARK}" "${message}" >>"${canonical}/${path}"
  git -C "${canonical}" add -- "${path}" ||
    rig_die "c3_move_accepted: could not stage ${path} in ${canonical}"
  git -C "${canonical}" \
    -c user.name='p-c3 canonical mover' \
    -c user.email='mover@spike-capsule.invalid' \
    commit --quiet -m "${message}"

  pipeline_snapshot "${run}"
}

# c3_stale_planted <run> <at> — the half of the positive control both staleness
# rows share: the accepted ref moved, and it moved to a CHILD OF B.
#
# The parentage clause is not bookkeeping. § 5.6 names H10 as a pair "from one
# base" and H16 as the trunk advancing "before admission"; a mover whose parent
# were something else would still produce `stale-base`, so the cell would score
# green while instantiating neither row. PRINTS the mover's OID.
c3_stale_planted() {
  local run=$1 base moved parent
  base=$(c3_base "${run}")
  moved=$(c3_accepted_oid "${run}")
  [ "${moved}" != "${base}" ] || return 1
  parent=$(git -C "${run}/canonical" rev-parse --verify "${moved}^" 2>/dev/null || true)
  [ "${parent}" = "${base}" ] || return 1
  printf '%s' "${moved}"
}

# c3_stale_assert_reached_four <at> <run> — all three upstream stages passed by
# NAME, which is this pair's non-vacuity clause.
#
# A staleness row's every remaining observable is an absence — canonical
# unchanged, nothing merged — and every one of those holds just as well against
# a run that refused at stage 1 and never approached the precondition. Naming
# the three is the same move `selftest_happy` makes (`selftest.sh:177-184`):
# asserting only the final status would score a run that skipped a stage
# entirely as green.
c3_stale_assert_reached_four() {
  local at=$1 run=$2 stage
  for stage in harvest conform verify; do
    c3_assert_stage_passed "${at}" "${run}" "${stage}"
  done
}

# H10 — a CONFLICTING PAIR from one base. A peer capsule contracted from the
# same B has already landed, and it touched the same path this result touches.
#
# THE PEER LANDING IS SIMULATED, and the simulation is exact where this row
# reads it. A real peer lands by stage 4's own CAS advancing the accepted ref
# from B to its result; committing on canonical's accepted ref reaches the
# identical end state — the ref at a child of B carrying that peer's content —
# and that end state is the entire input to the precondition this row
# exercises. Running a second full pipeline inside the mutate seam would put an
# UNSCORED pipeline run inside a scored cell, double the heavy fixture's cost
# at ~6 min a stage-3 run, and prove the happy path, which `selftest_happy`
# already owns.
H10_mutate() {
  local run=$1
  c3_move_accepted "${run}" \
    'H10: a peer result from the same base B, landed on the accepted ref' \
    "$(contract_field "${run}" stub)"
}

H10_planted() {
  local run=$1 base stub peer moved_paths
  base=$(c3_base "${run}")
  stub=$(contract_field "${run}" stub)

  peer=$(c3_stale_planted "${run}") || return 1

  # The peer touches the stub …
  moved_paths=$(c3_range "${run}/canonical" "${base}" "${peer}")
  printf '%s\n' "${moved_paths}" | command grep -qxF -- "${stub}" || return 1
  # … and so does this capsule's PUBLISHED result, which is what makes the two
  # a conflicting pair rather than two commits that happen to share a base.
  # Read off the published result, never the worktree (`c3_planted_paths`).
  c3_planted_paths "${run}" "${stub}" >/dev/null || return 1

  printf 'peer %s landed on the accepted ref from the same base %s, conflicting with this result on %s' \
    "$(git -C "${run}/canonical" rev-parse --short "${peer}")" \
    "$(git -C "${run}/canonical" rev-parse --short "${base}")" "${stub}"
}

H10_assert() {
  local run=$1 at="H10/$2/$3/$4" stub base peer
  stub=$(contract_field "${run}" stub)
  base=$(c3_base "${run}")
  peer=$(c3_accepted_oid "${run}")

  c3_stale_assert_reached_four "${at}" "${run}"

  # The trusted side HAD the conflict in front of it when it refused. The token
  # cannot say this: `stale-base` comes out of a comparison of two OIDs that
  # never reads a tree, so a transport which dropped the result entirely would
  # refuse identically.
  c3_assert_ingested "${at}" "${run}" "${stub}"

  # ── THE RESOLUTION GAP, made observable (§ 5.1, F-9/QUE-202) ─────────────
  #
  # `assert_outcome` says canonical did not CHANGE. It does not say whose
  # content survived, and "nothing was auto-resolved" is a claim about exactly
  # that. Three clauses, none of which the token or the outcome assertion
  # reaches: no merge was constructed, the peer's change is what stands, and
  # this capsule's version of the contested path did not land.
  rig_assert_eq "${at}: no merge was constructed — the accepted ref is still a child of B" \
    "${base}" "$(git -C "${run}/canonical" rev-parse --verify "${peer}^" 2>/dev/null || true)"
  rig_assert "${at}: the PEER's change to ${stub} is what stands" \
    test "$(c3_path_blob "${run}/canonical" "${peer}" "${stub}")" \
    != "$(c3_path_blob "${run}/canonical" "${base}" "${stub}")"
  rig_assert "${at}: … and THIS capsule's ${stub} did not land, merged or otherwise" \
    test "$(c3_path_blob "${run}/canonical" "${peer}" "${stub}")" \
    != "$(c3_path_blob "$(c3_capsule_repo "${run}")" "$(c3_result "${run}")" "${stub}")"
}

# H16 — the trunk moved before admission. The mover is nobody's capsule and it
# touches a path this result never names, so the pair is trivially mergeable.
H16_mutate() {
  local run=$1
  c3_move_accepted "${run}" \
    'H16: the trunk advanced after the contract pinned B' \
    "${C3_H16_TRUNK_PATH}"
}

H16_planted() {
  local run=$1 base stub moved moved_paths result_paths
  base=$(c3_base "${run}")
  stub=$(contract_field "${run}" stub)

  moved=$(c3_stale_planted "${run}") || return 1

  # The mover's range is EXACTLY its own one path …
  moved_paths=$(c3_range "${run}/canonical" "${base}" "${moved}")
  [ "${moved_paths}" = "${C3_H16_TRUNK_PATH}" ] || return 1

  # … and this result really changed something (a result that changed nothing
  # would be disjoint from the mover vacuously) …
  c3_planted_paths "${run}" "${stub}" >/dev/null || return 1

  # … and the two are DISJOINT. This is the row's whole distinction from H10
  # and it has to be MEASURED: a mover that collided with the stub would be H10
  # wearing H16's name, and it would score identically — which is exactly why
  # neither row can lean on the token to tell them apart.
  result_paths=$(c3_range "$(c3_capsule_repo "${run}")" "${base}" "$(c3_result "${run}")")
  if printf '%s\n' "${result_paths}" | command grep -qxF -- "${C3_H16_TRUNK_PATH}"; then
    return 1
  fi

  printf 'the trunk advanced to %s on %s, disjoint from this result (%s) — a three-way merge would take the pair' \
    "$(git -C "${run}/canonical" rev-parse --short "${moved}")" \
    "${C3_H16_TRUNK_PATH}" "${stub}"
}

H16_assert() {
  local run=$1 at="H16/$2/$3/$4" stub base moved
  stub=$(contract_field "${run}" stub)
  base=$(c3_base "${run}")
  moved=$(c3_accepted_oid "${run}")

  c3_stale_assert_reached_four "${at}" "${run}"

  # ── THE ASYMMETRY THE TOKEN HIDES ────────────────────────────────────────
  #
  # This pair is trivially mergeable and it refuses with the SAME
  # `advance/stale-base` H10 earns for a genuine conflict. Two clauses say so
  # mechanically. The DISJOINTNESS SURVIVED TRANSPORT: what the trusted side
  # actually folded carries this result's stub and not the trunk's path, so the
  # merge that stage 4 declined would have been a trivial one, and the fact is
  # measured on the quarantine rather than assumed from the rig's own setup.
  # And this result's contested-by-nobody stub never landed on canonical anyway.
  #
  # Stage 4 therefore pays nothing in precision for its safety and is given
  # nothing either: the recovery that WOULD tell these two cases apart belongs
  # to the candidate layer, which the T5 sub-probe measures and which counts
  # toward nothing (F-9, QUE-202).
  c3_assert_range "${at}" "${run}" "${C3_H16_TRUNK_PATH}" "${stub}"
  rig_assert_eq "${at}: canonical's ${stub} is untouched — this result never landed" \
    "$(c3_path_blob "${run}/canonical" "${base}" "${stub}")" \
    "$(c3_path_blob "${run}/canonical" "${moved}" "${stub}")"
}
