#!/usr/bin/env bash
# capsule/verify.sh — run the declaration's `verify:` command (I4).
#
#   usage: verify.sh -- COMMAND…                (runs INSIDE the sandbox)
#
# ── this script AUTHORS NO VERDICT ───────────────────────────────────────────
#
# I4: the verdict is the sandbox process's exit status **as observed by the
# parent**, never a file the capsule wrote. So this exits with the command's
# status and writes nothing a reader could mistake for a result. The capsule
# may write logs; those are untrusted text, size-capped by the sandbox's disk
# bound, and never parsed for the verdict.
#
# I4a: it enters at /rig — a read-only bind from OUTSIDE /capsule — so no
# script the capsule can write is ever the process whose status is read. A
# capsule that overwrites its own copy of this file changes nothing, which is
# PHASE-05 guard probe (d)'s subject.
#
# The command is passed IN by the control plane, which read it from the
# `verify:` line of the declaration at the contracted base B. This script never
# reads a declaration itself: fail-closed on absence is no defence against
# substitution, so the read has to happen where B is authoritative (F-5).
set -euo pipefail

INNER_CAPSULE=/capsule
CLONE="${INNER_CAPSULE}/repo"

die() {
  printf 'verify: %s\n' "$*" >&2
  exit 1
}

[ "${1:-}" = "--" ] || die 'usage: verify.sh -- COMMAND…'
shift
[ $# -gt 0 ] || die 'no verify command — the control plane passes it from B'
[ -d "${CLONE}" ] || die "nothing provisioned at ${CLONE}"

cd -- "${CLONE}"

# `exec` deliberately: the verify command REPLACES this process, so the status
# the parent reads is the command's own and this script cannot mistranslate it.
exec "$@"
