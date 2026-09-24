#!/usr/bin/env bash
# control/probe-c1a.sh — P-C1a, the deterministic cost baseline (EX-4, VA-2).
#
#   usage: probe-c1a.sh [--keep]           (dispatched by `rig c1a`)
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# The measurement terms — `step_start`, `record`, `peak_worker`, `rig_state`,
# `REPORT_COLUMNS` and the VA-2 shape assertion — live in `lib/measure.sh`,
# extracted when P-C1b needed every one of them (PHASE-06). Their rationale
# (absolutes never deltas; measurements taken trusted-side) is stated there.
#
# ── the step list is never SHORTENED (EX-4) ──────────────────────────────────
#
# probe-specs § P-C1 names six steps. This environment does not provide all six
# as separable operations, and the discipline for that is the one an `n/a`
# matrix cell already sets: the step stays in the list and carries its REASON.
# Dropping it would leave a shorter list that looks complete.
#
#   clone       measured — the capsule's own `git clone` at B, inside the sandbox
#   provision   COMPOSITE with `clone`, not measured separately: probe-specs
#               step 2 is `.envrc` + `direnv allow`, and neither binary exists
#               in this jail. What provisioning remains (detach at B, capsule
#               identity, remote strip) is the SAME control-plane runner
#               invocation as the clone, which dominates it. Carried with no
#               number rather than with the clone's number, so a reader summing
#               the column cannot double-count it.
#   nix env     `n/a` — `nix`/`direnv` absent; the toolchain arrives by ro-bind
#               of /nix/store (PHASE-02 EX-8, capsule/provision.sh).
#   build       measured — `npm run build` in the worker capsule, at B
#   test        measured — `npm test` in the worker capsule, at B (probe-specs
#               step 3's cold baseline: green before the phase runs)
#   phase       measured — the stub worker (DEC-109); probe-specs step 4
#   harvest     measured — doorbell → accepted-ref advance, the whole four-stage
#               pipeline. This is § 9's "git operations between doorbell and
#               accepted-ref advance" row, so it is timed as ONE span; the
#               verify capsule's own clone and suite run are inside it, and that
#               is admission cost, not a second cold baseline.
#
# ── the numbers must describe a run that WORKED ──────────────────────────────
#
# A cost baseline taken over a broken run is worse than no baseline: it is a
# number, so it gets quoted. The probe therefore asserts the pipeline reached
# green and that `assert_outcome`'s passed arm holds, and reds if it did not.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=pipeline.sh
. "${RIG_DIR}/control/pipeline.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/measure.sh
. "${RIG_DIR}/lib/measure.sh"

keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) keep=1 ;;
    -h | --help)
      sed -n '2,6p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) rig_die "unknown argument: $1" ;;
  esac
  shift
done

# I6 — FIRST, as a STATEMENT. Inside `$( … )` the refusal would end only the
# substitution's subshell (F-P01-1).
rig_enter

FIXTURE="${RIG_ROOT}/fixtures/light/repo"
DECLARATION="${RIG_ROOT}/fixtures/light/interpretation-surface.txt"
REPORT="${RIG_ROOT}/probes/c1a/results.tsv"

[ -d "${FIXTURE}" ] || rig_die "light fixture not built (F1): ${FIXTURE} — run control/fixture-light.sh"
[ -f "${DECLARATION}" ] || rig_die "light declaration missing: ${DECLARATION}"

printf '\nP-C1a — deterministic cost baseline, stub worker (EX-4, VA-2)\n'

# ── run scaffolding ──────────────────────────────────────────────────────────
#
# `pipeline_setup` PUBLISHES `PIPELINE_RUN`; it is never subshelled, because it
# calls `guard_not_real_repo`, which refuses by `exit` (F-P03-4).
step_start
pipeline_setup c1a "${FIXTURE}" "${DECLARATION}"
RUN="${PIPELINE_RUN}"
record setup measured "$(step_elapsed)" s \
  'control-plane run scaffolding — canonical + quarantine clones, contract, pinned declaration (outside probe-specs step list)'

CAPSULE="${RUN}/capsule"
BASE=$(contract_field "${RUN}" base)
STUB=$(contract_field "${RUN}" stub)

# ── 1. clone (+ provision) ───────────────────────────────────────────────────
step_start
"${SANDBOX}" --capsule "${CAPSULE}" --source "${RUN}/canonical" \
  -- /rig/provision.sh "${BASE}" >/dev/null 2>&1 ||
  rig_die "P-C1a: provisioning failed — the baseline would describe a broken run"
record clone measured "$(step_elapsed)" s \
  "in-capsule git clone from the ro-bound source, detached at ${BASE:0:12}"
peak_worker "${CAPSULE}"

record provision composite - - \
  'same runner invocation as clone (no separate manifest step: .envrc/direnv absent in this jail); carried without a number so the column cannot be double-counted'

# ── 2. nix env ready ─────────────────────────────────────────────────────────
record 'nix-env-ready' n/a - - \
  'nix and direnv are ABSENT in this jail; the toolchain reaches the capsule by ro-bind of /nix/store and a filtered PATH (PHASE-02 EX-8) — recorded, never dropped from the step list'

