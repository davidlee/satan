#!/usr/bin/env bash
# control/selftest.sh — THE RIG'S OWN RED/GREEN (EX-11, VT-4, VA-1/2/3).
#
#   usage: selftest.sh [apparatus|happy|attribution|bundle|falsifiable]
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# `rig selftest` dispatches here the moment this file exists (D-P01-3), and
# until it did, that arm degraded to the I6 guard probe.
#
# ── why this file gates every hostile row (§ 9, R4) ─────────────────────────
#
# Until the happy path lands green, EVERY "refused" is indistinguishable from
# "rig broken". A matrix row scoring `no kill` would then read in the results
# table as a defect of the capsule MODEL, which is R4 in its most damaging
# direction — the finding least likely to be re-examined, because it looks
# like the answer the spike was built to find. So: no hostile row may claim a
# kill before this is green, and the run is RECORDED (VA-1) rather than
# remembered.
#
# Five sections, five different claims:
#
#   apparatus     the rig can INVOKE its own tools, and a tool that cannot be
#                 invoked is a rig defect rather than a capsule refusal —
#                 F-P05-29. Capsule-free, and the precondition of the rest
#   happy         all four stages pass, both mechanisms — VA-1
#   attribution   WHICH stage refused is ASSERTED from the emitted line, never
#                 inferred from an exit code — VA-2
#   bundle        EX-3's four M-B hygiene legs each OBSERVED refusing
#   falsifiable   `assert_outcome`'s object-count clause is shown to RED on a
#                 real wrong admission — VA-3
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=pipeline.sh
. "${RIG_DIR}/control/pipeline.sh"

section=${1:-all}
case "${section}" in
  apparatus | happy | attribution | bundle | falsifiable | all) ;;
  -h | --help)
    sed -n '2,30p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *) rig_die "unknown section: ${section}" ;;
esac

# I6 — FIRST, as a STATEMENT. `guard_not_real_repo` runs at every entry point
# BEFORE any provisioning; inside `$( … )` the refusal would end only the
# substitution's subshell and the self-test would proceed on an empty root
# (F-P01-1).
rig_enter

FIXTURE="${RIG_ROOT}/fixtures/light/repo"
DECLARATION="${RIG_ROOT}/fixtures/light/interpretation-surface.txt"
RESULTS="${RIG_ROOT}/probes/selftest"

[ -d "${FIXTURE}" ] || rig_die "light fixture not built (F1): ${FIXTURE} — run control/fixture-light.sh"
[ -f "${DECLARATION}" ] || rig_die "light declaration missing: ${DECLARATION}"

mkdir -p -- "${RESULTS}"

# One row per observation, so VA-1's "the run is recorded" is a file rather
# than a memory of a terminal (D-P01-5's precedent: a committed re-runnable
# script and a written result beat a session transcript).
record() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${RESULTS}/results.tsv"
}

# Run one scenario to completion. PUBLISHES `SCENARIO_RUN`; prints nothing.
#
# Two F-P01-1-shaped hazards this shape exists to avoid, both of which would
# have made a refusal look like a result:
#
#   * it calls `pipeline_setup`, which calls `guard_not_real_repo`, which
#     refuses by `exit`. Returning the run dir on stdout would force every
#     caller into `$( … )`, where that exit ends only the subshell.
#   * `pipeline_run` is REDIRECTED, never piped — a pipe subshells it, so a
#     RIG DEFECT return could not reach this shell either.
scenario() {
  local label=$1 declaration=$2 stub=$3
  local rc=0
  pipeline_setup "${label}" "${FIXTURE}" "${declaration}" 001 "${stub}"
  SCENARIO_RUN="${PIPELINE_RUN}"
  pipeline_capsule "${SCENARIO_RUN}"
  pipeline_run "${SCENARIO_RUN}" "${MECHANISM:-fetch}" >"${SCENARIO_RUN}/stages" || rc=$?
  if [ "${rc}" -eq "${RIG_EXIT_DEFECT}" ]; then
    rig_warn "${label}: RIG DEFECT — not a result"
    exit "${RIG_EXIT_DEFECT}"
  fi
}

# A declaration is the control plane's own copy, so a scenario that needs a
# different `verify:` writes one rather than reaching into the fixture. This is
# also the provenance invariant exercised: the command comes from B's side of
# the boundary, never from the harvested result (F-5, EX-7).
declaration_with_verify() {
  local dest=$1 cmd=$2
  sed "s|^verify:.*|verify:    ${cmd}|" "${DECLARATION}" >"${dest}"
}

