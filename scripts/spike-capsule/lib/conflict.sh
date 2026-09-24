#!/usr/bin/env bash
# lib/conflict.sh — THE H10/H16 CONFLICT SUB-PROBE (PHASE-05 T5; EX-6, EX-15,
# VA-4). SOURCED, never executed.
#
# ── what this measures, and what it is NOT ──────────────────────────────────
#
# Design § 5.1 (D8) splits H10 and H16 into two separable claims, and only one
# of them needs the candidate layer:
#
#   SAFETY      the accepted ref has moved since the contracted base B, so
#               stage 4's CAS refuses `advance/stale-base`. That leg runs on the
#               four-stage pipeline (`lib/instantiations.sh`) and IS
#               capsule-model evidence.
#   RESOLUTION  `candidate create`'s 3-way, its `Conflicted` classification and
#               the incumbent's supersede guidance are the RECOVERY path after
#               that refusal. F5 shows those verbs are welded to coordination
#               staging, which the capsule model does not have. THIS FILE is
#               that leg.
#
# So every entry recorded here is an INCUMBENT-LAYER REGRESSION CHECK and
# **counts toward nothing** (F-9). It is not capsule-model evidence and must
# never enter a coverage number. The claim is enforced in the results file
# rather than left to prose: the `altitude` column — the one column a reader
# sums to make a coverage claim — reads `counts-toward-nothing` on these rows,
# and `expected-stage`/`expected-token` carry values DELIBERATELY OUTSIDE
# `MATRIX_STAGES` and `token_legal`. A tally that tried to fold these entries
# into the pipeline's vocabulary finds values in neither closed set and fails
# loudly, instead of silently counting an incumbent refusal as model coverage.
#
# H16's token is `stale-trunk`, and the near-miss with the pipeline's
# `stale-base` is deliberate: it is the SAME phenomenon observed on the other
# layer, and a reader who notices the echo has understood the row. It is spelt
# differently because it is not the same token — `token_legal` would refuse it,
# which is the point.
#
# ── the two rows PARTITION the sequence ─────────────────────────────────────
#
# § 5.1 names the leg as `dispatch setup` → `prepare-review` → `candidate
# create` → `admit` → integrate, "staging and all". Neither row drives all of
# it, because each refuses at its own point in it — and between them the whole
# sequence is exercised:
#
#   H10  a genuinely conflicting pair from one base. Refuses AT `candidate
#        create`: the 3-way cannot be taken, the row is recorded `conflicted`,
#        and the guidance is hand-resolution (`candidate ingest`).
#   H16  the trunk advances on a disjoint path AFTER the candidates pinned B and
#        BEFORE admission. `create` and `admit` BOTH SUCCEED — admission never
#        looks at trunk — and the refusal lands at the integrate CAS, whose
#        guidance is to SUPERSEDE the close-target on the new base.
#
# That asymmetry is itself the regression check's result: on this layer,
# staleness is caught by the fast-forward CAS at integration and by nothing
# earlier. It is the incumbent's analogue of the ordering `pipeline.sh:560-566`
# holds for stage 4, and it is why the H16 leg drives admission at all rather
# than stopping at `create`.
#
# ── F3, and why it is COPIED rather than cloned ─────────────────────────────
#
# `prepare-review`'s phase-completion gate is what F3 exists for (EX-15): its
# SL-001 carries a plan with PHASE-01 driven to `completed`. That completion
# lives in `.doctrine/state/slice/001/phases/phase-01.toml`, which is RUNTIME
# STATE and gitignored — so `phases: 1/1` is a property of the fixture
# DIRECTORY, not of its repository (fixtures.md F3). A sub-probe that cloned
# would arrive with no completed phase, and the gate's refusal would read as a
# finding about the candidate layer when it is a fact about the provisioning.
# Hence `cp -a`, and hence the assertion that the gate was actually cleared.

# F3, and the two joins it inherits from F1. `light-plan` IS the light fixture
# plus a plan, so its slice and its stub path ARE light's: read through the same
# accessors rather than re-spelled, or a fixture rebuild that moved either would
# leave this file pointing at the old one.
CONFLICT_VARIANT=light-plan
CONFLICT_JOINS_FIXTURE=light

# The phase F3's plan carries, and the one `record-boundary` cuts against.
CONFLICT_PHASE=PHASE-01

