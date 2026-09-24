#!/usr/bin/env bash
# control/pipeline.sh — the closed FOUR-stage pipeline (EX-1..EX-10, VT-1).
#
#   sourced:   . control/pipeline.sh
#                → pipeline_setup / pipeline_capsule / pipeline_run
#                  assert_outcome / pipeline_first_refusal / pipeline_teardown
#   executed:  pipeline.sh <label> <fixture> <declaration> <fetch|bundle>
#
# There are FOUR stages and the set is CLOSED. Provisioning is capsule-side and
# cannot refuse a *result*, so it is not a stage.
#
#   1 harvest   capsule → QUARANTINE, fsck, caps, pin the OID
#   2 conform   ancestry · declared scope · forbidden paths · tree mode
#   3 verify    verify capsule at the pinned OID; the verdict is its exit status
#   4 advance   precondition → transfer → ONE compare-and-swap, or refuse
#
# ── three repositories, and only one of them is canonical ────────────────────
#
# Stage 4 is the FIRST AND ONLY touch of the canonical repository (F-3).
# Stages 1–3 run entirely against a per-run quarantine that is `rm -rf`'d
# afterwards, so a refused row leaves the canonical object database unchanged
# IN SIZE — which is the observable DQ-3 wants and `assert_outcome` asserts.
#
#   canonical/    per-run disposable clone of the fixture (D-P03-1). The
#                 fixture itself is a TEMPLATE: stage 4 advances a ref, and
#                 `assert_outcome` needs a subject it may mutate, which the
#                 pristine base fixture PHASE-05 also reads is not.
#   quarantine/   per-run clone of canonical (D-P03-2), `fetch.fsckObjects`.
#                 Cloned rather than `init`'d empty because it must satisfy two
#                 things at once: hold S's objects for the conform legs, AND
#                 give `slice conformance -p` a `.doctrine/` registry to read.
#                 Its worktree sits at B — the control-plane-pinned base, which
#                 is NOT the candidate, so I4's "no candidate tree materialised
#                 trusted-side" holds. Every leg below is plumbing over B..S.
#   capsule/      the worker's rw root. Never read for a verdict.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

SANDBOX="${RIG_DIR}/capsule/sandbox.sh"
HARVEST_FETCH="${RIG_DIR}/control/harvest-fetch.sh"
HARVEST_BUNDLE="${RIG_DIR}/control/harvest-bundle.sh"

PIPELINE_VERIFY_TIMEOUT="${PIPELINE_VERIFY_TIMEOUT:-300}"
# The VERIFY capsule's disk bound, deliberately NOT `SPIKE_SANDBOX_DISK_CAP`.
# That default also bounds the WORKER capsule, where it is doing real work —
# the heavy worker sits at 195M against 256 MiB (F-P05-10) and H7 plants against
# exactly that headroom. Widening one must not widen the other, so the verify
# side gets its own name and is passed explicitly (STD-001). Both are per-fixture
# (D-P05-7): light's build fits the default, a Rust workspace's does not.
PIPELINE_VERIFY_DISK_CAP="${PIPELINE_VERIFY_DISK_CAP:-$((256 * 1024 * 1024))}"

# The WORKER capsule's VEHICLE and DISK BOUND — the two things a row whose
# hazard is produced INSIDE the capsule has to be able to state (F-P05-37).
#
# Every other row plants trusted-side between `pipeline_capsule` and
# `pipeline_run`, which is why those are two calls. A row tripping the sandbox's
# own disk cap cannot use that seam: `sandbox.sh` evaluates the bound before
# control ever returns here. So the terms travel as PARAMETERS, set per cell by
# the harness from a row lookup (D-P05-19) — declaratively, never as a hook.
#
# BOTH ARE EMPTY-MEANS-DEFAULT, and the default is resolved AT THE CALL SITE,
# never here. That is not a style choice: the harness assigns these per cell, so
# a `:-` resolved once at source time would be overwritten by the first cell and
# the fifteen already-scored rows would run with an EMPTY vehicle. A default has
# to stay inert in its consumer to survive a caller that sets the variable.
#
# The cap's empty likewise means "pass no `--disk-cap` at all", so `sandbox.sh`
# goes on owning that number — a literal here would be a second copy of it
# (STD-001), which is H13's `unset RIG_BUNDLE_CAP` reason one bound over.
PIPELINE_WORKER_VEHICLE_DEFAULT='/rig/worker-stub.sh'
PIPELINE_WORKER_VEHICLE="${PIPELINE_WORKER_VEHICLE:-}"
PIPELINE_WORKER_DISK_CAP="${PIPELINE_WORKER_DISK_CAP:-}"