# ── apparatus: the instruments answer before anything they say is believed ──
#
# One rung BELOW A-1. A-1 says the happy path must be green before a hostile row
# may claim a kill; this says the rig must be shown able to INVOKE ITS OWN TOOLS
# before the happy path's green means anything at all.
#
# F-P05-29 is the case for it, and it cost a 75-minute scored run. A co-agent
# rebuilt the shared `target/debug/doctrine` against a nix store this jail does
# not mount, so every invocation exited 127 — and conform leg 2, which mapped any
# nonzero exit to `undeclared-path` with stderr discarded, reported the rig's own
# broken toolchain as A REFUSAL BY THE CAPSULE. 32 hostile-row failures, all of
# them one missing ELF interpreter. This section is capsule-free and runs FIRST.

selftest_apparatus() {
  printf '\napparatus — the rig can invoke its own tools (A-1'"'"'s own precondition, F-P05-29)\n'

  local bin fake fallback out rc=0

  # 1. THE LIVE CLAIM about this environment, not about the code: whatever the
  #    ladder just picked must actually run HERE.
  bin=$(rig_doctrine_bin)
  rig_assert "the doctrine binary conform leg 2 will call RUNS: ${bin}" \
    "${bin}" --version

  # 2. `[ -x ]` IS NOT RUNNABILITY, and that gap is the whole finding. A file
  #    with the executable bit and an absent interpreter is exactly the shape
  #    the clobbered dev build had.
  fake="${RESULTS}/unrunnable-doctrine"
  printf '#!/nonexistent/interpreter\n' >"${fake}"
  chmod +x -- "${fake}"
  rig_assert 'the fake carries the executable bit — [ -x ] would have believed it' \
    test -x "${fake}"
  rig_assert_fails 'and it cannot be invoked — exit 127, the F-P05-29 shape' \
    "${fake}" --version

  fallback=$(DOCTRINE_BIN="${fake}" rig_doctrine_bin)
  rig_assert 'the ladder REFUSES an unrunnable DOCTRINE_BIN rather than returning it' \
    test "${fallback}" != "${fake}"
  rig_assert 'and the rung it falls through to RUNS' "${fallback}" --version

  # 3. CONFORM LEG 2 DISTINGUISHES "the verb refused" FROM "the verb could not
  #    run". Negative control first, or the red below would prove only that the
  #    call is broken in general: through the real ladder, the same range must
  #    still yield a real refusal TOKEN.
  rig_assert_eq 'negative control: leg 2 still reports a real refusal token' \
    'undeclared-path' \
    "$(conform_stage "${FIXTURE}" 6bd9833 6caba12 001 || true)"

  # Then with no runnable doctrine anywhere on the ladder. The override is the
  # honest simulation of that: `rig_doctrine_bin` having exhausted every rung.
  out=$(
    # shellcheck disable=SC2329  # invoked indirectly, by conform_stage below
    rig_doctrine_bin() { printf '%s' "${fake}"; }
    conform_stage "${FIXTURE}" 6bd9833 6caba12 001
  ) || rc=$?
  rig_assert_eq 'a doctrine binary that cannot be INVOKED is a RIG DEFECT, not a refusal' \
    "${RIG_EXIT_DEFECT}" "${rc}"
  rig_assert_eq 'and it names no token — the capsule is not blamed for the rig' \
    '' "${out}"

  rm -f -- "${fake}"
  record - apparatus pass 'the ladder proves runnability; leg 2 separates a refusal from a failure to invoke'
}

# ── happy: all four stages, both mechanisms (EX-11, VA-1) ───────────────────

selftest_happy() {
  printf '\nhappy path — EX-11, the precondition of every hostile row (VA-1)\n'

  local mech run stages
  for mech in fetch bundle; do
    MECHANISM="${mech}" scenario "selftest-happy-${mech}" "${DECLARATION}" src/capsule-stub.ts
    run="${SCENARIO_RUN}"
    stages="${run}/stages"

    # Every stage ASSERTED to have passed, by name. Asserting only the final
    # status would score a run that skipped a stage entirely as green — the
    # same adjacent-observable move as F-P02-1/2.
    local stage
    for stage in harvest conform verify advance; do
      rig_assert "${mech}: stage ${stage} PASSED" \
        grep -qx "stage=${stage} verdict=pass token=" "${stages}"
    done

    rig_assert_eq "${mech}: no refusal at all" '' "$(pipeline_first_refusal "${stages}")"
    assert_outcome "${run}" ''
    record "${mech}" happy pass "four stages, one canonical ref advanced"
    pipeline_teardown "${run}"
  done
}