# ── 3. cold baseline: build, then test ───────────────────────────────────────
#
# At B, before the worker runs. probe-specs step 3 wants the capsule proven able
# to build and test the contracted base — a phase that reaches green in a
# capsule whose baseline was already red would be measuring the wrong thing.
step_start
"${SANDBOX}" --capsule "${CAPSULE}" -- sh -c 'cd /capsule/repo && npm run --silent build' >/dev/null 2>&1 ||
  rig_die "P-C1a: cold-baseline build failed at ${BASE:0:12}"
record build measured "$(step_elapsed)" s 'npm run build (tsc) in the worker capsule, at B'
peak_worker "${CAPSULE}"

step_start
"${SANDBOX}" --capsule "${CAPSULE}" -- sh -c 'cd /capsule/repo && npm test' >/dev/null 2>&1 ||
  rig_die "P-C1a: cold-baseline suite failed at ${BASE:0:12}"
record test measured "$(step_elapsed)" s 'npm test in the worker capsule, at B — the cold baseline green'
peak_worker "${CAPSULE}"

# `dist/` is fixture-gitignored, so it never reaches a commit — but it is real
# bytes and the peak above has already counted them. Cleaned so the phase step
# below measures the worker, not a build output being re-walked.
"${SANDBOX}" --capsule "${CAPSULE}" -- sh -c 'cd /capsule/repo && npm run --silent clean' >/dev/null 2>&1 || true

# ── 4. the phase ─────────────────────────────────────────────────────────────
#
# The worker's status is DATA (a capsule that hit a bound must flow into a
# stage-1 refusal rather than dying here), so it is written to the run the way
# `pipeline_capsule` writes it — this probe replaces that call only to time its
# parts, and must not drop the file the pipeline reads.
step_start
worker_status=0
"${SANDBOX}" --capsule "${CAPSULE}" -- /rig/worker-stub.sh "${STUB}" >/dev/null 2>&1 || worker_status=$?
printf '%s\n' "${worker_status}" >"${RUN}/worker-status"
rig_wait_doorbell "${CAPSULE}" "${PIPELINE_DOORBELL_DEADLINE}" \
  "${PIPELINE_DOORBELL_INTERVAL}" >/dev/null || true
record phase measured "$(step_elapsed)" s \
  'the stub worker (DEC-109): commit, result ref, bundle, doorbell'
peak_worker "${CAPSULE}"

# ── 5. harvest → accepted-ref advance ────────────────────────────────────────
#
# REDIRECTED, never piped: a pipe subshells `pipeline_run`, so a RIG DEFECT
# return could not reach this shell and would score as an ordinary refusal
# (F-P01-1's family).
step_start
rc=0
pipeline_run "${RUN}" fetch >"${RUN}/stages" || rc=$?
harvest_elapsed=$(step_elapsed)
cat "${RUN}/stages"
if [ "${rc}" -eq "${RIG_EXIT_DEFECT}" ]; then
  rig_warn 'P-C1a: RIG DEFECT — not a result'
  exit "${RIG_EXIT_DEFECT}"
fi
record harvest measured "${harvest_elapsed}" s \
  'doorbell → accepted-ref advance: harvest, conform, verify (its own capsule and suite), advance'
peak_worker "${CAPSULE}"

record peak-disk measured "${PEAK_WORKER}" B \
  'worker capsule, high-water mark over the run — an ABSOLUTE (VA-2)'
record peak-disk-verify measured "$(capsule_disk "${RUN}/verify-capsule")" B \
  'verify capsule, after the verify stage — an ABSOLUTE (VA-2)'

# ── the run must have WORKED ─────────────────────────────────────────────────

refusal=$(pipeline_first_refusal "${RUN}/stages")
rig_assert_eq 'P-C1a measured a run that reached green (no stage refused)' '' "${refusal}"
assert_outcome "${RUN}" "${refusal}"

# ── EX-4 / VA-2 made mechanical ──────────────────────────────────────────────
#
# Both claims are about the SHAPE of the recorded evidence, so both are asserted
# against the rows about to be written. Left to prose they would be true today
# and quietly false after one edit.

for step in clone provision nix-env-ready build test harvest; do
  rig_assert_eq "EX-4: the step list carries '${step}'" \
    "${step}" "$(row_field "${step}" 1)"
done

rig_assert_eq "EX-4: 'nix env ready' is recorded n/a, not dropped" \
  'n/a' "$(row_field nix-env-ready 2)"
rig_assert "EX-4: the n/a row carries ITS REASON, not a bare n/a" \
  test -n "$(row_field nix-env-ready 5)"
rig_assert "EX-4: the composite provision row carries its reason" \
  test -n "$(row_field provision 5)"

# VA-2 stated as a property of the file: five columns, none of them an incumbent
# or a delta. A future edit that adds one has to fail this to land.
assert_absolutes_only

# ── write it out ─────────────────────────────────────────────────────────────

mkdir -p -- "$(dirname -- "${REPORT}")"
[ -s "${REPORT}" ] || printf '%s\n' "${REPORT_COLUMNS}" >"${REPORT}"
{
  printf 'p-c1a: %s\tstub\tin-jail\tbase=%s\trig=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${BASE:0:12}" "$(rig_state)"
  printf '%s\n' "${ROWS[@]}"
} >>"${REPORT}"

printf '\nresults: %s\n' "${REPORT}"

[ "${keep}" -eq 1 ] || pipeline_teardown "${RUN}"

rig_assert_done 'probe-c1a'