PIPELINE_DOORBELL_DEADLINE="${PIPELINE_DOORBELL_DEADLINE:-120}"
PIPELINE_DOORBELL_INTERVAL="${PIPELINE_DOORBELL_INTERVAL:-1}"

# ── the CLOSED refusal-token vocabulary (design § 5.1) ───────────────────────
#
# A token observed outside this set is a RIG DEFECT, not a result — which is
# why `stage_emit` refuses to print one rather than trusting the caller. The
# set is closed but NOT fully exercised, and the difference is recorded rather
# than papered over: `cas-lost` is legal and owned by NO row (producing it
# means racing the accepted ref between stage 4's precondition read and its
# CAS, which probes the rig's own scheduling rather than a hostile capsule).
# Reachable-but-unexercised is a weaker and more accurate claim than "the rig
# cannot produce it" — an unexercised path stated as impossible is how a gap
# stops being looked at.
RIG_TOKENS_HARVEST='fsck-failed oid-mismatch resource-cap bundle-invalid bundle-absent bundle-unsafe-path'
RIG_TOKENS_CONFORM='ancestry-not-descendant ancestry-merge-commit undeclared-path forbidden-path gitlink gitmodules'
RIG_TOKENS_VERIFY='suite-failed verify-timeout sandbox-failed resource-cap'
RIG_TOKENS_ADVANCE='stale-base cas-lost'

token_legal() {
  local stage=$1 token=$2 set_
  case "${stage}" in
    harvest) set_="${RIG_TOKENS_HARVEST}" ;;
    conform) set_="${RIG_TOKENS_CONFORM}" ;;
    verify) set_="${RIG_TOKENS_VERIFY}" ;;
    advance) set_="${RIG_TOKENS_ADVANCE}" ;;
    *) return 1 ;;
  esac
  case " ${set_} " in
    *" ${token} "*) return 0 ;;
  esac
  return 1
}

# Every stage emits `stage=<name> verdict=pass|refuse token=<t>` (EX-9), and
# the runner records the FIRST refusing stage. Emission is ASSERTED downstream,
# never inferred from an exit code (VA-2): the pass/partial distinction in the
# matrix requires knowing WHICH stage refused, and an exit code cannot say.
stage_emit() {
  local stage=$1 verdict=$2 token=${3:-}
  if [ "${verdict}" = refuse ] && ! token_legal "${stage}" "${token}"; then
    rig_warn "RIG DEFECT: ${stage}/${token} is outside the closed vocabulary"
    exit "${RIG_EXIT_DEFECT}"
  fi
  printf 'stage=%s verdict=%s token=%s\n' "${stage}" "${verdict}" "${token}"
}

# ── canonical snapshots — what `assert_outcome` compares ────────────────────

canonical_refs() {
  git -C "$1" for-each-ref --format='%(objectname) %(refname)' | sort
}

# Loose PLUS packed. The object COUNT is what makes I1 falsifiable rather than
# decorative: it is precisely the thing a quarantine *namespace inside
# canonical* would have broken, on every refused row.
canonical_objects() {
  git -C "$1" count-objects -v |
    awk '/^count:/ { c = $2 } /^in-pack:/ { p = $2 } END { print c + p }'
}

# quiesce_clone <repo>
#
# A freshly provisioned clone must change ONLY when the pipeline changes it.
# Two inheritances break that, and both are invisible until something reds
# (F-P05-28):
#
#   1. A local clone copies `objects/` WHOLESALE, so it inherits the source's
#      COMMIT-GRAPH — a derived cache. The clone keeps a narrower ref set than
#      the source (the heavy fixture keeps `refs/heads` + `refs/tags` only), so
#      commits the graph names arrive UNREACHABLE. They survive as `dangling`
#      and fsck is content — until something prunes them, at which point the
#      graph names a commit that is gone and `git fsck` exits 16. The harvester
#      fscks the whole quarantine, so that lands as `harvest/fsck-failed`,
#      attributed to the capsule. A derived cache carried across a clone
#      boundary is stale by construction; a probe has no business inheriting it.
#
#   2. Git's own AUTO-MAINTENANCE is what does the pruning, triggered by the
#      harvest fetch inside the run. It also repacks — and `canonical_objects`
#      counts objects, so background housekeeping can move the very number I1's
#      falsifiability rests on. A measurement whose subject is being tidied up
#      underneath it is not a measurement.
#
# Both are disabled rather than tolerated. This is rig hygiene, not a claim
# about the capsule model: nothing here changes what a stage may do.
quiesce_clone() {
  local repo=$1
  rm -rf -- "${repo}/.git/objects/info/commit-graph" \
    "${repo}/.git/objects/info/commit-graphs"
  git -C "${repo}" config core.commitGraph false
  git -C "${repo}" config fetch.writeCommitGraph false
  git -C "${repo}" config gc.auto 0
  git -C "${repo}" config maintenance.auto false
}