# ── attribution: WHICH stage refused, asserted (VA-2) ───────────────────────

selftest_attribution() {
  printf '\nattribution — VA-2: the refusing stage is ASSERTED, not inferred\n'

  # § 9 wants the kill boundary tested DIRECTLY. The pass/partial distinction
  # in the matrix depends on knowing which stage refused, and an exit code
  # cannot say — every refusal exits 1. This is the direct descendant of
  # F-P02-2, where "the runner refused" and "the runner never ran" read
  # identically until they were given distinguishable statuses.
  #
  # Four scenarios across THREE stages. One stage would not discriminate: an
  # assertion that the emitted line says `conform` when conform is the only
  # thing that ever refuses proves nothing about attribution.
  local run stages decl

  # conform — the stub writes OUTSIDE the slice's `src/**` selectors.
  scenario selftest-conform "${DECLARATION}" docs/stub.md
  run="${SCENARIO_RUN}"
  stages="${run}/stages"
  rig_assert_eq 'conform: the FIRST refusing stage is conform/undeclared-path' \
    'conform/undeclared-path' "$(pipeline_first_refusal "${stages}")"
  rig_assert 'conform: harvest is recorded PASSED before it' \
    grep -qx 'stage=harvest verdict=pass token=' "${stages}"
  rig_assert 'conform: no later stage emitted anything (the run stops at the first refusal)' \
    test 2 -eq "$(wc -l <"${stages}")"
  assert_outcome "${run}" 'conform/undeclared-path'
  record fetch attribution pass 'conform/undeclared-path, harvest passed before it'
  pipeline_teardown "${run}"

  # verify / suite-failed — a verify command that fails. The command is read
  # from the control plane's own declaration copy, never from the result.
  decl="${RIG_ROOT}/probes/selftest/decl-fail.txt"
  declaration_with_verify "${decl}" 'node -e "process.exit(1)"'
  scenario selftest-suite "${decl}" src/capsule-stub.ts
  run="${SCENARIO_RUN}"
  rig_assert_eq 'verify: a failing suite is verify/suite-failed' \
    'verify/suite-failed' "$(pipeline_first_refusal "${run}/stages")"
  rig_assert 'verify: conform is recorded PASSED before it' \
    grep -qx 'stage=conform verdict=pass token=' "${run}/stages"
  assert_outcome "${run}" 'verify/suite-failed'
  record fetch attribution pass 'verify/suite-failed'
  pipeline_teardown "${run}"

  # verify / verify-timeout — the wall-clock bound, and the one place the
  # PHASE-02 status → PHASE-03 token mapping is actually observed end to end.
  # PHASE-02 proved the bound BITES; this proves it acquires the right token
  # (D-P02-4, I5 — the capsule never authors it).
  decl="${RIG_ROOT}/probes/selftest/decl-hang.txt"
  declaration_with_verify "${decl}" 'sleep 600'
  PIPELINE_VERIFY_TIMEOUT=3 scenario selftest-timeout "${decl}" src/capsule-stub.ts
  run="${SCENARIO_RUN}"
  rig_assert_eq 'verify: a hung suite is verify/verify-timeout, NOT suite-failed' \
    'verify/verify-timeout' "$(pipeline_first_refusal "${run}/stages")"
  assert_outcome "${run}" 'verify/verify-timeout'
  record fetch attribution pass 'verify/verify-timeout — the PHASE-02 status mapped to its token'
  pipeline_teardown "${run}"

  # advance / stale-base — the trunk moves after the capsule was provisioned.
  # Refuses at the PRECONDITION, having transferred nothing, so it keeps the
  # FULL assert_outcome clause including the object count (F-14).
  pipeline_setup selftest-stale "${FIXTURE}" "${DECLARATION}" 001 src/capsule-stub.ts
  run="${PIPELINE_RUN}"
  pipeline_capsule "${run}"
  git -C "${run}/canonical" commit --allow-empty --quiet -m '[add] trunk moved under us'
  # Re-snapshot: the trunk move is SCENARIO STATE, not a pipeline effect.
  # Without this the case reds on its own setup and looks like the assertion
  # working.
  pipeline_snapshot "${run}"
  pipeline_run "${run}" fetch >"${run}/stages" || true
  rig_assert_eq 'advance: a moved trunk is advance/stale-base' \
    'advance/stale-base' "$(pipeline_first_refusal "${run}/stages")"
  rig_assert 'advance: verify is recorded PASSED before it' \
    grep -qx 'stage=verify verdict=pass token=' "${run}/stages"
  # THE STRICT CLAUSE, on the row where it does the most work. stale-base
  # refuses before transferring, so the object count must be untouched — this
  # is what would red if stage 4's ordering were inverted (R-c, F-14).
  assert_outcome "${run}" 'advance/stale-base'
  record fetch attribution pass 'advance/stale-base — nothing transferred, strict clause holds'
  pipeline_teardown "${run}"
}

