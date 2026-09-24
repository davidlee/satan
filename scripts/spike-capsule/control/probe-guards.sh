#!/usr/bin/env bash
# control/probe-guards.sh — THE FIVE GUARD PROBES (SL-241 PHASE-05 T6;
# EX-10, EX-11, VA-2, VA-3).
#
#   usage: probe-guards.sh [a|b|c|d|e …]     (dispatched by `rig guards`)
#          probe-guards.sh --positive-control  this probe's OWN red/green; no
#                                              provisioning, no legs, no results
#   env:   SPIKE_CAPSULE_ROOT  capsule / fixture root (default: ~/capsules)
#
# ── the claim, and why it needs a probe at all ──────────────────────────────
#
# EX-10: each of the five guards must be **OBSERVED REFUSING at least once**,
# because a guard never seen to fire is not known to work. That is the same
# discipline `rig_guard_probe` applies to I6 and `audit-i4a.sh --positive-
# control` applies to itself — an untested guard and an absent one are
# indistinguishable from the outside, and the results table cannot tell them
# apart either.
#
# ── these are NOT matrix rows, and the separation is load-bearing ───────────
#
# The five guards have no `Hnn_{mutate,planted,assert}` triple, no fixture ×
# mechanism cross-product, and no altitude. They are not scored against § 5.6's
# re-derived boundary and they must never be summed with the sixteen rows. So
# they record into their OWN file — `probes/guards/results.tsv` — rather than
# appending to `probes/c3/results.tsv` with a discriminator column that a reader
# tallying the table would have to notice. `lib/conflict.sh` solved the same
# problem the other way (a `counts-toward-nothing` altitude) because its entries
# genuinely belong on the matrix's axes; these do not.
#
# What IS shared is the vocabulary: `lib/instantiations.sh`'s plant helpers and
# — critically — its named constants. Guard (b) plants `C3_H5_NONASCII` and
# guard (c) renames `C3_H5_RENAME_SRC`, the same literals H5 uses, because a
# guard probe spelling its own path would be proving something about a path the
# matrix never touched (STD-001).
#
# ── (b) and (c) are ISOLATED, and that is D-P05-10's ruling ─────────────────
#
# H5 plants all three forms into ONE range, so conform leg 3 returns on the
# first matching path and the other two refuse on its behalf (F-P05-22). A
# combined range therefore observes NEITHER the non-ASCII form nor the rename.
# Each is its own probe here, and the isolation is ASSERTED per leg — exactly
# one governance path in the range — rather than believed from the plant code.
#
# ── what this probe will not do ─────────────────────────────────────────────
#
# It will not report a leg it did not run. Guard (a) is the one leg satisfied by
# CITATION rather than by a fresh run, and the citation is MECHANICAL: it reads
# H8's entries out of the committed `probes/c3/results.tsv` and reds if they are
# not there. A citation that could not fail would be an assertion about a
# memory of a run, which is the shape D-P01-5 exists to refuse.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=pipeline.sh
. "${RIG_DIR}/control/pipeline.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/fixtures.sh
. "${RIG_DIR}/lib/fixtures.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/rows.sh
. "${RIG_DIR}/lib/rows.sh"
# The capsule-plant vocabulary AND the shared path constants. Sourced for
# `c3_plant_file` / `c3_commit` / `c3_publish` / `c3_range` / `c3_lines_have` /
# `c3_planted_paths` / `c3_assert_ingested` / `c3_assert_stage_passed`, and for
# `C3_H5_NONASCII` and `C3_H5_RENAME_SRC|DST`. None of the sixteen `Hnn_*` trios
# is called from here; they are inert definitions.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/instantiations.sh
. "${RIG_DIR}/lib/instantiations.sh"

# guard | fixture | leg | outcome | observed | claim
#
# `observed` is this file's positive control, in `ROWS_OBSERVABLE_FIELD`'s sense:
# a leg that ran but named nothing it saw is the silent pass, and
# `rows_assert_complete` reds it.
GUARDS_COLUMNS=$'guard\tfixture\tleg\toutcome\tobserved\tclaim'
ROWS_OUTCOME_FIELD=4
ROWS_OBSERVABLE_FIELD=5

ALL_GUARDS='a b c d e'

# Guard (a)'s citation source — P-C3's own committed results file.
GUARDS_C3_RESULTS_REL='probes/c3/results.tsv'