# ── setup / teardown ─────────────────────────────────────────────────────────

# pipeline_setup <label> <fixture-repo> <declaration> [slice-id] [stub-path]
#
# PUBLISHES `PIPELINE_RUN` rather than printing it, and that is load-bearing —
# the same reason `rig_enter` publishes RIG_ROOT (F-P01-1). This function calls
# `guard_not_real_repo`, which refuses by `exit`; if the caller had to wrap it
# in `$( … )` to read the run dir, that exit would end only the substitution's
# subshell and setup would carry on against a root the guard had just refused.
# A guard whose refusal cannot reach the entry point is not a guard.
pipeline_setup() {
  local label=$1 fixture=$2 declaration=$3 slice=${4:-001} stub=${5:-src/capsule-stub.ts}
  local run="${RIG_ROOT}/runs/${label}"

  guard_not_real_repo "${run}"
  rm -rf -- "${run}"
  mkdir -p -- "${run}/capsule"

  # `--no-hardlinks` throughout, and not as an optimisation knob: a local clone
  # hardlinks object files by default, so a hostile capsule corrupting a shared
  # object would corrupt the thing it was cloned from. It is the difference
  # between a copy and an alias.
  git clone --no-hardlinks --quiet -- "${fixture}" "${run}/canonical"
  quiesce_clone "${run}/canonical"

  # The accepted ref is READ FROM THE FIXTURE, never hardcoded. The light
  # fixture's trunk is `mainline` precisely so that anything assuming `main`
  # breaks loudly (D5) — a pipeline that hardcoded it would pass here for a
  # reason that says nothing about portability.
  local accepted base
  accepted=$(git -C "${run}/canonical" symbolic-ref HEAD)
  base=$(git -C "${run}/canonical" rev-parse --verify "${accepted}")

  pipeline_quarantine "${run}/canonical" "${run}/quarantine"

  # The declaration, pinned control-plane-side as a SIBLING of canonical. This
  # is "read from B" in F-5's sense — the content the control plane itself
  # pinned, never anything the capsule can reach. PHASE-05's F2 variant
  # manufactures the in-repo exposure; when it does, this read becomes
  # `git show <B>:<path>` and must NEVER become `<S>:<path>`.
  cp -- "${declaration}" "${run}/interpretation-surface.txt"

  # The work contract (design § 5.2). Plain key=value — rig scaffolding, not a
  # doctrine entity; it is read by shell and by nothing else.
  {
    printf 'base=%s\n' "${base}"
    printf 'slice=%s\n' "${slice}"
    printf 'label=%s\n' "${label}"
    printf 'mode=%s\n' fresh
    printf 'accepted=%s\n' "${accepted}"
    # Recorded in the contract because it is a JOIN with the slice's selectors,
    # not a worker detail: the happy path needs it DECLARED, and a run whose
    # stub path drifted out of scope would refuse at conform leg 2 for a reason
    # about the rig rather than about the model.
    printf 'stub=%s\n' "${stub}"
    printf 'verify=%s\n' "$(declaration_field "${run}/interpretation-surface.txt" verify)"
  } >"${run}/contract"

  pipeline_snapshot "${run}"

  PIPELINE_RUN="${run}"
}

# pipeline_quarantine <source> <dest> — WHAT A QUARANTINE IS, in one place.
#
# A clone of canonical, quiesced, with `fetch.fsckObjects` on: the fsck setting
# is the half that is easy to leave out, and a quarantine without it ingests
# unchecked objects while still looking like a quarantine. Extracted because
# P-C3's H14 builds a second one to re-harvest into (I2), and a hand-rolled copy
# there would be a quarantine that differs from the one every stage ran against
# — the difference being invisible until it mattered.
pipeline_quarantine() {
  local source=$1 dest=$2
  git clone --no-hardlinks --quiet -- "${source}" "${dest}"
  quiesce_clone "${dest}"
  git -C "${dest}" config fetch.fsckObjects true
}

# pipeline_harvester <fetch|bundle> — the mechanism → harvester mapping, named
# once. `pipeline_run` and H14's second harvest both need it, and two copies
# would be two places for the matrix's mechanism column to stop meaning the
# same thing in each.
#
# PUBLISHES `PIPELINE_HARVESTER` rather than printing it, for the reason
# `cell_pipeline_leg` publishes `CELL_OBSERVED` (F-P01-1): a caller forced into
# `$( … )` to read the path would swallow the `rig_die` below in the
# substitution's subshell and go on to invoke an empty command.
pipeline_harvester() {
  case "$1" in
    fetch) PIPELINE_HARVESTER="${HARVEST_FETCH}" ;;
    bundle) PIPELINE_HARVESTER="${HARVEST_BUNDLE}" ;;
    *) rig_die "unknown harvest mechanism: $1 (fetch|bundle)" ;;
  esac
}

