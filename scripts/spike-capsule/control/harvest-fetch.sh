#!/usr/bin/env bash
# control/harvest-fetch.sh — stage 1, mechanism M-A (EX-1, VT-2).
#
#   usage: harvest-fetch.sh <capsule> <quarantine>   → pinned OID on stdout
#
# ONE SIGNATURE WITH M-B (EX-1). `harvest-bundle.sh` takes the same two
# arguments and prints the same thing, so the P-C3 matrix loops over the two
# mechanisms without branching — the comparison QUE-200 exists to make is only
# clean if the harness treats them identically.
#
# Refusal protocol: stdout carries the OID and NOTHING ELSE. A refusal prints
# `token=<t>` on stderr and exits nonzero. The token is computed HERE, trusted
# side, from git's own report — never relayed from capsule-authored text (I5).
#
# ── the second hop is DELETED, and that is the point (F-3) ───────────────────
#
# probe-specs described capsule → quarantine → *a quarantine namespace inside
# canonical*. That second hop is gone. A ref in canonical drags its objects
# into the canonical object database, so a hostile 2 GiB blob would land there
# BEFORE the refusal meant to stop it — and `assert_outcome`'s object-count
# clause, the one thing that makes I1 falsifiable rather than decorative, would
# red on every refused row for a reason belonging to git rather than to the
# model under test. Objects reach canonical exactly once, at stage 4, after
# every gate has passed.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

refuse() {
  printf 'token=%s\n' "$1" >&2
  exit 1
}

capsule=${1:?usage: harvest-fetch.sh <capsule> <quarantine>}
quarantine=${2:?usage: harvest-fetch.sh <capsule> <quarantine>}

# I6 — FIRST, as a STATEMENT (F-P01-1).
rig_enter

capsule=$(rig_resolve "${capsule}")
quarantine=$(rig_resolve "${quarantine}")
guard_not_real_repo "${capsule}"
guard_not_real_repo "${quarantine}"

clone="${capsule}/repo"
[ -d "${quarantine}/.git" ] || rig_die "not a quarantine repository: ${quarantine}"

# A capsule that published no result at all. The closed vocabulary has no M-A
# token for this — `bundle-absent` is M-B's, and naming it here would be a
# mechanism lie in the one column the rig exists to compare. Recorded as a
# vocabulary gap (OQ-c) and surfaced as a RIG DEFECT rather than scored: an
# unexercised path stated as impossible is how a gap stops being looked at.
if [ ! -d "${clone}/.git" ] ||
  ! git -C "${clone}" rev-parse --verify --quiet "${RIG_RESULT_REF}" >/dev/null; then
  rig_warn "RIG DEFECT: no ${RIG_RESULT_REF} in ${clone} — M-A has no token for an absent result (OQ-c)"
  exit "${RIG_EXIT_DEFECT}"
fi

# READ THE RESULT REF EXACTLY ONCE, AND PIN IT (RT-5). Everything downstream
# names this OID, never the ref: a ref the capsule still owns can move between
# any two reads, and a pipeline that re-read it would gate one commit and land
# another.
oid=$(git -C "${clone}" rev-parse --verify "${RIG_RESULT_REF}")

# fsck ON INGEST, before anything inspects the objects. `fetch.fsckObjects` is
# set on the quarantine rather than passed per-invocation so it also covers the
# verify capsule's clone out of here.
git -C "${quarantine}" config fetch.fsckObjects true

git -C "${quarantine}" fetch --no-tags --quiet -- "${clone}" \
  "+${RIG_RESULT_REF}:${RIG_QUARANTINE_REF}" 2>/dev/null || refuse fsck-failed

# The ref moved between the pin and the fetch. This is why the OID is pinned at
# all, so it is asserted rather than assumed.
got=$(git -C "${quarantine}" rev-parse --verify "${RIG_QUARANTINE_REF}")
[ "${got}" = "${oid}" ] || refuse oid-mismatch

# Belt to `fetch.fsckObjects`' braces: connectivity and object well-formedness
# over what actually landed. `--no-progress` because stderr is parsed above.
git -C "${quarantine}" fsck --no-progress --connectivity-only >/dev/null 2>&1 ||
  refuse fsck-failed

printf '%s\n' "${oid}"
