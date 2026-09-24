#!/usr/bin/env bash
# control/harvest-bundle.sh — stage 1, mechanism M-B (EX-3, VT-3).
#
#   usage: harvest-bundle.sh <capsule> <quarantine>   → pinned OID on stdout
#
# Same two arguments and same stdout as `harvest-fetch.sh` (EX-1), so the P-C3
# matrix loops over both mechanisms without branching.
#
# ── why this file is longer than M-A, and why that is a RESULT ───────────────
#
# The bundle is the ONE capsule-authored artifact this design does not delete,
# so it inherits every RT-4 obligation — and those obligations are a
# trusted-side FILE-INGESTION BOUNDARY that M-A does not carry at all. That
# asymmetry is a QUE-200 verdict input in its own right (design § 5.2), not
# incidental bulk: leaving it unnamed would silently understate M-B's cost in
# the comparison the whole rig exists to make.
#
# Four legs, and the ORDER is load-bearing (EX-3):
#
#   1. the path is CONTROL-PLANE-CHOSEN at a fixed location, and the capsule
#      never names it — it arrives over `--setenv RIG_BUNDLE`, fail-closed.
#   2. symlinks REFUSED, tested with `-L` FIRST. A symlink to a nonexistent
#      target would otherwise read as `bundle-absent`, which scores RT-4's
#      first attack verbatim as an ordinary missing file.
#   3. SIZE-CAPPED BEFORE `git bundle verify` READS IT. A cap applied after the
#      read is not a cap; the point is that a hostile 2 GiB file is never
#      streamed at all.
#   4. absent / truncated / still being written → `bundle-absent` /
#      `bundle-invalid`, with NO silent wait-and-retry. The doorbell rang; the
#      bundle was supposed to be complete before it did.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

# Default 64 MiB. A parameter rather than a literal so the RT-4 size-cap row
# can drive it down and observe the leg biting (STD-001).
RIG_BUNDLE_CAP="${RIG_BUNDLE_CAP:-$((64 * 1024 * 1024))}"

refuse() {
  printf 'token=%s\n' "$1" >&2
  exit 1
}

capsule=${1:?usage: harvest-bundle.sh <capsule> <quarantine>}
quarantine=${2:?usage: harvest-bundle.sh <capsule> <quarantine>}

# I6 — FIRST, as a STATEMENT (F-P01-1).
rig_enter

capsule=$(rig_resolve "${capsule}")
quarantine=$(rig_resolve "${quarantine}")
guard_not_real_repo "${capsule}"
guard_not_real_repo "${quarantine}"

[ -d "${quarantine}/.git" ] || rig_die "not a quarantine repository: ${quarantine}"

# LEG 1 — the path. Composed HERE from the control plane's own constant; the
# capsule was told this name, it did not choose it.
bundle="${capsule}/${RIG_BUNDLE}"

# LEG 2 — symlinks refused, and refused BEFORE any test that follows links.
# `-L` does not dereference, so this catches a symlink whose target does not
# exist, which `-e` would report as merely absent.
[ -L "${bundle}" ] && refuse bundle-unsafe-path

# ...and no symlink anywhere on the path either, which is the same attack one
# directory up. Resolved with `-e` (all components must exist) and required to
# land where the control plane put it.
resolved=$(realpath -e -- "${bundle}" 2>/dev/null) || resolved=""
if [ -n "${resolved}" ] && [ "${resolved}" != "${capsule}/${RIG_BUNDLE}" ]; then
  refuse bundle-unsafe-path
fi

# LEG 4a — absent. No wait, no retry: the doorbell already rang.
[ -f "${bundle}" ] || refuse bundle-absent

# LEG 3 — SIZE CAP, before `git bundle verify` reads a byte of it.
size=$(wc -c <"${bundle}")
[ "${size}" -le "${RIG_BUNDLE_CAP}" ] || refuse resource-cap

# LEG 4b — truncated, still being written, or simply not a bundle. `verify`
# also checks that the prerequisites it names are satisfiable, which is the
# leg that catches a bundle whose base we do not hold.
git -C "${quarantine}" bundle verify -- "${bundle}" >/dev/null 2>&1 ||
  refuse bundle-invalid

# READ THE RESULT REF EXACTLY ONCE, AND PIN IT (RT-5) — here the read is of the
# bundle's own ref list, which is the artifact's single source of truth.
oid=$(git -C "${quarantine}" bundle list-heads -- "${bundle}" |
  awk -v ref="${RIG_RESULT_REF}" '$2 == ref { print $1; exit }')
[ -n "${oid}" ] || refuse bundle-invalid

# fsck on ingest, exactly as M-A does — the bundle is a transport, not a trust
# boundary, and the objects inside it are as untrusted as the ones on the wire.
git -C "${quarantine}" config fetch.fsckObjects true

git -C "${quarantine}" fetch --no-tags --quiet -- "${bundle}" \
  "+${RIG_RESULT_REF}:${RIG_QUARANTINE_REF}" 2>/dev/null || refuse fsck-failed

got=$(git -C "${quarantine}" rev-parse --verify "${RIG_QUARANTINE_REF}")
[ "${got}" = "${oid}" ] || refuse oid-mismatch

git -C "${quarantine}" fsck --no-progress --connectivity-only >/dev/null 2>&1 ||
  refuse fsck-failed

printf '%s\n' "${oid}"