# The pre-run canonical snapshot — what `assert_outcome` compares against.
#
# Re-callable on purpose. A scenario that deliberately moves the trunk before
# the pipeline runs (the `advance/stale-base` case) is establishing SCENARIO
# STATE, not producing a pipeline effect; re-snapshotting after it is what
# keeps the assertion answering "did the PIPELINE change canonical" rather
# than "did anything at all". Without this the stale-base case would red on
# its own setup and look like the assertion working.
pipeline_snapshot() {
  local run=$1
  canonical_refs "${run}/canonical" >"${run}/canonical-refs.before"
  canonical_objects "${run}/canonical" >"${run}/canonical-objects.before"
}

pipeline_teardown() {
  local run=$1
  guard_not_real_repo "${run}"
  rm -rf -- "${run}"
}

contract_field() { rig_field "$1/contract" "$2"; }

# ── the capsule phase (NOT a stage) ─────────────────────────────────────────
#
# Provision and run the worker. Separate from `pipeline_run` on purpose: the
# P-C3 harness mutates between the two (`Hnn.mutate` → `Hnn.planted?` → the
# pipeline), and folding them together would leave no seam to plant into.
pipeline_capsule() {
  local run=$1
  local capsule="${run}/capsule" base stub status=0
  base=$(contract_field "${run}" base)
  stub=$(contract_field "${run}" stub)

  "${SANDBOX}" --capsule "${capsule}" --source "${run}/canonical" \
    -- /rig/provision.sh "${base}" >/dev/null 2>&1 ||
    rig_die "provisioning failed for ${capsule}"

  # The worker's status is DATA, not an error here. A worker that hit the disk
  # cap must flow into a stage-1 refusal carrying `harvest/resource-cap` — dying
  # on it would lose the very outcome the bound exists to produce.
  #
  # The bound is passed only when a row asked for one, so an unset cap is a
  # sandbox-defaulted run byte-for-byte and not a run capped at a number this
  # file restated. Bash 5 expands an empty array under `set -u` cleanly.
  local worker_bound=()
  [ -n "${PIPELINE_WORKER_DISK_CAP}" ] &&
    worker_bound=(--disk-cap "${PIPELINE_WORKER_DISK_CAP}")

  "${SANDBOX}" --capsule "${capsule}" "${worker_bound[@]}" \
    -- "${PIPELINE_WORKER_VEHICLE:-${PIPELINE_WORKER_VEHICLE_DEFAULT}}" \
    "${stub}" >/dev/null 2>&1 || status=$?
  printf '%s\n' "${status}" >"${run}/worker-status"

  # The doorbell is a HINT TO LOOK, never a statement of what to look at. Loss
  # degrades to polling with a wall-clock deadline, so a lost ring costs
  # latency and not correctness.
  rig_wait_doorbell "${capsule}" "${PIPELINE_DOORBELL_DEADLINE}" \
    "${PIPELINE_DOORBELL_INTERVAL}" >/dev/null || true
}

# ── the four stages ─────────────────────────────────────────────────────────