# Guard (d)'s two plants. The runner's NAME, at the two paths a capsule can
# actually reach — named once, because the assertion and the plant must agree
# about what was planted (STD-001).
GUARDS_RUNNER_NAME='verify.sh'
GUARDS_D_TREE_RUNNER="src/${GUARDS_RUNNER_NAME}"

# Guard (e)'s substitution. `false` rather than `true` on purpose: the honest
# `verify:` command PASSES on this fixture, so a hostile command that also
# passed would leave the two runs identical for a reason that is not the
# invariant. A command that would REFUSE makes the comparison discriminating —
# if the control plane had read the capsule's copy, stage 3 would carry
# `verify/suite-failed` and the byte comparison would say so.
GUARDS_E_HOSTILE_VERIFY='false'
GUARDS_E_DECLARATION='interpretation-surface.txt'

# ── the run seam, split at the plant point ──────────────────────────────────
#
# Two calls rather than one, for the reason `pipeline_capsule` and
# `pipeline_run` are two calls: the adversary plants BETWEEN them. Both PUBLISH
# rather than print — `pipeline_setup` calls `guard_not_real_repo`, which
# refuses by `exit`, and a caller forced into `$( … )` to read the run dir would
# lose that refusal in the substitution's subshell (F-P01-1).

GUARDS_RUN=''
GUARDS_OBSERVED=''

guards_provision() {
  local label=$1 fixture=$2
  pipeline_setup "${label}" "$(fixture_repo "${fixture}")" \
    "$(fixture_declaration "${fixture}")" \
    "$(fixture_slice "${fixture}")" "$(fixture_stub "${fixture}")"
  GUARDS_RUN="${PIPELINE_RUN}"

  # Per fixture, set for this leg only — the D-P05-7 reason: a leg reading these
  # must not inherit the previous leg's fixture.
  PIPELINE_VERIFY_TIMEOUT="$(fixture_verify_timeout "${fixture}")"
  PIPELINE_VERIFY_DISK_CAP="$(fixture_verify_disk_cap "${fixture}")"

  pipeline_capsule "${GUARDS_RUN}"
}

# REDIRECTED, never piped and never substituted: a pipe or a `$( … )` subshells
# `pipeline_run`, so a RIG DEFECT return could not reach this shell and the leg
# would score as an ordinary refusal (`cell_pipeline_leg` is the reference form).
guards_pipeline() {
  local run=$1 mechanism=${2:-fetch} rc=0
  pipeline_run "${run}" "${mechanism}" >"${run}/stages" || rc=$?
  if [ "${rc}" -eq "${RIG_EXIT_DEFECT}" ]; then
    rig_warn 'guards: RIG DEFECT from the pipeline — not a result'
    exit "${RIG_EXIT_DEFECT}"
  fi
  GUARDS_OBSERVED=$(pipeline_first_refusal "${run}/stages")
}

# ── the shared observables ──────────────────────────────────────────────────

