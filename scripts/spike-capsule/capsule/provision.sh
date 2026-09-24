#!/usr/bin/env bash
# capsule/provision.sh — clone the contracted base INSIDE the sandbox (EX-8).
#
#   usage: provision.sh <base-oid>            (runs INSIDE the sandbox)
#
# Runs from /rig, ro-bound from outside the capsule's writable root (I4a). It
# is a CONTROL-PLANE script that happens to execute in the capsule, not a
# capsule script — the distinction is the mount posture, and it is the whole of
# why the verdict means anything.
#
# ── the provisioning mechanism, pinned against this environment (EX-8) ───────
#
# probe-specs § P-C1 step 2 provisions with `direnv allow`. **`nix` and
# `direnv` are ABSENT in this jail** — verified at planning time; `/nix/store`,
# `bwrap`, `node`, `npm` and `claude` are present. So the toolchain reaches the
# capsule by RO-BINDING `/nix/store` and setting PATH, which is what the P-C2
# profile already specifies, and there is no `direnv allow` step because there
# is no binary to run it.
#
# That divergence is RECORDED, not silently worked around: it is an environment
# fact, and P-C1a records the design's "nix env ready" step `n/a` WITH ITS
# REASON rather than dropping it from the step list (PHASE-04 EX-4). RFC-025
# prose is NOT edited — a slice non-goal.
set -euo pipefail

INNER_CAPSULE=/capsule
INNER_SOURCE=/source
CLONE="${INNER_CAPSULE}/repo"

die() {
  printf 'provision: %s\n' "$*" >&2
  exit 1
}

base=${1:?usage: provision.sh <base-oid>}

[ -d "${INNER_SOURCE}" ] || die "no contracted source at ${INNER_SOURCE} — pass --source"
[ -d "${INNER_CAPSULE}" ] || die "not running inside a capsule (${INNER_CAPSULE} absent)"
[ -e "${CLONE}" ] && die "already provisioned: ${CLONE}"

# The capsule's own identity. Never the host's — a capsule that adopted the
# control plane's git identity would author commits indistinguishable from it.
#
# PINNED ON THE CLONE ITSELF, and that is a COST fix as much as a correctness
# one (F-P04-7, P-C1a). `git clone -c` takes effect after init and before the
# fetch, so it covers the clone's own reflog writes — which need a committer
# ident like any other. Configured only afterwards, git had to GUESS one, and
# guessing means resolving the hostname: inside `--unshare-all --share-net` that
# is a DNS query for an unshared UTS name, and it blocks until the resolver
# gives up. Measured at ~3.9s PER IDENT-NEEDING GIT OPERATION against 40ms with
# the ident pinned. Every capsule paid it twice — once here, once in the verify
# capsule — so P-C1a's headline number was mostly a resolver timeout.
CAPSULE_IDENT_NAME='capsule worker'
CAPSULE_IDENT_EMAIL='worker@spike-capsule.invalid'

# `--no-hardlinks` is not an optimisation knob (fixtures.md F4): a local clone
# hardlinks object files by default, so the capsule and the source would SHARE
# them and a hostile capsule corrupting a shared object corrupts the source. It
# is the difference between a copy and an alias. The ro bind makes the write
# fail rather than corrupt — belt and braces, and the belt is the one that
# survives someone making /source writable.
git clone --no-hardlinks --quiet \
  -c "user.name=${CAPSULE_IDENT_NAME}" \
  -c "user.email=${CAPSULE_IDENT_EMAIL}" \
  -- "${INNER_SOURCE}" "${CLONE}"
git -C "${CLONE}" switch --detach --quiet "${base}"

# The identity is asserted, not assumed: `-c` persisting into the new repo's
# config is what makes every LATER capsule git operation cheap too, and a git
# that stopped doing so would restore the timeout silently.
[ "$(git -C "${CLONE}" config user.email)" = "${CAPSULE_IDENT_EMAIL}" ] ||
  die "capsule identity did not persist into ${CLONE} — every git op will guess and stall"

# No remotes. The capsule has nowhere to push; harvest is a control-plane pull
# from the capsule (§ 5.2), never a capsule-initiated write outward.
git -C "${CLONE}" remote remove origin 2>/dev/null || true

printf 'provision: %s at %s\n' "${CLONE}" "$(git -C "${CLONE}" rev-parse HEAD)"