# THE F-9 MARKER, in the column that carries the coverage claim. `cell_altitude`
# never runs for these entries — `c3_stamp_altitude` is a row-loop concern — so
# this is passed to the recorder directly and is the only altitude value in the
# results file that is not computed from legs.
CONFLICT_ALTITUDE=counts-toward-nothing

# Where the coordination worktree goes. Under the project root by REFUSAL, not
# by taste: `dispatch setup` rejects a coord dir outside the root under the
# claude arm (the arm forks the Agent worktree off the Bash cwd's HEAD, and a
# `cd` out of a confining jail silently reverts). The refusal names this
# convention; taking it keeps the sub-probe cwd-independent, since every verb is
# then reachable with `-p <repo>` from anywhere.
CONFLICT_COORD_REL=.dispatch

# The two identities that commit here. Distinct so a reader of a refused run can
# tell the capsule's half of a pair from canonical's at a glance — the same
# reason `C3_STALE_MARK` exists, and the trunk-side mover reuses that constant
# rather than minting a second name for the same actor.
CONFLICT_RESULT_WHO='p-c3 capsule result'
CONFLICT_MAIL=subprobe@spike-capsule.invalid

# What the capsule's half of H10's pair writes. Named because it has TWO
# readers: `conflict_stage_result` writes it, and M33 has canonical write the
# same bytes to dissolve the conflict. A mutant carrying its own copy of this
# literal would stop agreeing the moment either side was edited, and it would
# fail by scoring GREEN — the conflict would simply persist and the mutant would
# have proved nothing (STD-001).
CONFLICT_RESULT_BODY='// the capsule side of the pair'

# ── provisioning ────────────────────────────────────────────────────────────

# conflict_provision <label>
#
# PUBLISHES `CONFLICT_RUN` / `CONFLICT_REPO` / `CONFLICT_COORD` /
# `CONFLICT_TRUNK` / `CONFLICT_BASE` rather than printing them, for
# `pipeline_setup`'s reason (F-P01-1): this calls `guard_not_real_repo`, which
# refuses by `exit`, and a caller forced to wrap it in `$( … )` to read the run
# dir would end only the substitution's subshell — provisioning would carry on
# against a root the guard had just refused.
conflict_provision() {
  local label=$1
  local run="${RIG_ROOT}/runs/${label}"

  guard_not_real_repo "${run}"
  rm -rf -- "${run}"
  mkdir -p -- "${run}"

  # COPIED, NEVER CLONED — see the header. `-a` carries the gitignored runtime
  # state that EX-15's whole fixture exists to supply.
  cp -a -- "$(fixture_repo "${CONFLICT_VARIANT}")" "${run}/repo"

  CONFLICT_RUN="${run}"
  CONFLICT_REPO="${run}/repo"

  # RESOLVED HERE, NOT AT SOURCE TIME, and both for the D-P05-19 reason: this
  # file is sourced beside the other libraries, and `fixture_stub` /
  # `fixture_slice` / `rig_doctrine_bin`'s ladder are defined further down
  # `probe-c3.sh` than the source block. A source-time read would take the
  # value the shell had before the accessors existed.
  CONFLICT_SLICE=$(fixture_slice "${CONFLICT_JOINS_FIXTURE}")
  CONFLICT_DOCTRINE=$(rig_doctrine_bin)
  CONFLICT_COORD="${run}/repo/${CONFLICT_COORD_REL}/SL-${CONFLICT_SLICE}"

  # The trunk ref is READ FROM THE FIXTURE, never hardcoded (EX-8). The light
  # fixture's trunk is `mainline` precisely so that anything assuming `main`
  # breaks loudly (D5), and the incumbent needs it named explicitly: with no
  # `[dispatch] trunk` configured, `setup` refuses `no trunk ref resolves`.
  CONFLICT_TRUNK=$(git -C "${CONFLICT_REPO}" symbolic-ref HEAD)
  CONFLICT_BASE=$(git -C "${CONFLICT_REPO}" rev-parse --verify "${CONFLICT_TRUNK}")
}

conflict_teardown() {
  guard_not_real_repo "${CONFLICT_RUN}"
  rm -rf -- "${CONFLICT_RUN}"
}

# ── driving the incumbent ───────────────────────────────────────────────────

