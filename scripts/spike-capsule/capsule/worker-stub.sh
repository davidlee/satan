#!/usr/bin/env bash
# capsule/worker-stub.sh — the scripted worker (DEC-109 default).
#
#   usage: worker-stub.sh [<message>]           (runs INSIDE the sandbox)
#
# Deterministic by design. `--stub` is the rig's default and `--agent` is
# explicit opt-in, because only P-C1 needs an LLM — everything in P-C2 and P-C3
# is scripted by DQ-2 mandate, and a probe "contained" by a worker politely
# declining is void.
#
# Inside the capsule the worker has TOTAL FREEDOM (I1a): commit, amend, rebase,
# iterate. The boundary is where the constraint lives, not the workspace. So
# this makes an ordinary commit and rings — nothing here is a permission check.
set -euo pipefail

INNER_CAPSULE=/capsule
CLONE="${INNER_CAPSULE}/repo"

die() {
  printf 'worker-stub: %s\n' "$*" >&2
  exit 1
}

# Every name that crosses the boundary comes from the CONTROL PLANE, over the
# sandbox env — this script runs inside the sandbox and cannot source the
# library that defines them. FAIL CLOSED rather than defaulting: a worker that
# rings a bell nobody listens for is indistinguishable from a worker that never
# finished, and a default here would silently restore exactly the drift this env
# hop exists to remove (F-P02-6).
#
# The bundle path is the same mechanism carrying a stronger claim: RT-4/F-6
# requires that **the capsule never names the harvest path**, because a capsule
# free to choose it would choose a symlink.
DOORBELL="${INNER_CAPSULE}/${RIG_DOORBELL:?worker-stub: RIG_DOORBELL not set — the control plane names the doorbell}"
RESULT_REF="${RIG_RESULT_REF:?worker-stub: RIG_RESULT_REF not set — the control plane names the result ref}"
BUNDLE="${INNER_CAPSULE}/${RIG_BUNDLE:?worker-stub: RIG_BUNDLE not set — the control plane names the bundle path}"

# WHERE the stub writes is a control-plane choice, because it is a JOIN with
# the fixture's `design-target` selectors: a stub writing outside them makes
# every run refuse at conform leg 2 for a reason that is about the rig's own
# scaffolding rather than about the capsule model. The happy path needs a
# DECLARED path; the hostile rows need undeclared and forbidden ones. Passing
# it in is what keeps that choice visible at the call site instead of buried
# here. Default suits the light fixture (`src/**`).
path=${1:-src/capsule-stub.ts}
message=${2:-'[add] capsule stub worker touch'}

[ -d "${CLONE}" ] || die "nothing provisioned at ${CLONE} — run provision.sh first"
cd -- "${CLONE}"

mkdir -p -- "$(dirname -- "${path}")"
printf 'export const stub = %s;\n' "$(date +%s)" >>"${path}"
git add -- "${path}"
git commit --quiet -m "${message}"

# The result the control plane will harvest. A REF the capsule owns, at a name
# the control plane chose — the capsule never names the harvest path, and the
# ref is read exactly once and pinned to an OID trusted-side (RT-5).
git update-ref "${RESULT_REF}" HEAD

# M-B's artifact, written BEFORE the ring — the doorbell is the signal that the
# bundle is complete, so a bundle still being written when the bell rings is a
# stage-1 refusal the control plane must catch rather than wait out (EX-3).
# M-A ignores this file entirely; one worker serves both mechanisms so the
# matrix loops without branching.
git bundle create --quiet "${BUNDLE}" "${RESULT_REF}" 2>/dev/null ||
  die "could not write the bundle at ${BUNDLE}"

# Ring. The doorbell carries NO AUTHORITY: content is never read, so what goes
# in the file is irrelevant by construction rather than by convention. Written
# non-empty on purpose — a rig that only ever rang with an empty file would not
# be exercising the "content is never read" claim at all.
printf 'capsule=%s oid=%s\n' "${INNER_CAPSULE}" "$(git rev-parse HEAD)" >"${DOORBELL}"

printf 'worker-stub: %s at %s\n' "${RESULT_REF}" "$(git rev-parse HEAD)"