# guards_governance_paths <run> — how many `.doctrine/`/`.claude/` paths are in
# the range the capsule published. THE ISOLATION CLAIM, made mechanical.
#
# Leg 3 returns on the FIRST matching path, so a leg that meant to observe one
# form and planted two observes whichever sorted first — and cannot tell. This
# is the only thing standing between (b)/(c) and re-running H5 under a new name
# (F-P05-22).
guards_governance_paths() {
  local run=$1 changed path n=0
  changed=$(c3_range "$(c3_capsule_repo "${run}")" \
    "$(c3_base "${run}")" "$(c3_result "${run}")")
  while IFS= read -r path; do
    case "${path}" in
      .doctrine/* | .claude/*) n=$((n + 1)) ;;
    esac
  done <<<"${changed}"
  printf '%s' "${n}"
}

# guards_assert_isolated <at> <run> — exactly one, and it is named in the leg's
# own plant. Asserted rather than asserted-away: the count is the observable a
# reader needs to believe the word "isolated" in the results file.
guards_assert_isolated() {
  rig_assert_eq "$1: EXACTLY ONE governance path in the range — the leg is isolated (F-P05-22)" \
    1 "$(guards_governance_paths "$2")"
}

# guards_range_rename_aware <repo> <base> <oid> — the range git computes WITH
# rename detection. Deliberately NOT `c3_range`: this is the EVASION's view, and
# the whole of guard (c) is that the two disagree.
guards_range_rename_aware() {
  git -C "$1" -c core.quotePath=false diff --name-only --find-renames -z "$2..$3" |
    tr '\0' '\n'
}

# guards_trusted_side <run> — everything about a run that is a statement about
# WHAT THE CONTROL PLANE DID, and nothing that is a statement about which
# repository it did it to.
#
# Two fields, and the exclusions are the point. `base` and `accepted` are OIDs,
# so they differ between F1 and F2 for a reason that is fixture identity rather
# than behaviour; including them would make the comparison unfalsifiable-by-
# construction in the wrong direction — always unequal, never informative.
# What remains is the verify command the control plane RESOLVED (guard (e)'s
# actual subject) and the stage ladder it emitted.
guards_trusted_side() {
  local run=$1
  printf 'verify=%s\n' "$(contract_field "${run}" verify)"
  cat -- "${run}/stages"
}

# ── this probe's own red/green, before it probes anything ───────────────────
#
# Every leg below is scored by the helpers above, so "the harness works" cannot
# be a claim about the code — it has to be an observation, and one taken BEFORE
# the legs rather than after (probe-c3's `c3_positive_control` is the precedent;
# a scorer proven after the fact proves it for the next run, not this one).

# Returns 0 when the guarded assertion REDS. Counter reset in a subshell so a
# deliberate red does not poison the real tally.
guards_isolation_reds() {
  local count=$1
  ! (
    RIG_ASSERT_FAILURES=0
    rig_assert_eq 'self-check' 1 "${count}" >/dev/null 2>&1
    [ "${RIG_ASSERT_FAILURES}" -eq 0 ]
  )
}

guards_positive_control() {
  printf '\nprobe positive control — the observables, before they observe (EX-10)\n'

  # The isolation counter is what separates (b)/(c) from a second H5. A count of
  # two must RED, or a leg that planted both forms would report the first one
  # and read as an isolated observation of it.
  rig_assert 'a range with TWO governance paths REDS the isolation clause' \
    guards_isolation_reds 2
  rig_assert 'a range with NONE reds it too — an unplanted leg is not isolated' \
    guards_isolation_reds 0
  rig_assert_fails 'and exactly one does NOT red it' guards_isolation_reds 1

  # `guards_trusted_side` must be sensitive to the one field guard (e) turns on.
  # A comparator blind to `verify=` would call every pair of runs identical and
  # score (e) green against a control plane that HAD read the capsule's copy.
  local a b
  a=$(printf 'verify=npm test\nstage=verify verdict=pass token=\n')
  b=$(printf 'verify=%s\nstage=verify verdict=pass token=\n' "${GUARDS_E_HOSTILE_VERIFY}")
  rig_assert_fails 'the trusted-side comparison DISTINGUISHES a substituted verify command' \
    test "${a}" = "${b}"
  rig_assert 'and calls two identical observations equal' test "${a}" = "${a}"
}

# ── (a) gitlink + .gitmodules — CITED from H8's committed run ───────────────
#
# The one leg that is not a fresh run, and the reasoning is stated rather than
# assumed. EX-10 asks for the OBSERVATION, not for a fifth script: H8 IS guard
# (a) — `probes/c3/matrix.tsv` names it so in the instantiation column — and its
# `conform/gitlink` and `conform/gitmodules` alternatives are each already
# observed passing, on both fixtures and both mechanisms, in a scored run.
# Re-running it here would produce a second copy of an observation the corpus
# already holds, and would tempt a reader into counting it twice.
#
# The citation is MECHANICAL. It reads the committed results file and counts the
# entries; if H8 were removed, rerun without those alternatives, or scored
# anything but `pass`, this leg REDS. A citation that cannot fail is prose.

guards_h8_entries() {
  local token=$1
  awk -F'\t' -v t="${token}" \
    '$1 == "H8" && $7 == "conform" && $8 == t && $10 == "pass" { n++ } END { print n + 0 }' \
    "${GUARDS_C3_RESULTS}"
}

guard_a() {
  local token n
  rig_assert "guard (a): P-C3's results file exists to cite — ${GUARDS_C3_RESULTS}" \
    test -s "${GUARDS_C3_RESULTS}"

  # The negative control FIRST. Without it, `n > 0` proves only that awk ran:
  # a filter that matched every line would satisfy both tokens and say nothing.
  # `forbidden-path` is a real conform token that H8 never produces.
  rig_assert_eq 'guard (a): the citation counter DISCRIMINATES — H8 never scored conform/forbidden-path' \
    0 "$(guards_h8_entries forbidden-path)"

  for token in gitlink gitmodules; do
    row_begin "guard (a)/${token} — cited from H8's scored run (F-2)"
    n=$(guards_h8_entries "${token}")
    rig_assert "guard (a): H8 is observed refusing conform/${token} in a scored run (${n} entries)" \
      test "${n}" -gt 0
    record_row a - "cite:H8/${token}" "${n} scored entries at conform/${token}" \
      'F-2 leg 4, the mode-aware leg. OBSERVED by H8 on both fixtures and both mechanisms; cited, not re-run, so the corpus holds one copy of the observation'
  done
}

# ── (b) a non-ASCII `.doctrine/` path, ALONE in the range ───────────────────
#
# Runs on BOTH fixtures, because the path was chosen to be design-target on each
# (`lib/instantiations.sh`'s surface table): light declares `.doctrine/**`,
# heavy declares `.doctrine/rfc/025/evidence/**`, and leg 2 runs BEFORE leg 3 —
# an undeclared plant would refuse `undeclared-path` and observe nothing about
# the guard under test (F-P05-18).
#
# WHAT THIS LEG DOES NOT PROVE, recorded because the temptation to claim it is
# real: it does not show `core.quotePath=false` is load-bearing. `-z` already
# defeats the C-quoting evasion on its own (F-P05-23), so a leg that dropped the
# quotePath setting would still pass. The claim is narrower and exact — leg 3
# fires on a non-ASCII path.

guard_b() {
  local fixture run at planted
  for fixture in light heavy; do
    at="guard (b)/${fixture}"
    row_begin "${at} — a non-ASCII governance path, isolated (F-4)"

    guards_provision "guards-b-${fixture}" "${fixture}"
    run="${GUARDS_RUN}"

    c3_plant_file "${run}" "${C3_H5_NONASCII}"
    c3_commit "${run}" 'guard (b): a non-ASCII governance path' "${C3_H5_NONASCII}"
    c3_publish "${run}"

    planted=$(c3_planted_paths "${run}" "${C3_H5_NONASCII}") || planted=''
    rig_assert "${at}: planted? — the non-ASCII path is in the published range" \
      test -n "${planted}"
    guards_assert_isolated "${at}" "${run}"

    guards_pipeline "${run}"

    c3_assert_stage_passed "${at}" "${run}" harvest
    c3_assert_ingested "${at}" "${run}" "${C3_H5_NONASCII}"
    rig_assert_eq "${at}: conform leg 3 REFUSES the non-ASCII governance path" \
      'conform/forbidden-path' "${GUARDS_OBSERVED}"
    assert_outcome "${run}" "${GUARDS_OBSERVED}"

    record_row b "${fixture}" nonascii "${GUARDS_OBSERVED}" \
      'leg 3 fires on a non-ASCII path, isolated in the range. Does NOT prove core.quotePath=false is load-bearing — -z already defeats that evasion (F-P05-23)'
    pipeline_teardown "${run}"
  done
}

# ── (c) a rename OUT of `.doctrine/`, ALONE in the range ────────────────────
#
# LIGHT ONLY (F-P05-21), and that is not an `n/a` against the model: leg 3 reads
# a two-dot TREE diff, so the rename source must exist AT B, and heavy's sole
# design-target `.doctrine/` prefix holds zero files there. A guard is observed
# once, not per fixture (D-P05-10).
#
# BOTH DIRECTIONS, because here the evasion is real and the falsifier is not
# hypothetical. Git's own rename detection makes the `.doctrine/` SOURCE leg
# VANISH from the range — the destination alone remains, and it is not a
# governance path — so a leg 3 written without `--no-renames` would pass this
# capsule. The probe asserts the guard fires AND that the thing it defends
# against genuinely hides, over one computation.

guard_c() {
  local at='guard (c)/light' run repo planted evaded
  row_begin "${at} — a rename OUT of .doctrine/, isolated, both directions (F-4)"

  guards_provision guards-c light
  run="${GUARDS_RUN}"
  repo=$(c3_capsule_repo "${run}")

  # `git mv` rather than a delete-plus-add, so the range carries a REAL rename
  # for git's own detector to find — a hand-rolled pair would exercise the
  # evasion against something git never had to detect.
  #
  # DESTINATION ONLY at the commit, and this is H5's lesson ridden rather than
  # re-met (`lib/instantiations.sh:501-507`): `git mv` has already staged both
  # legs, so the source exists in neither the worktree nor the index and
  # re-adding it matches no pathspec at all. The deletion still lands —
  # `c3_commit`'s `git commit` carries no pathspec and takes the whole index.
  git -C "${repo}" mv -- "${C3_H5_RENAME_SRC}" "${C3_H5_RENAME_DST}"
  c3_commit "${run}" 'guard (c): a rename out of .doctrine/' "${C3_H5_RENAME_DST}"
  c3_publish "${run}"

  planted=$(c3_planted_paths "${run}" "${C3_H5_RENAME_SRC}" "${C3_H5_RENAME_DST}") || planted=''
  rig_assert "${at}: planted? — both legs of the rename are in the belt's view of the range" \
    test -n "${planted}"
  guards_assert_isolated "${at}" "${run}"

  # THE EVASION, demonstrated rather than asserted. Same range, same repo, one
  # flag different. The destination clause is the control that says this range
  # was computed against something real — a bare "the source is absent" passes
  # just as well when the range came back empty (the `c3_assert_range` lesson).
  evaded=$(guards_range_rename_aware "${repo}" "$(c3_base "${run}")" "$(c3_result "${run}")")
  rig_assert "${at}: with rename detection the DESTINATION is still in the range" \
    c3_lines_have "${evaded}" "${C3_H5_RENAME_DST}"
  rig_assert_fails "${at}: …and the .doctrine/ SOURCE has VANISHED — --no-renames is load-bearing" \
    c3_lines_have "${evaded}" "${C3_H5_RENAME_SRC}"

  guards_pipeline "${run}"

  c3_assert_stage_passed "${at}" "${run}" harvest
  c3_assert_ingested "${at}" "${run}" "${C3_H5_RENAME_SRC}"
  rig_assert_eq "${at}: conform leg 3 REFUSES the renamed-out governance path" \
    'conform/forbidden-path' "${GUARDS_OBSERVED}"
  assert_outcome "${run}" "${GUARDS_OBSERVED}"

  record_row c light rename-out "${GUARDS_OBSERVED}" \
    'leg 3 fires on a rename OUT of .doctrine/, isolated. Both directions: with --find-renames the source leg vanishes and the same capsule passes, so --no-renames is load-bearing. LIGHT ONLY — heavy has no source to rename at B (F-P05-21)'
  pipeline_teardown "${run}"
}

# ── (d) a capsule that overwrites its own verify.sh ─────────────────────────
#
# I4a: the runner enters at `/rig/verify.sh`, a read-only bind from OUTSIDE the
# writable root, so no script the capsule can write is ever the process whose
# exit status is the verdict (`capsule/verify.sh:14-17` names this leg as its
# subject). The mount posture makes that structural — this leg is the
# BEHAVIOURAL half, and `control/audit-i4a.sh` is the STATIC half. Neither
# substitutes for the other, and both run here.
#
# ── the discrimination, which is the whole design of this leg ───────────────
#
# The honest `verify:` command PASSES on this fixture, so a plant alone proves
# nothing: real runner and hostile runner would both end in a pass and the leg
# would be green against an I4a that had been undone. So the capsule ALSO breaks
# the suite. Now the two answers differ — the real runner refuses
# `verify/suite-failed`, the planted one would exit 0 — and observing the
# refusal is observing the guard.
#
# TWO PLANTS, at the two paths a capsule can actually reach:
#
#   /capsule/verify.sh          the worker capsule's own root, adjacent to the
#                               `--chdir`. Never harvested, never in the range.
#   /capsule/repo/src/verify.sh committed at a DECLARED path, so it survives
#                               conform and is cloned into the VERIFY capsule,
#                               inside the tree `verify.sh` cds to.
#
# Neither is `/rig/verify.sh`, and that is the invariant. A THIRD path — the
# clone root — is deliberately not attempted: it is undeclared on this fixture,
# so it would refuse at conform leg 2 and the leg would observe nothing.

guards_hostile_runner() {
  printf '#!/usr/bin/env bash\n# %s: a capsule-authored runner that attests unconditionally.\nexit 0\n' \
    "${C3_PAYLOAD_MARK}" >"$1"
  chmod +x -- "$1"
}

guard_d() {
  local at='guard (d)/light' run repo capsule_runner planted
  row_begin "${at} — a capsule that overwrites its own verify.sh; the verdict is UNAFFECTED (F-11/I4a)"

  guards_provision guards-d light
  run="${GUARDS_RUN}"
  repo=$(c3_capsule_repo "${run}")
  capsule_runner="${run}/capsule/${GUARDS_RUNNER_NAME}"

  # The static half's NEGATIVE control, taken before the plant. Without it the
  # refusal below proves only that the audit refuses — which an audit that
  # refuses everything also does, and that is exactly as broken.
  rig_assert "${at}: audit-i4a PASSES the unmutated capsule (negative control)" \
    "${RIG_DIR}/control/audit-i4a.sh" "${run}/capsule"

  guards_hostile_runner "${capsule_runner}"
  guards_hostile_runner "${repo}/${GUARDS_D_TREE_RUNNER}"
  # Breaks the suite for real: the payload mark is appended to the module the
  # test file imports, so `node --test` fails to parse it. The refusal is the
  # project's own toolchain answering, not a rig-authored verdict.
  c3_plant_file "${run}" src/money.ts
  c3_commit "${run}" 'guard (d): a capsule-authored runner, and a broken suite' \
    "${GUARDS_D_TREE_RUNNER}" src/money.ts
  c3_publish "${run}"

  planted=$(c3_planted_paths "${run}" "${GUARDS_D_TREE_RUNNER}" src/money.ts) || planted=''
  rig_assert "${at}: planted? — the capsule-authored runner and the broken module are in the range" \
    test -n "${planted}"
  # The plant WOULD have attested. Without this the leg cannot claim the two
  # runners disagree, only that one of them refused.
  rig_assert "${at}: the planted runner exits 0 — had it been the verdict, this capsule would have ATTESTED" \
    "${repo}/${GUARDS_D_TREE_RUNNER}"
  # `rig_assert_fails`, never `rig_assert … ! cmd`: `!` is a shell KEYWORD, so
  # the latter passes it as the command NAME and reds on the invocation without
  # ever scoring the refusal (common.sh:291-294 — met on this phase's own I4a
  # positive control).
  rig_assert_fails "${at}: audit-i4a REFUSES the mutated capsule (the static half, positive control)" \
    "${RIG_DIR}/control/audit-i4a.sh" "${run}/capsule"

  guards_pipeline "${run}"

  c3_assert_stage_passed "${at}" "${run}" conform
  c3_assert_ingested "${at}" "${run}" "${GUARDS_D_TREE_RUNNER}"
  rig_assert_eq "${at}: the verdict is the RO-BOUND runner's — the broken suite refuses" \
    'verify/suite-failed' "${GUARDS_OBSERVED}"
  assert_outcome "${run}" "${GUARDS_OBSERVED}"

  record_row d light verify-shadow "${GUARDS_OBSERVED}" \
    'a capsule-authored verify.sh at /capsule/ and at a declared tree path changes nothing: the verdict is the ro-bound /rig/verify.sh running B'"'"'s command. Behavioural half; audit-i4a is the static half and both ran'
  pipeline_teardown "${run}"
}

# ── (e) a capsule that rewrites its own declaration ─────────────────────────
#
# EX-11 / VA-3, and QUE-201's ONLY evidence input. In the rig as drawn the
# attack is NOT LIVE — both light and heavy keep the declaration OUTSIDE the
# clone, as a sibling — so F2 (`fixtures/light-inrepo`) manufactures the
# exposure QUE-201 candidates 1 and 2 describe: a declaration copy INSIDE the
# repository.
#
# ── the evidence is the COMPARISON, not the claim ──────────────────────────
#
# Three legs, and the baseline is a leg rather than a paragraph:
#
#   e1  F1, unmutated. The honest four-stage run.
#   e2  F2, the capsule rewrites its in-repo copy IN THE WORKTREE. Trusted-side
#       behaviour must be BYTE-IDENTICAL to e1.
#   e3  F2, the capsule COMMITS the rewrite, so it enters the range.
#
# e2 and e3 are different attacks, not two spellings of one. e2 asks whether the
# control plane reads anything the capsule's working tree holds; e3 asks whether
# it reads `<S>:<path>` — the read `pipeline.sh:208-212` pins as one that must
# NEVER become the S side. Only e2 can be byte-identical by construction, and
# only e3 can show what happens when the substitution is in the published range.

guards_declaration_copy() { printf '%s/%s' "$(c3_capsule_repo "$1")" "${GUARDS_E_DECLARATION}"; }

# The capsule rewrites its own copy. `sed` over the file in place of a hand-
# written declaration so the substitution differs from the honest one in the
# `verify:` line and NOWHERE ELSE — a wholly different file would leave the
# comparison unable to say which difference the trusted side ignored.
guards_substitute_declaration() {
  local copy=$1 tmp="$1.hostile"
  sed "s|^verify:.*|verify:    ${GUARDS_E_HOSTILE_VERIFY}|" "${copy}" >"${tmp}"
  mv -- "${tmp}" "${copy}"
}

guard_e() {
  local at run copy honest baseline observed_e1

  # ── e1: the baseline ──
  at='guard (e)/light'
  row_begin "${at} — baseline: F1, no in-repo declaration, unmutated (VA-3)"
  guards_provision guards-e1-light light
  run="${GUARDS_RUN}"
  guards_pipeline "${run}"
  # EVERY STAGE ASSERTED BY NAME, and "refuses nowhere" is not a substitute for
  # it: a run that SKIPPED a stage entirely also refuses nowhere, and this
  # baseline is what e2's byte comparison is anchored to — a ladder with a hole
  # in it would be reproduced faithfully and compare equal (selftest_happy's
  # reason, the F-P02-1/2 adjacent-observable shape).
  local stage
  for stage in harvest conform verify advance; do
    c3_assert_stage_passed "${at}" "${run}" "${stage}"
  done
  rig_assert_eq "${at}: the baseline run refuses NOWHERE" '' "${GUARDS_OBSERVED}"
  assert_outcome "${run}" "${GUARDS_OBSERVED}"
  baseline=$(guards_trusted_side "${run}")
  observed_e1="${GUARDS_OBSERVED:-no refusal}"
  record_row e light baseline "${observed_e1}" \
    'the run the substitution legs are compared against: F1 keeps its declaration outside the clone, so the capsule has nothing to rewrite'
  pipeline_teardown "${run}"

  # ── e2: the worktree rewrite ──
  at='guard (e)/light-inrepo/worktree'
  row_begin "${at} — the capsule rewrites its in-repo declaration (EX-11, QUE-201)"

  honest=$(declaration_field "$(fixture_declaration light-inrepo)" verify)
  rig_assert "${at}: VA-3 — the F2 variant exists and carries an in-repo declaration" \
    test -f "$(fixture_repo light-inrepo)/${GUARDS_E_DECLARATION}"

  guards_provision guards-e2-inrepo light-inrepo
  run="${GUARDS_RUN}"
  copy=$(guards_declaration_copy "${run}")
  rig_assert "${at}: the capsule can reach its own copy — it is in the provisioned clone" \
    test -f "${copy}"
  guards_substitute_declaration "${copy}"

  # planted?: the substitution really happened, and it really would have
  # mattered. Both halves — a rewrite that left the command unchanged would
  # satisfy the byte comparison for no reason at all.
  rig_assert_eq "${at}: planted? — the capsule's copy now carries the hostile command" \
    "${GUARDS_E_HOSTILE_VERIFY}" "$(declaration_field "${copy}" verify)"
  rig_assert "${at}: …and it differs from the honest one, so the comparison can discriminate" \
    test "${GUARDS_E_HOSTILE_VERIFY}" != "${honest}"

  guards_pipeline "${run}"

  rig_assert_eq "${at}: the control plane resolved B's command, never the capsule's" \
    "${honest}" "$(contract_field "${run}" verify)"
  rig_assert_eq "${at}: trusted-side behaviour is BYTE-IDENTICAL to the F1 baseline (VA-3)" \
    "${baseline}" "$(guards_trusted_side "${run}")"
  assert_outcome "${run}" "${GUARDS_OBSERVED}"
  record_row e light-inrepo decl-worktree "${GUARDS_OBSERVED:-no refusal}" \
    'byte-identical to the F1 baseline: the control plane never reads a declaration the capsule can write. QUE-201 candidates 1 and 2, evidenced by comparison'
  pipeline_teardown "${run}"

  # ── e3: the committed rewrite ──
  at='guard (e)/light-inrepo/committed'
  row_begin "${at} — the capsule COMMITS the rewrite, so it enters the range"

  guards_provision guards-e3-inrepo light-inrepo
  run="${GUARDS_RUN}"
  copy=$(guards_declaration_copy "${run}")
  guards_substitute_declaration "${copy}"
  c3_commit "${run}" 'guard (e): a committed declaration rewrite' "${GUARDS_E_DECLARATION}"
  c3_publish "${run}"

  rig_assert "${at}: planted? — the rewritten declaration is in the published range" \
    test -n "$(c3_planted_paths "${run}" "${GUARDS_E_DECLARATION}" || true)"

  guards_pipeline "${run}"

  rig_assert_eq "${at}: the control plane STILL resolved B's command" \
    "${honest}" "$(contract_field "${run}" verify)"
  # The refusal is recorded, not scored against an expectation this probe
  # authored. The reason it lands where it does is FIXTURE-SPECIFIC — F2 puts
  # its declaration at the repository root, which SL-001 declares no selector
  # for — and stating that is the point. A project that DID declare its own
  # declaration path would reach leg 3 and beyond, and the invariant that
  # matters here is the clause above, which holds either way.
  rig_assert "${at}: the committed substitution does not reach the trusted side's read" \
    test "$(contract_field "${run}" verify)" != "${GUARDS_E_HOSTILE_VERIFY}"
  assert_outcome "${run}" "${GUARDS_OBSERVED}"
  record_row e light-inrepo decl-committed "${GUARDS_OBSERVED:-no refusal}" \
    "the S-side substitution never reaches the control plane's read either. WHERE it refuses is fixture-specific — F2's declaration sits at the repository root, undeclared by SL-001's selectors — and is recorded, not generalised"
  pipeline_teardown "${run}"
}

# ── argument parsing ────────────────────────────────────────────────────────

self_check_only=0
guards=()
while [ $# -gt 0 ]; do
  case "$1" in
    --positive-control) self_check_only=1 ;;
    -h | --help)
      sed -n '2,9p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) rig_die "unknown flag: $1" ;;
    *)
      case " ${ALL_GUARDS} " in
        *" $1 "*) guards+=("$1") ;;
        *) rig_die "unknown guard: $1 (${ALL_GUARDS})" ;;
      esac
      ;;
  esac
  shift
done
[ "${#guards[@]}" -gt 0 ] || read -r -a guards <<<"${ALL_GUARDS}"

# I6 — FIRST, as a STATEMENT, before any provisioning (F-P01-1).
rig_enter

printf '\nguard probes — each guard OBSERVED refusing at least once (EX-10, EX-11, VA-2, VA-3)\n'

guards_positive_control
if [ "${self_check_only}" -eq 1 ]; then
  rig_assert_done 'probe-guards --positive-control'
  exit 0
fi

GUARDS_C3_RESULTS="${RIG_ROOT}/${GUARDS_C3_RESULTS_REL}"
REPORT="${RIG_ROOT}/probes/guards/results.tsv"

# What the selected guards OWE this run, counted BEFORE anything runs.
# Completeness measured against a number derived up front is the only form that
# can see a leg which never ran at all — counting what was recorded cannot.
guards_expected() {
  local g total=0
  for g in "$@"; do
    case "${g}" in
      a) total=$((total + 2)) ;; # gitlink, gitmodules
      b) total=$((total + 2)) ;; # light, heavy
      c | d) total=$((total + 1)) ;;
      e) total=$((total + 3)) ;; # baseline, worktree, committed
    esac
  done
  printf '%s' "${total}"
}

expected=$(guards_expected "${guards[@]}")

# ── the falsifiability overlay (F-P05-31's middle beat) ─────────────────────
#
# An OPTIONAL file of rebinds, the same affordance `SPIKE_C3_MUTANT` gives P-C3
# and for the same reason: a clause shown to red against a REAL perturbation is
# worth more than one hand-waved against a hypothetical. A mutant WRAPS a named
# seam and calls through — it never owns a copy of the body — so its red is
# evidence about the function this probe actually runs.
#
# LOADED HERE, and the position is load-bearing twice over. It is after every
# definition, so a mutant can see the probe's own seams and not merely the four
# libraries. And it is after `guards_positive_control`, which has therefore
# already run UNMUTATED — a mutant must not be able to quiet the check that
# proves the observables work.
#
# Inert when unset, so a scored run is byte-identical to one without it.
if [ -n "${SPIKE_GUARDS_MUTANT:-}" ]; then
  [ -r "${SPIKE_GUARDS_MUTANT}" ] || rig_die "no such mutant overlay: ${SPIKE_GUARDS_MUTANT}"
  rig_warn "FALSIFY MODE: overlay ${SPIKE_GUARDS_MUTANT} — this run is NOT evidence"
  # shellcheck source=/dev/null
  . "${SPIKE_GUARDS_MUTANT}"
fi

for guard_id in "${guards[@]}"; do "guard_${guard_id}"; done

printf '\n'
rows_assert_complete 'VA-2' "${expected}"

rows_write "${REPORT}" "${GUARDS_COLUMNS}" \
  "$(printf 'guards: %s\tin-jail\tguards=%s%s' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${guards[*]}" \
    "${SPIKE_GUARDS_MUTANT:+$(printf '\tMUTATED=%s' "${SPIKE_GUARDS_MUTANT##*/}")}")"

printf '\nresults: %s\n' "${REPORT}"
printf '%s\n' "${ROWS_RECORDED[@]}" | cut -f1,2,3,4,5 | sed 's/^/  /'

rig_assert_done 'probe-guards'