# conflict_doctrine <log> <args…> — one incumbent verb, its combined output
# captured to `<run>/<log>.log`. Returns the verb's OWN status; the caller
# decides whether a refusal is this leg's result or a defect.
#
# REDIRECTED, never piped and never substituted, for `cell_pipeline_leg`'s
# reason (probe-c3.sh:526): `$( … )` and `|` both subshell the call, so a status
# this leg means to score would arrive as the reader's instead.
#
# `-p` rather than a `cd`, so no leg depends on the shell's working directory.
conflict_doctrine() {
  local log="${CONFLICT_RUN}/$1.log" rc=0
  shift
  DOCTRINE_TRUNK_REF="${CONFLICT_TRUNK}" \
    "${CONFLICT_DOCTRINE}" "$@" -p "${CONFLICT_REPO}" >"${log}" 2>&1 || rc=$?
  return "${rc}"
}

# conflict_said <log> <text> — does the captured output carry <text>?
# `-F` literal: the guidance strings are full of shell and regex metacharacters.
conflict_said() {
  command grep -qF -- "$2" "${CONFLICT_RUN}/$1.log"
}

# conflict_commit <tree> <path> <content> <message> <who>
#
# One commit in <tree>, path-limited at BOTH the add and the commit — the
# incumbent's own rule (AGENTS.md), and load-bearing here because
# `record-boundary` commits object-db-only and leaves the coordination index
# holding a staged deletion of the file it just landed. A pathless commit in
# this tree would carry that deletion straight back out.
#
# The identity is passed EXPLICITLY. The copy does inherit the fixture's local
# config, but git's implicit `user@host` fallback happens to resolve in this
# jail — so a leg leaning on inheritance would fail somewhere else rather than
# here, and arrive as a plant that silently planted nothing (F-P05, the
# `c3_move_accepted` lesson).
conflict_commit() {
  local tree=$1 path=$2 content=$3 message=$4 who=$5
  mkdir -p -- "$(dirname -- "${tree}/${path}")"
  printf '%s\n' "${content}" >"${tree}/${path}"
  git -C "${tree}" add -- "${path}" ||
    rig_die "conflict_commit: could not stage ${path} in ${tree}"
  git -C "${tree}" -c user.name="${who}" -c user.email="${CONFLICT_MAIL}" \
    commit --quiet -m "${message}" -- "${path}"
}

# conflict_row_field <label> <key> — a field of the incumbent's OWN recorded
# candidate row. Read from `candidates.toml` rather than from the `candidate
# status` table: the table is a rendered surface with box-drawing in it, and the
# ledger is what the machinery itself keys off.
conflict_row_field() {
  sed -n "/^id = \"cand-${CONFLICT_SLICE}-$1\"\$/,/^\$/s/^$2 = \"\\(.*\\)\"\$/\\1/p" \
    "${CONFLICT_REPO}/.doctrine/dispatch/${CONFLICT_SLICE}/candidates.toml" 2>/dev/null |
    head -1
}

conflict_trunk_oid() {
  git -C "${CONFLICT_REPO}" rev-parse --verify "${CONFLICT_TRUNK}"
}

# conflict_blob <ref> <path> — the blob at <path> in <ref>, EMPTY when absent.
# Empty is a legitimate answer, not an error: the stub path does not exist at B,
# which is exactly what makes H10's pair an add/add meeting.
conflict_blob() {
  git -C "${CONFLICT_REPO}" rev-parse --verify --quiet "$1:$2" 2>/dev/null || true
}

# ── the shared prologue: a result, cut, and staged for review ───────────────