# ── bundle hygiene: EX-3's four legs OBSERVED refusing (RT-4/F-6) ──────────
#
# The bundle is the ONE capsule-authored artifact this design does not delete,
# so it carries a trusted-side file-ingestion boundary M-A does not have — a
# QUE-200 verdict input in its own right. Four legs are specified; a leg that
# has never been seen to refuse is not known to work, and these are absence-
# shaped, which is the class that passes when its subject was never reachable.

# bundle_case <label> <expected-token> <mutator> — mutator receives the path.
bundle_case() {
  local label=$1 expect=$2 mutator=$3 run
  pipeline_setup "${label}" "${FIXTURE}" "${DECLARATION}" 001 src/capsule-stub.ts
  run="${PIPELINE_RUN}"
  pipeline_capsule "${run}"
  "${mutator}" "${run}/capsule/${RIG_BUNDLE}"
  pipeline_run "${run}" bundle >"${run}/stages" || true
  rig_assert_eq "${label}: harvest/${expect}" \
    "harvest/${expect}" "$(pipeline_first_refusal "${run}/stages")"
  assert_outcome "${run}" "harvest/${expect}"
  record bundle hygiene pass "${expect}"
  pipeline_teardown "${run}"
}

# The four mutators live in `lib/common.sh` — H13 attacks the same artifact at
# the same path, and one copy is what keeps the two from drifting apart.

selftest_bundle() {
  printf '\nbundle hygiene — EX-3, all four legs OBSERVED refusing (RT-4/F-6)\n'

  # POSITIVE CONTROL FIRST. Four "it refused" assertions pass vacuously if the
  # bundle path is wrong and every run refuses; an untouched bundle must be
  # ingested for any of the refusals below to mean anything.
  local run
  pipeline_setup selftest-bundle-ok "${FIXTURE}" "${DECLARATION}" 001 src/capsule-stub.ts
  run="${PIPELINE_RUN}"
  pipeline_capsule "${run}"
  bundle_leave "${run}/capsule/${RIG_BUNDLE}"
  pipeline_run "${run}" bundle >"${run}/stages" || true
  rig_assert 'positive control: an UNTOUCHED bundle is ingested' \
    grep -qx 'stage=harvest verdict=pass token=' "${run}/stages"
  pipeline_teardown "${run}"

  bundle_case selftest-bundle-symlink bundle-unsafe-path bundle_symlink
  bundle_case selftest-bundle-absent bundle-absent bundle_remove
  bundle_case selftest-bundle-invalid bundle-invalid bundle_truncate

  # The size cap is a THRESHOLD, not a mutation — capped below the real
  # bundle's size so the leg bites on an honest artifact. It must refuse
  # BEFORE `git bundle verify` reads a byte: a cap applied after the read is
  # not a cap, and the whole point is that a hostile 2 GiB file is never
  # streamed at all.
  pipeline_setup selftest-bundle-cap "${FIXTURE}" "${DECLARATION}" 001 src/capsule-stub.ts
  run="${PIPELINE_RUN}"
  pipeline_capsule "${run}"
  RIG_BUNDLE_CAP=64 pipeline_run "${run}" bundle >"${run}/stages" || true
  rig_assert_eq 'size cap: an oversized bundle is harvest/resource-cap' \
    'harvest/resource-cap' "$(pipeline_first_refusal "${run}/stages")"
  assert_outcome "${run}" 'harvest/resource-cap'
  record bundle hygiene pass resource-cap
  pipeline_teardown "${run}"
}