# pipeline_run <run> <fetch|bundle>
#
# Emits one `stage=…` line per stage on stdout and stops at the FIRST refusal.
# Returns 0 if all four passed, 1 on any refusal.
pipeline_run() {
  local run=$1 mechanism=$2
  local canonical="${run}/canonical" quarantine="${run}/quarantine"
  local capsule="${run}/capsule"
  local base slice accepted verify_cmd oid token status

  base=$(contract_field "${run}" base)
  slice=$(contract_field "${run}" slice)
  accepted=$(contract_field "${run}" accepted)
  verify_cmd=$(contract_field "${run}" verify)

  # ── stage 1: harvest ──────────────────────────────────────────────────────
  local harvester
  pipeline_harvester "${mechanism}"
  harvester="${PIPELINE_HARVESTER}"

  # ONE SIGNATURE for both mechanisms (EX-1), so this call does not branch.
  # The worker capsule's own bound, folded in trusted-side (I5, D-P02-4).
  # PHASE-02 emits distinguishable STATUSES and no tokens deliberately; this is
  # the SINGLE place they become tokens. Re-deriving the mapping anywhere else
  # would read as a pipeline bug rather than as the mapping drift it is.
  # Checked BEFORE harvest: a capsule that blew the disk cap has nothing worth
  # ingesting, and streaming it first would be the cap arriving too late.
  if [ "$(cat "${run}/worker-status" 2>/dev/null || echo 0)" = "${RIG_EXIT_DISK}" ]; then
    stage_emit harvest refuse resource-cap
    return 1
  fi

  status=0
  oid=$("${harvester}" "${capsule}" "${quarantine}" 2>"${run}/harvest.err") || status=$?
  if [ "${status}" -ne 0 ]; then
    if [ "${status}" -eq "${RIG_EXIT_DEFECT}" ]; then
      # The harvester is a separate PROCESS, so its defect status propagates
      # here honestly. Re-raised as a return, never an `exit`: `pipeline_run`
      # must stay usable from a caller that redirects it (F-P01-1).
      rig_warn 'RIG DEFECT raised by the harvester — see above'
      return "${RIG_EXIT_DEFECT}"
    fi
    token=$(sed -n 's/^token=//p' "${run}/harvest.err" | head -1)
    stage_emit harvest refuse "${token}"
    return 1
  fi

  # THE DELETED SECOND HOP (F-3), reachable ONLY as a deliberate defect for
  # VA-3. Fetching into canonical here is what probe-specs described and what
  # this design removes: it puts hostile objects in the canonical database
  # BEFORE the refusal meant to stop them. Wired as an opt-in so the
  # object-count clause can be shown to RED against a real wrong admission
  # rather than a hand-waved one.
  if [ "${RIG_DEFECT_CANONICAL_HOP:-0}" = 1 ]; then
    rig_warn 'DEFECT MODE: performing the deleted second hop into canonical (VA-3)'
    # NO destination refspec, so this writes FETCH_HEAD and creates no ref. That
    # is deliberate and it is what makes the demonstration sharp: canonical's
    # REFS are untouched, so the refs clause still passes and ONLY the object
    # count moves. The object-count clause is therefore shown catching something
    # no other clause can see — which is exactly the claim EX-10 makes for it,
    # and exactly what a hostile 2 GiB blob would do on its way to a refusal.
    git -C "${canonical}" fetch --no-tags --quiet -- "${quarantine}" \
      "${RIG_QUARANTINE_REF}" 2>/dev/null || true
  fi

  stage_emit harvest pass
  printf '%s\n' "${oid}" >"${run}/pinned-oid"

  # ── stage 2: conform ──────────────────────────────────────────────────────
  #
  # Four legs, all against QUARANTINE objects. No worktree, no index, no
  # staging: every leg below is plumbing over the range B..S.
  # Re-raised as a RETURN, never an `exit`, for the same reason harvest's defect
  # is: `pipeline_run` must stay usable from a caller that redirects it (F-P01-1).
  status=0
  token=$(conform_stage "${quarantine}" "${base}" "${oid}" "${slice}") || status=$?
  if [ "${status}" -eq "${RIG_EXIT_DEFECT}" ]; then
    rig_warn 'RIG DEFECT raised by conform — see above'
    return "${RIG_EXIT_DEFECT}"
  fi
  if [ "${status}" -ne 0 ]; then
    stage_emit conform refuse "${token}"
    return 1
  fi
  stage_emit conform pass

  # ── stage 3: verify ───────────────────────────────────────────────────────
  token=$(verify_stage "${run}" "${quarantine}" "${oid}" "${verify_cmd}") || {
    stage_emit verify refuse "${token}"
    return 1
  }
  stage_emit verify pass

  # ── stage 4: advance ──────────────────────────────────────────────────────
  token=$(advance_stage "${canonical}" "${quarantine}" "${accepted}" "${base}" "${oid}") || {
    stage_emit advance refuse "${token}"
    return 1
  }
  stage_emit advance pass
  return 0
}