# Everything up to and including `prepare-review` — identical for both rows,
# because the rows differ in what CANONICAL does, never in what the capsule side
# delivered.
#
# PUBLISHES `CONFLICT_RESULT` (the coordination tip the review refs are cut
# from).
conflict_stage_result() {
  local at=$1 stub before
  stub=$(fixture_stub "${CONFLICT_JOINS_FIXTURE}")
  before=$(git -C "${CONFLICT_COORD}" rev-parse HEAD)

  conflict_commit "${CONFLICT_COORD}" "${stub}" \
    "${CONFLICT_RESULT_BODY}" 'result A' "${CONFLICT_RESULT_WHO}"
  CONFLICT_RESULT=$(git -C "${CONFLICT_COORD}" rev-parse HEAD)

  conflict_doctrine record-boundary dispatch record-boundary \
    --slice "${CONFLICT_SLICE}" --phase "${CONFLICT_PHASE}" \
    --code-start "${before}" --code-end "${CONFLICT_RESULT}" ||
    rig_die "${at}: record-boundary refused — see ${CONFLICT_RUN}/record-boundary.log"

  # EX-15 MADE OBSERVABLE. This is the gate F3 was provisioned for, so the leg
  # asserts it CLEARED rather than merely not dying: a `prepare-review` that
  # refused here would be a fact about the fixture's runtime state, and the two
  # rows would then refuse downstream for a reason that has nothing to do with
  # the candidate layer.
  rig_assert "${at}: prepare-review clears F3's phase-completion gate (EX-15)" \
    conflict_doctrine prepare-review dispatch sync --slice "${CONFLICT_SLICE}" --prepare-review
  rig_assert "${at}: the review surface exists to be a candidate's source" \
    git -C "${CONFLICT_REPO}" rev-parse --verify --quiet "refs/heads/review/${CONFLICT_SLICE}"
}

# ── the two canonical-side moves ────────────────────────────────────────────
#
# Each row's hazard is ONE commit on the accepted ref, and each gets a named
# function rather than an inline `conflict_commit`. Two reasons, and the second
# is the load-bearing one:
#
#   1. it is the shape `c3_move_accepted` already has for the pipeline legs —
#      canonical's mover is a thing with a name, one layer down;
#   2. a mutant can only WRAP what has a name. An inline commit is unfalsifiable
#      without restating the leg, which is the error `rebind` exists to prevent
#      (drivers/falsify-lib.sh).

# conflict_peer_half <path> — H10's other half: the SAME path from the SAME base
# B. The stub path is the one path both halves are guaranteed to touch — the
# worker stub appends to it and the contract records it as a join with the
# slice's selectors — so the pair needs no path of its own (`lib/instantiations.sh`'s
# H10 note).
conflict_peer_half() {
  conflict_commit "${CONFLICT_REPO}" "$1" \
    "${C3_STALE_MARK}: the peer half of the pair" \
    'peer landed on the accepted ref from the same base' "${C3_STALE_MARK}"
}

# conflict_move_trunk — H16's advance, on a path this result never names: the
# trivially mergeable move. `C3_H16_TRUNK_PATH` is spelled once in
# `lib/instantiations.sh` so its disjointness from the result is checkable
# against ONE string.
conflict_move_trunk() {
  conflict_commit "${CONFLICT_REPO}" "${C3_H16_TRUNK_PATH}" \
    "${C3_STALE_MARK}: trunk advanced before admission" \
    'trunk advance on a disjoint path' "${C3_STALE_MARK}"
}