# ── falsifiable: the object-count clause REDS on a wrong admission (VA-3) ───

# Returns 0 when `assert_outcome` FAILED. The counter is reset inside a
# subshell so a deliberate red does not poison the real tally, and the caller
# sees a plain success/failure it can assert on.
outcome_reds() {
  local run=$1 refusal=$2
  ! (
    RIG_ASSERT_FAILURES=0
    assert_outcome "${run}" "${refusal}" >/dev/null 2>&1
    [ "${RIG_ASSERT_FAILURES}" -eq 0 ]
  )
}

selftest_falsifiable() {
  printf '\nfalsifiable — VA-3: the object-count clause is shown to RED\n'

  # A WRONG ADMISSION, not a payload refusal. The weak form of this evidence
  # would be an assertion that fails because nothing is wired yet; that proves
  # the assertion runs, not that it guards anything. So: land the whole
  # pipeline, then deliberately restore the DELETED SECOND HOP (F-3) — the
  # thing probe-specs described and this design removed — and watch the clause
  # catch it (mem.pattern.tdd.wire-before-guard).
  #
  # The hop writes FETCH_HEAD and creates NO ref, so canonical's refs are
  # untouched and only its object count moves. That is the sharp version: the
  # object-count clause is seen catching something NO OTHER CLAUSE CAN SEE,
  # which is precisely EX-10's claim for it and precisely what a hostile 2 GiB
  # blob does on its way to a refusal.
  local clean defect

  # NEGATIVE CONTROL FIRST. The same scenario without the defect must be green,
  # or a red below proves only that the scenario is broken.
  scenario selftest-clean "${DECLARATION}" docs/stub.md
  clean="${SCENARIO_RUN}"
  rig_assert 'negative control: without the defect, assert_outcome HOLDS' \
    outcome_holds "${clean}" 'conform/undeclared-path'
  rig_assert_eq 'negative control: canonical object count is unchanged' \
    "$(cat "${clean}/canonical-objects.before")" \
    "$(canonical_objects "${clean}/canonical")"
  pipeline_teardown "${clean}"

  # THE WRONG ADMISSION.
  RIG_DEFECT_CANONICAL_HOP=1 scenario selftest-defect "${DECLARATION}" docs/stub.md
  defect="${SCENARIO_RUN}"
  rig_assert_eq 'defect run: still refuses at the same stage' \
    'conform/undeclared-path' "$(pipeline_first_refusal "${defect}/stages")"
  # The refs clause CANNOT see this. Asserted, so the demonstration cannot be
  # confused with "some clause noticed".
  rig_assert_eq 'defect run: canonical REFS are unchanged — the refs clause is blind to it' \
    "$(cat "${defect}/canonical-refs.before")" \
    "$(canonical_refs "${defect}/canonical")"
  rig_assert 'defect run: canonical object count GREW — hostile objects landed pre-refusal' \
    test "$(canonical_objects "${defect}/canonical")" -gt "$(cat "${defect}/canonical-objects.before")"
  rig_assert 'VA-3: assert_outcome REDS on the canonical-writing harvest' \
    outcome_reds "${defect}" 'conform/undeclared-path'
  record fetch falsifiable pass 'object-count clause red on the restored second hop; refs clause blind'
  pipeline_teardown "${defect}"
}

# The inverse of `outcome_reds`, for the negative control. Written out rather
# than spelled `! outcome_reds` at the call site: under `"$@"` a leading `!`
# arrives as the COMMAND NAME and the assertion reds on its own invocation
# (F-P02-3) — the mistake that cost PHASE-02 a round on a mechanism that was
# correct throughout.
outcome_holds() {
  local run=$1 refusal=$2
  (
    RIG_ASSERT_FAILURES=0
    assert_outcome "${run}" "${refusal}" >/dev/null 2>&1
    [ "${RIG_ASSERT_FAILURES}" -eq 0 ]
  )
}

printf 'selftest: %s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${section}" >>"${RESULTS}/results.tsv"

case "${section}" in
  apparatus) selftest_apparatus ;;
  happy) selftest_happy ;;
  attribution) selftest_attribution ;;
  bundle) selftest_bundle ;;
  falsifiable) selftest_falsifiable ;;
  all)
    selftest_apparatus
    selftest_happy
    selftest_attribution
    selftest_bundle
    selftest_falsifiable
    ;;
esac

rig_assert_done "selftest (${section})"
