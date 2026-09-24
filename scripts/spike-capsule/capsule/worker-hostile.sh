#!/usr/bin/env bash
# capsule/worker-hostile.sh — the RESOURCE-HOSTILE worker (P-C3 row H7).
#
#   usage: worker-hostile.sh [<path>] [<message>]   (runs INSIDE the sandbox)
#
# The third vehicle beside `worker-stub.sh` and `worker-agent.sh`, and the only
# one that deliberately dies. It exists because H7 is the one row whose
# observable is produced by an enforcement point INSIDE the sandbox: the disk
# cap is evaluated by `sandbox.sh` — `ulimit -f` in the namespace, then `du -s`
# on the way out — before control ever returns to the harness. The trusted-side
# plant seam every other row uses arrives after that, so the hazard has to be
# authored here (F-P05-37).
#
# ── it does the HONEST work first, and that is the row ──────────────────────
#
# A capsule that only blew its cap would refuse at stage 1 for an uninteresting
# reason: there was nothing to ingest. This one commits, publishes
# `RIG_RESULT_REF`, writes a valid bundle and rings — so a harvestable result
# genuinely stands — and THEN exhausts its bound. The refusal is therefore the
# cap arriving BEFORE ingestion rather than in place of it, which is exactly
# what `pipeline.sh`'s stage-1 ordering claims: *"a capsule that blew the disk
# cap has nothing worth ingesting, and streaming it first would be the cap
# arriving too late."*
#
# Ringing before dying is not a convenience either. The doorbell carries no
# authority (H14), so a bell rung for a result the capsule then abandons is a
# faithful hostile act — and it keeps the control plane off its 120s deadline.
#
# ── the SPARSE oversize, and the leg it does not exercise ───────────────────
#
# The blob is sparse. That is the leg P-C2 identified as the nastier one
# (F-P03-1, `probe-capsule.sh:151-167`): `ulimit -f` fires, the tree stays tiny,
# and `du` has nothing to say — a bound that bit while the sandbox reported
# success, before the 153 classification existed.
#
# The CUMULATIVE leg is deliberately NOT exercised here. It is already owned by
# P-C2, which drives both legs against both capsule kinds with a positive
# control at an 8 MiB cap. Re-proving it in this row would be a second copy of
# someone else's claim, and on H7's cap it would cost cap-many REAL bytes per
# execution — a cost D-P05-18 explicitly declined to pay for attribution it
# buys with a control instead.
set -euo pipefail

INNER_CAPSULE=/capsule
CLONE="${INNER_CAPSULE}/repo"

# The hostile artifacts sit in the capsule's writable root and OUTSIDE the
# clone, uncommitted. That separation is load-bearing: it leaves the published
# result completely honest, so nothing about the stage-1 refusal can be
# explained by a damaged payload.
BLOB="${INNER_CAPSULE}/hostile-blob"
DEEP="${INNER_CAPSULE}/hostile-deep"

# Deep enough to be pathological, short enough to stay well inside PATH_MAX
# (4096): 200 × 5 bytes ≈ 1000. A tree that could not be traversed would be
# testing the rig's teardown, not the capsule model.
DEEP_LEVELS=200

die() {
  printf 'worker-hostile: %s\n' "$*" >&2
  exit 1
}

# Same fail-closed env contract as `worker-stub.sh`, and for the same reasons —
# every name that crosses the boundary comes from the control plane, and a
# default here would silently restore the drift the env hop removes (F-P02-6).
DOORBELL="${INNER_CAPSULE}/${RIG_DOORBELL:?worker-hostile: RIG_DOORBELL not set — the control plane names the doorbell}"
RESULT_REF="${RIG_RESULT_REF:?worker-hostile: RIG_RESULT_REF not set — the control plane names the result ref}"
BUNDLE="${INNER_CAPSULE}/${RIG_BUNDLE:?worker-hostile: RIG_BUNDLE not set — the control plane names the bundle path}"

path=${1:-src/capsule-stub.ts}
message=${2:-'[add] capsule stub worker touch'}

[ -d "${CLONE}" ] || die "nothing provisioned at ${CLONE} — run provision.sh first"
cd -- "${CLONE}"

# ── 1. the honest result ─────────────────────────────────────────────────────
mkdir -p -- "$(dirname -- "${path}")"
printf 'export const stub = %s;\n' "$(date +%s)" >>"${path}"
git add -- "${path}"
git commit --quiet -m "${message}"
git update-ref "${RESULT_REF}" HEAD
git bundle create --quiet "${BUNDLE}" "${RESULT_REF}" 2>/dev/null ||
  die "could not write the bundle at ${BUNDLE}"
printf 'capsule=%s oid=%s\n' "${INNER_CAPSULE}" "$(git rev-parse HEAD)" >"${DOORBELL}"

# ── 2. the pathological deep tree ────────────────────────────────────────────
deep="${DEEP}"
for ((i = 0; i < DEEP_LEVELS; i++)); do deep="${deep}/d"; done
mkdir -p -- "${deep}"
printf 'leaf\n' >"${deep}/leaf"

# ── 3. the oversize blob ─────────────────────────────────────────────────────
#
# THE BOUND IS ASKED FOR, NEVER ASSUMED. `ulimit -f` reports this capsule's own
# per-file limit in 1024-byte blocks, so the blob is sized against the cap that
# is actually in force rather than against a number copied from the control
# plane (STD-001). A row whose cap moved would otherwise stop exceeding it and
# score a silent pass.
limit_blocks=$(ulimit -f)
[ "${limit_blocks}" != unlimited ] ||
  die 'no per-file bound in force — this vehicle has no hazard to author'

# One block past the limit, so the write is over by the smallest amount that
# can be over. `bs=1 count=1 seek=N` is P-C2's spelling of a sparse oversize
# (`probe-capsule.sh:163-167`), reused rather than re-derived.
seek=$(((limit_blocks + 1) * 1024))
printf 'worker-hostile: writing a sparse %s-byte blob against a %s-byte bound\n' \
  "$((seek + 1))" "$((limit_blocks * 1024))"

dd if=/dev/zero of="${BLOB}" bs=1 count=1 seek="${seek}" 2>/dev/null

# UNREACHED on any host where the bound is enforced. Left as a statement rather
# than omitted: if this line ever runs, the vehicle authored no hazard and the
# row must fail loudly instead of scoring a refusal that came from elsewhere.
die "the ${limit_blocks}-block per-file bound did NOT fire on a $((seek + 1))-byte write"