# conform_stage <quarantine> <B> <S> <slice>
# Prints the refusal token and returns 1, or returns 0 silently.
conform_stage() {
  local q=$1 base=$2 oid=$3 slice=$4

  # LEG 1 — ancestry. I3: this precedes everything that normalises the result.
  # A merge commit S with parents (B, X) satisfies a naive single-commit
  # predicate, so only an ancestry check that rejects merges kills H3.
  git -C "${q}" merge-base --is-ancestor "${base}" "${oid}" 2>/dev/null || {
    printf 'ancestry-not-descendant'
    return 1
  }
  if [ -n "$(git -C "${q}" rev-list --min-parents=2 "${base}..${oid}" 2>/dev/null)" ]; then
    printf 'ancestry-merge-commit'
    return 1
  fi

  # LEG 2 — declared scope, via THE EXISTING VERB over an arbitrary rev-range.
  # It folds the range as `actual` against the slice's design-target selectors,
  # exits nonzero on any undeclared path, and its range fold is already
  # belt-hardened. Reaching for shell here would re-derive a hardened thing.
  #
  # A REFUSAL AND A FAILURE TO INVOKE ARE DIFFERENT ANSWERS, and collapsing them
  # is what F-P05-29 cost. `>/dev/null 2>&1 || printf undeclared-path` reported a
  # doctrine binary that could not START (exit 127, absent ELF interpreter) as a
  # conform refusal ATTRIBUTED TO THE CAPSULE — 32 hostile-row failures across a
  # 75-minute scored run, all of them the rig's own toolchain. It is the same
  # defect F-P05-28 finding 1 named in the harvester: one token standing for two
  # causes, with the only sentence that says which thrown away by `2>&1`.
  #
  # So: 126/127 is a RIG DEFECT and stderr is kept and re-emitted. Note the
  # defect is RETURNED, not `exit`ed — this function is called inside `$( … )`,
  # where an exit would end only the substitution's subshell and the caller
  # would read a bare nonzero with an empty token (F-P01-1, and
  # mem_019fbd2453997de3aaa53d2239134d18).
  local doctrine err rc=0
  doctrine=$(rig_doctrine_bin)
  err=$("${doctrine}" slice conformance "${slice}" -p "${q}" \
    --against "${base}..${oid}" --strict 2>&1 >/dev/null) || rc=$?
  if [ "${rc}" -eq "${RIG_EXIT_NOEXEC}" ] || [ "${rc}" -eq "${RIG_EXIT_NOTFOUND}" ]; then
    rig_warn "RIG DEFECT: conform leg 2 cannot invoke '${doctrine}' (exit ${rc}) — ${err}"
    return "${RIG_EXIT_DEFECT}"
  fi
  if [ "${rc}" -ne 0 ]; then
    printf 'undeclared-path'
    return 1
  fi

  # LEG 3 — forbidden paths, and it is LOAD-BEARING, not a belt on leg 2.
  # PHASE-01 T7 settled this: `--strict` has NO `.doctrine/`/`.claude/`
  # predicate at all, so a pipeline running only leg 2 passes a `.doctrine/`
  # touch whenever a selector happens to declare that path — and this slice's
  # own selectors are exactly that shape. DO NOT FOLD THIS INTO LEG 2.
  #
  # THE BELT'S OWN INVOCATION FORM (F-4), copied and not re-derived:
  #   core.quotePath=false  a non-ASCII governance path emits verbatim rather
  #                         than C-quoted AND double-quoted, which defeats a
  #                         prefix test
  #   --no-renames          a `.doctrine/` SOURCE leg cannot hide behind a
  #                         same-content destination
  #   -z                    NUL-delimited is the only byte-safe form to parse
  #                         in shell; a path may contain a newline
  # All three exist in the Rust belt because all three evasions are real. A
  # shell leg that drops them scores H5 as "no kill" and reads in the results
  # table as a defect of the capsule MODEL — R4 in its most damaging direction.
  local path
  while IFS= read -r -d '' path; do
    case "${path}" in
      .doctrine/* | .claude/*)
        printf 'forbidden-path'
        return 1
        ;;
    esac
  done < <(git -C "${q}" -c core.quotePath=false diff --name-only --no-renames \
    -z "${base}..${oid}")

  # LEG 4 — tree mode (F-2). The existing rejection cannot be borrowed:
  # `reject_submodules` scans `git ls-files --stage`, which is INDEX-scoped and
  # unreachable from an object-only pipeline. Without this leg a hostile
  # capsule adds a gitlink at a DECLARED path and every other leg passes it.
  local mode name
  while read -r mode _ _ name; do
    case "${mode}" in
      160000)
        printf 'gitlink'
        return 1
        ;;
    esac
    case "${name}" in
      .gitmodules | */.gitmodules)
        printf 'gitmodules'
        return 1
        ;;
    esac
  done < <(git -C "${q}" ls-tree -r "${oid}")
  # Symlinks (120000) stay LEGAL (SL-012): their class-4 hazard is trusted-side
  # path-following, which I4 already dissolves by never materialising a tree.

  return 0
}