# ── H10 — the conflicting pair, refused at `candidate create` ───────────────
#
# PUBLISHES `CONFLICT_PLANTED`: the positive control, and the answer to "did the
# pair actually MEET". Without it a `conflicted` verdict could as easily be the
# incumbent refusing something else.
conflict_leg_H10() {
  local at=$1 stub review peer before
  stub=$(fixture_stub "${CONFLICT_JOINS_FIXTURE}")

  conflict_peer_half "${stub}"

  review=$(conflict_blob "refs/heads/review/${CONFLICT_SLICE}" "${stub}")
  peer=$(conflict_blob "${CONFLICT_TRUNK}" "${stub}")

  # THE PAIR MEETS: both halves name the path, they disagree, and canonical's
  # half is a CHILD OF B. The parentage clause is `c3_stale_planted`'s, for its
  # reason — § 5.6 names H10 as a pair "from one base", and a peer parented
  # elsewhere would still conflict, so the leg would score green while
  # instantiating a different row.
  rig_assert "${at}: canonical's half is a child of B (a PAIR, not two commits)" \
    test "$(git -C "${CONFLICT_REPO}" rev-parse --verify "${CONFLICT_TRUNK}^")" = "${CONFLICT_BASE}"
  rig_assert "${at}: the capsule's half names ${stub}" test -n "${review}"
  rig_assert "${at}: canonical's half names ${stub}" test -n "${peer}"
  rig_assert "${at}: the two halves DISAGREE — an add/add meeting, not a race" \
    test "${review}" != "${peer}"
  CONFLICT_PLANTED="pair-meets ${stub} ${review:0:7}/${peer:0:7}"

  # Read BEFORE the verb runs. Comparing the ref to itself afterwards would be
  # the assertion that cannot fail — the shape a "nothing landed" check is most
  # likely to rot into.
  before=$(conflict_trunk_oid)

  # THE ASYMMETRY THIS LEG FOUND (F-P05-40), asserted as a SUCCESS rather than
  # tolerated as one. `candidate create` exits ZERO on a content conflict:
  # SL-212 made the Conflicted row a recorded LIFECYCLE STATE with a
  # hand-resolution continuation (`ingest`), not a command failure —
  # `create_conflict_worktree` returns `Ok(())` deliberately
  # (`src/dispatch.rs:2803`), and the sibling arm's `Ok` is the same ruling.
  #
  # So on this layer "I will not auto-resolve" is carried by the LEDGER, and a
  # caller reading the exit status alone cannot see it. H16's integrate signals
  # the SAME refusal non-zero. Within one layer the conflict path and the
  # staleness path disagree about how a refusal is signalled — an ergonomics
  # fact QUE-202 owns, and one the four-stage model does not have (every stage
  # there refuses through one token vocabulary, VA-2).
  #
  # An exit-status assertion here would have been the wrong question, and the
  # three below are the right one: the classification, the guidance, and the
  # absence of a merge are where the refusal actually lives.
  rig_assert "${at}: \`candidate create\` exits ZERO on a conflict — the refusal is LEDGERED, not status-borne (F-P05-40)" \
    conflict_doctrine create dispatch candidate create \
    --slice "${CONFLICT_SLICE}" --label h10 --role review_surface --payload code \
    --base "${CONFLICT_TRUNK}" --worktree

  # The CLASSIFICATION, from the incumbent's own ledger — a refusal that left no
  # row would be a different result from one that recorded `conflicted`.
  rig_assert_eq "${at}: the candidate row records the Conflicted classification" \
    conflicted "$(conflict_row_field h10 status)"
  rig_assert "${at}: the guidance names hand-resolution (\`candidate ingest\`)" \
    conflict_said create 'dispatch candidate ingest'

  # NOTHING WAS AUTO-RESOLVED AND NOTHING LANDED — the half of § 5.1's claim
  # that the error text alone does not carry.
  rig_assert_eq "${at}: trunk is unmoved by the refusal — nothing landed" \
    "${before}" "$(conflict_trunk_oid)"
  rig_assert_eq "${at}: no merge was recorded for the conflicted row" \
    '' "$(conflict_row_field h10 merge_oid)"
}

# ── H16 — trunk moved before admission, refused at the integrate CAS ────────
conflict_leg_H16() {
  local at=$1 moved

  # Both candidates pinned at B, BEFORE canonical moves. A close_target is not
  # optional scaffolding: integration refuses outright without an admitted one
  # rather than falling back to a raw phase ref, so the CAS this row is here to
  # observe is unreachable without it.
  rig_assert "${at}: the review surface is candidated at B" \
    conflict_doctrine create-review dispatch candidate create \
    --slice "${CONFLICT_SLICE}" --label h16 --role review_surface --payload code \
    --base "${CONFLICT_TRUNK}" --worktree
  rig_assert "${at}: the close target is candidated at B" \
    conflict_doctrine create-close dispatch candidate create \
    --slice "${CONFLICT_SLICE}" --label h16-close --role close_target --payload code \
    --base "${CONFLICT_TRUNK}" --source "refs/heads/review/${CONFLICT_SLICE}"

  # NOW canonical advances — after the candidates pinned B, before admission.
  conflict_move_trunk
  moved=$(conflict_trunk_oid)

  rig_assert_eq "${at}: canonical moved to a CHILD of the pinned base" \
    "${CONFLICT_BASE}" "$(git -C "${CONFLICT_REPO}" rev-parse --verify "${moved}^")"
  rig_assert_eq "${at}: it moved on a path the result never names" \
    '' "$(conflict_blob "refs/heads/review/${CONFLICT_SLICE}" "${C3_H16_TRUNK_PATH}")"
  CONFLICT_PLANTED="trunk-moved ${CONFLICT_BASE:0:7}->${moved:0:7}"

  # ADMISSION IS INDIFFERENT TO THE MOVE. Asserted as a PASS, not tolerated as
  # one: "trunk moved before admission" is this row's scenario, and the fact
  # that admission takes it anyway is what makes the integrate CAS the sole
  # place staleness is caught on this layer.
  rig_assert "${at}: \`admit\` accepts the review surface with trunk already moved" \
    conflict_doctrine admit-review dispatch candidate admit \
    --slice "${CONFLICT_SLICE}" --role review_surface \
    --candidate "refs/heads/candidate/${CONFLICT_SLICE}/h16"
  rig_assert "${at}: \`admit\` accepts the close target with trunk already moved" \
    conflict_doctrine admit-close dispatch candidate admit \
    --slice "${CONFLICT_SLICE}" --role close_target \
    --candidate "refs/heads/candidate/${CONFLICT_SLICE}/h16-close"

  # The refusal, at the fast-forward CAS.
  rig_assert_fails "${at}: integrate refuses a close target that no longer fast-forwards" \
    conflict_doctrine integrate dispatch sync \
    --slice "${CONFLICT_SLICE}" --integrate --trunk "${CONFLICT_TRUNK}"
  rig_assert "${at}: the guidance is to SUPERSEDE on the new base" \
    conflict_said integrate 'superseding close-target candidate on the new base'
  rig_assert "${at}: and it states the refusal is not auto-resolved" \
    conflict_said integrate 'not auto-resolved'

  rig_assert_eq "${at}: trunk is unmoved by the refusal — nothing landed" \
    "${moved}" "$(conflict_trunk_oid)"
}

