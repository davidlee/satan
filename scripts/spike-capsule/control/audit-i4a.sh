#!/usr/bin/env bash
# audit-i4a.sh — no control-plane runner lives in the capsule's writable root.
#
#   usage: audit-i4a.sh <capsule> [--positive-control]
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# ── what this defends ────────────────────────────────────────────────────────
#
# I4a: the runners enter as read-only binds from OUTSIDE the writable root, so
# no script the capsule can write is ever the process whose exit status is the
# verdict. The mount posture makes that structural — but the posture is one
# `cp` away from being undone, and the P-C2 profile's "rw bind = capsule dir
# only" would happily permit that `cp`. RT-1 is the programme's only blocker.
# This is the standing check that the reflex has not crept in.
#
# ── by CONTENT, not by name ──────────────────────────────────────────────────
#
# A name-only scan is defeated by `cp verify.sh check.sh`, which is not a
# clever evasion — it is what an ordinary refactor looks like. Both legs run:
# content first (a hash match at any path), then name (a runner-shaped name
# holding something else, which is the more confusing failure to debug).
#
# ── the positive control (VA-2) ──────────────────────────────────────────────
#
# `--positive-control` plants a copy, requires the audit to REFUSE, removes it,
# and requires the audit to PASS. Both directions, because an audit that
# refuses everything is exactly as broken as one that refuses nothing — and a
# negative grep without a positive control proves only that grep ran.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

RUNNERS="${RIG_DIR}/capsule"

capsule=""
positive_control=0
while [ $# -gt 0 ]; do
  case "$1" in
    --positive-control) positive_control=1 ;;
    -h | --help)
      sed -n '2,6p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) rig_die "unknown flag: $1" ;;
    *) capsule=$1 ;;
  esac
  shift
done

[ -n "${capsule}" ] || rig_die "usage: audit-i4a.sh <capsule> [--positive-control]"

# I6 — FIRST, as a STATEMENT (F-P01-1).
rig_enter

capsule=$(rig_resolve "${capsule}")
guard_not_real_repo "${capsule}"
[ -d "${capsule}" ] || rig_die "capsule does not exist: ${capsule}"
[ -d "${RUNNERS}" ] || rig_die "missing runner directory: ${RUNNERS}"

# Prints one line per violation; exit 0 when clean. Deliberately silent about
# how it searched — the OUTPUT is the finding, and an empty output with a
# nonzero exit would be the audit lying by omission.
audit() {
  local runner name hash size found violations=0 candidate
  for runner in "${RUNNERS}"/*.sh; do
    name=$(basename -- "${runner}")
    hash=$(sha256sum -- "${runner}" | cut -d' ' -f1)
    size=$(stat -c %s -- "${runner}")

    # Content leg. Size first because it is a cheap filter over a tree that may
    # hold a whole clone; the hash is what actually decides.
    while IFS= read -r -d '' candidate; do
      if [ "$(sha256sum -- "${candidate}" | cut -d' ' -f1)" = "${hash}" ]; then
        printf 'I4a VIOLATION: %s is a copy of the runner %s\n' "${candidate}" "${name}"
        violations=$((violations + 1))
      fi
    done < <(find "${capsule}" -type f -size "${size}"c -print0)

    # Name leg. A runner-shaped name holding something else is not a copy, but
    # it is a path a future edit could resolve to by mistake.
    while IFS= read -r -d '' found; do
      if [ "$(sha256sum -- "${found}" | cut -d' ' -f1)" != "${hash}" ]; then
        printf 'I4a VIOLATION: %s carries a runner name with foreign content\n' "${found}"
        violations=$((violations + 1))
      fi
    done < <(find "${capsule}" -type f -name "${name}" -print0)
  done
  [ "${violations}" -eq 0 ]
}

if [ "${positive_control}" -eq 0 ]; then
  if audit; then
    printf 'audit-i4a: clean — no control-plane runner under %s\n' "${capsule}"
    exit 0
  fi
  rig_warn "audit-i4a: I4a is NOT holding under ${capsule}"
  exit 1
fi

# ── positive control (VA-2) ──────────────────────────────────────────────────

planted="${capsule}/verify.sh"
[ -e "${planted}" ] && rig_die "positive control needs a clean capsule: ${planted} already exists"

# The plant is the ORDINARY REFLEX, spelled out: `cp` the runner into the
# capsule dir at provisioning time. Not a contrived payload — the thing a shell
# rig does by habit, which is exactly why it is the thing worth catching.
cp -- "${RUNNERS}/verify.sh" "${planted}"
rig_assert_fails 'planted: the audit REFUSES a runner copied into the writable root' \
  audit

rm -f -- "${planted}"
rig_assert 'unplanted: the audit PASSES on the same capsule' \
  audit

rig_assert_done 'audit-i4a positive control'