# verify_stage <run> <quarantine> <S> <verify-cmd>
verify_stage() {
  local run=$1 q=$2 oid=$3 cmd=$4
  local vcap="${run}/verify-capsule" status=0

  rm -rf -- "${vcap}"
  mkdir -p -- "${vcap}"

  # The clone happens INSIDE the sandbox, so no candidate tree is materialised
  # trusted-side (I4). Source is the QUARANTINE — the objects have been fsck'd
  # and the canonical repo is still untouched at this point.
  "${SANDBOX}" --capsule "${vcap}" --kind verify --source "${q}" \
    --disk-cap "${PIPELINE_VERIFY_DISK_CAP}" \
    -- /rig/provision.sh "${oid}" >/dev/null 2>&1 || {
    printf 'sandbox-failed'
    return 1
  }

  # The verdict is the SANDBOX PROCESS'S EXIT STATUS as the parent observes it,
  # never a file the capsule wrote (I4). `verify.sh` execs the command so the
  # status is the command's own and cannot be mistranslated. The command itself
  # was read from B, trusted-side — this capsule never reads a declaration
  # (F-5): fail-closed on absence is no defence against substitution.
  #
  # `sh -c` rather than an unquoted expansion, and this is a CORRECTNESS fix,
  # not a style one (F-P03-3). Word-splitting a declaration's `verify:` line
  # hands the command its quotes as LITERAL CHARACTERS: `node -e "process.exit(1)"`
  # split naively reaches node as the three words `node`, `-e`,
  # `"process.exit(1)"`, which node evaluates as a harmless string expression
  # and exits 0. A verify command that should have refused SILENTLY ATTESTS.
  # `sh` still execs a single command, so the status remains the command's own
  # and I4 is untouched.
  "${SANDBOX}" --capsule "${vcap}" --kind verify \
    --timeout "${PIPELINE_VERIFY_TIMEOUT}" \
    --disk-cap "${PIPELINE_VERIFY_DISK_CAP}" \
    -- /rig/verify.sh -- sh -c "${cmd}" >/dev/null 2>&1 || status=$?

  # The status → token mapping (I5, D-P02-4). PHASE-02 emits distinguishable
  # STATUSES and no tokens; this is the single place they become tokens.
  #
  # `*)` MEANS ONE THING: the verify command's own nonzero exit. Every status
  # the SANDBOX injects is named above it, and that is not decoration — an
  # unnamed injected status falls through and reports "the project's tests
  # failed" about a run whose tests never finished. Four independent causes
  # stacked behind this one token and it took three measurement rounds to see
  # past the first (F-P05-15).
  case "${status}" in
    0) return 0 ;;
    "${RIG_EXIT_TIMEOUT}") printf 'verify-timeout' ;;
    "${RIG_EXIT_SANDBOX}") printf 'sandbox-failed' ;;
    # The VERIFY capsule's disk bound, folded trusted-side exactly as the WORKER
    # capsule's already is (`harvest_stage`, :256). Same bound, same authority,
    # both kinds — which is what EX-2 claims, and the claim was half-true until
    # this arm existed.
    "${RIG_EXIT_DISK}") printf 'resource-cap' ;;
    *) printf 'suite-failed' ;;
  esac
  return 1
}

# advance_stage <canonical> <quarantine> <accepted-ref> <B> <S>
#
# THE INTERNAL ORDERING IS LOAD-BEARING (F-14). Git cannot advance a ref to
# objects it does not hold, so the transfer must precede the CAS — which means
# a CAS-stage refusal leaves objects in canonical, and an object-count
# assertion taken over ANY advance refusal would red on exactly the rows that
# refuse there (H10/H16), for a reason belonging to git's object model rather
# than to the model under test. So the precondition is read FIRST.
advance_stage() {
  local canonical=$1 q=$2 accepted=$3 base=$4 oid=$5
  local current

  # 1. PRECONDITION — is the accepted ref still at B? If not, refuse HAVING
  #    TRANSFERRED NOTHING. This is the ordinary staleness path, the one
  #    H10/H16 exercise, and it writes zero objects — which is why it keeps
  #    the FULL `assert_outcome` clause while `cas-lost` does not.
  current=$(git -C "${canonical}" rev-parse --verify "${accepted}" 2>/dev/null) || current=""
  if [ "${current}" != "${base}" ]; then
    printf 'stale-base'
    return 1
  fi

  # 2. TRANSFER — the pinned OID into canonical. No refspec destination, so
  #    this writes FETCH_HEAD and creates NO ref: the passed arm of
  #    `assert_outcome` says exactly ONE canonical ref changed, and a transfer
  #    that minted a bookkeeping ref would break it for a reason that is not
  #    about the model.
  #
  #    A transfer that fails outright has NO token in the closed vocabulary,
  #    and mislabelling it `stale-base` would forge the very distinction
  #    `assert_outcome` keys off. It emits a deliberately-illegal token instead,
  #    which `stage_emit` refuses as a RIG DEFECT — the one place that check
  #    can fire from, since an `exit` inside this command substitution would
  #    end only the subshell (F-P01-1).
  git -C "${canonical}" fetch --no-tags --quiet -- "${q}" "${RIG_QUARANTINE_REF}" 2>/dev/null || {
    printf 'transfer-failed'
    return 1
  }

  # 3. CAS — one ref move, expecting old value B. The three-argument
  #    `update-ref` IS the compare-and-swap. Losing it is a GENUINE RACE (the
  #    ref moved between step 1 and step 3), which leaves the step-2 objects
  #    unreferenced and collectable — not landed state, so CON-004 is intact.
  git -C "${canonical}" update-ref -m 'capsule advance' \
    "${accepted}" "${oid}" "${base}" 2>/dev/null || {
    printf 'cas-lost'
    return 1
  }

  return 0
}