# ── the entry point `probe-c3.sh` calls ─────────────────────────────────────

# conflict_subprobe <row> — ONE leg, ONE recorded entry (F-9).
#
# `c3_run_conflict` asserts the entry count, so this function must record
# exactly once on every path it can return from. It therefore does NOT `rig_die`
# on a leg's refusal: a leg that fails is a FAILED ENTRY in the results file,
# which `row_outcome` derives from the assertions the leg actually made. The
# only deaths here are provisioning deaths, before any entry is owed.
conflict_subprobe() {
  local row=$1 verb token inst
  local at="${row}/${CONFLICT_VARIANT}/candidate"

  # The incumbent's refusal points, in the columns the pipeline uses for its
  # own — and deliberately NOT in the pipeline's vocabulary. See the header.
  #
  # `inst` is the ROW'S OWN ACCOUNT OF ITSELF, per row rather than a shared
  # template, and that is not formatting: the two rows refuse in materially
  # different ways, and one sentence covering both could only do it by saying
  # "refuses" of a verb that exits zero. The results file is what T8 reads.
  case "${row}" in
    H10)
      verb=candidate-create
      token=conflicted
      inst='the pair is classified Conflicted and parked for hand-resolution (ingest). The refusal to auto-resolve is LEDGERED, not status-borne — the verb exits ZERO (F-P05-40)'
      ;;
    H16)
      verb=integrate
      token=stale-trunk
      inst='create and admit BOTH accept the moved trunk; the fast-forward CAS at integrate is the sole place staleness is caught, and it refuses non-zero, guiding to supersede on the new base'
      ;;
    *) rig_die "conflict_subprobe: no sub-probe leg for row: ${row}" ;;
  esac

  row_begin "${at} — ${verb}/${token} (incumbent regression; counts toward nothing)"
  CONFLICT_PLANTED=''

  conflict_provision "c3-conflict-${row}"
  conflict_doctrine setup dispatch setup \
    --slice "${CONFLICT_SLICE}" --dir "${CONFLICT_COORD}" ||
    rig_die "${at}: dispatch setup refused — see ${CONFLICT_RUN}/setup.log"

  conflict_stage_result "${at}"
  "conflict_leg_${row}" "${at}"

  record_row "${row}" "${CONFLICT_VARIANT}" candidate conflict '-' \
    "the incumbent's RESOLUTION leg (§ 5.1 D8) — F3 on the real candidate layer, refusing at ${verb}: ${inst}. Regression check on machinery being replaced; NOT capsule-model evidence, counts toward nothing (F-9)" \
    "${verb}" "${token}" "${CONFLICT_PLANTED}" "${CONFLICT_ALTITUDE}"

  conflict_teardown
}