# ── the outcome assertion (I1, EX-10) ───────────────────────────────────────

# pipeline_first_refusal <stage-lines-file>  → "stage/token", or empty on pass
pipeline_first_refusal() {
  awk '$2 == "verdict=refuse" {
         sub(/^stage=/, "", $1); sub(/^token=/, "", $3);
         print $1 "/" $3; exit }' "$1"
}

# assert_outcome <run> <stage/token or empty>
#
# OUTCOME-CONDITIONAL, and it KEYS OFF THE TOKEN, NEVER THE STAGE (EX-10). An
# earlier draft said "byte-identical on every row regardless of outcome", which
# is wrong — a passing row must advance the ref. Keying off the stage would be
# wrong differently: both advance tokens share a stage, so `cas-lost`'s
# refs-only clause would silently absorb `stale-base`'s full clause, weakening
# the assertion on H10/H16 — the rows where it does the most work.
assert_outcome() {
  local run=$1 refusal=${2:-}
  local canonical="${run}/canonical" token="${refusal#*/}"
  local refs_now objects_now refs_before objects_before changed

  refs_now=$(canonical_refs "${canonical}")
  objects_now=$(canonical_objects "${canonical}")
  refs_before=$(cat "${run}/canonical-refs.before")
  objects_before=$(cat "${run}/canonical-objects.before")
  changed=$(comm -3 <(printf '%s\n' "${refs_before}") <(printf '%s\n' "${refs_now}") | wc -l)

  case "${token}" in
    '')
      # PASSED ⇒ exactly one canonical ref changed (the accepted ref, to the
      # pinned OID) and nothing else. `comm -3` reports the old and new lines
      # of one moved ref, hence 2.
      rig_assert_eq 'assert_outcome[pass]: exactly one canonical ref changed' 2 "${changed}"
      rig_assert_eq 'assert_outcome[pass]: the accepted ref is at the pinned OID' \
        "$(cat "${run}/pinned-oid")" \
        "$(git -C "${canonical}" rev-parse --verify "$(contract_field "${run}" accepted)")"
      ;;
    cas-lost)
      # A GENUINE RACE. The step-2 objects are EXPECTED, unreferenced and
      # collectable, so their count is RECORDED, NOT ASSERTED (F-14) — a
      # scope correction, not a weakening. Unreferenced objects are not landed
      # state: nothing points at them and no future read can reach them.
      rig_assert_eq 'assert_outcome[cas-lost]: canonical refs unchanged' 0 "${changed}"
      printf '  note  assert_outcome[cas-lost]: %s orphan object(s) recorded, not asserted\n' \
        "$((objects_now - objects_before))"
      ;;
    *)
      # REFUSED at harvest, conform, verify, or advance/STALE-BASE ⇒ canonical
      # is byte-identical to its pre-run state: same refs AND THE SAME OBJECT
      # COUNT. The object-count clause is what makes this falsifiable rather
      # than decorative — it is precisely the thing a quarantine namespace
      # inside canonical would have broken, on every refused row.
      rig_assert_eq "assert_outcome[${token}]: canonical refs unchanged" 0 "${changed}"
      rig_assert_eq "assert_outcome[${token}]: canonical OBJECT COUNT unchanged" \
        "${objects_before}" "${objects_now}"
      ;;
  esac
}

# ── executed directly ───────────────────────────────────────────────────────

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  rig_enter
  label=${1:?usage: pipeline.sh <label> <fixture> <declaration> <fetch|bundle>}
  fixture=${2:?usage: pipeline.sh <label> <fixture> <declaration> <fetch|bundle>}
  declaration=${3:?usage: pipeline.sh <label> <fixture> <declaration> <fetch|bundle>}
  mechanism=${4:-fetch}

  pipeline_setup "${label}" "${fixture}" "${declaration}"
  RUN="${PIPELINE_RUN}"
  pipeline_capsule "${RUN}"
  # NOT `pipeline_run … | tee`: a pipe would run it in a SUBSHELL, so a RIG
  # DEFECT return could not reach this shell and the run would score as an
  # ordinary refusal. Same family as F-P01-1 — in shell the invocation form
  # silently changes the semantics of a refusal.
  pipeline_run "${RUN}" "${mechanism}" >"${RUN}/stages" || rc=$?
  cat "${RUN}/stages"
  if [ "${rc:-0}" -eq "${RIG_EXIT_DEFECT}" ]; then
    rig_warn "pipeline (${label}/${mechanism}): RIG DEFECT — not a result"
    exit "${RIG_EXIT_DEFECT}"
  fi
  assert_outcome "${RUN}" "$(pipeline_first_refusal "${RUN}/stages")"
  rig_assert_done "pipeline (${label}/${mechanism})"
fi
