#!/usr/bin/env bash
# fixture-heavy.sh — provision the HEAVY fixture (PHASE-01 T4, EX-3).
#
# A `git clone --no-hardlinks` of this repository at a contracted base B, with
# remotes stripped and no credential helper. Carries P-C1's cost baseline, the
# verify-capsule leg, and the H11/H12 instantiations.
#
#   usage: fixture-heavy.sh [--base <rev>] [--force]
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# Layout — the declaration is a SIBLING of the clone, never inside it:
#
#   $SPIKE_CAPSULE_ROOT/fixtures/heavy/
#     repo/                        the clone, at exactly B
#     interpretation-surface.txt   copied from the rig's authored source
#
# That placement is the F-5 provenance invariant made structural: the base
# fixture cannot mount the substitution attack because there is nothing inside
# the clone to substitute. PHASE-05 manufactures the exposure deliberately.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

base_rev=HEAD
force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      base_rev=${2:?--base needs a rev}
      shift
      ;;
    --force) force=1 ;;
    -h | --help)
      sed -n '2,20p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) rig_die "unknown argument: $1" ;;
  esac
  shift
done

# I6 — FIRST, before any provisioning. A guard that runs late is not a guard.
rig_enter

src=$(rig_repo_root) || rig_die "cannot resolve the source repository"
base=$(git -C "${src}" rev-parse --verify "${base_rev}^{commit}" 2>/dev/null) ||
  rig_die "not a commit in ${src}: ${base_rev}"

fixture="${RIG_ROOT}/fixtures/heavy"
clone="${fixture}/repo"

# Belt: the destination is a mutation target, so guard it on its own rather than
# trusting that it inherited RIG_ROOT's verdict.
guard_not_real_repo "${clone}"

if [ -e "${clone}" ]; then
  [ "${force}" -eq 1 ] || rig_die "fixture exists: ${clone} — pass --force to rebuild"
  rm -rf -- "${clone}"
fi

mkdir -p -- "${fixture}"

# --no-hardlinks is not an optimisation knob. A local clone hardlinks object
# files by default, so the fixture and the real repository would SHARE them —
# a hostile fixture corrupting a shared object corrupts canonical. This flag is
# the difference between a copy and an alias.
printf 'cloning %s → %s (no hardlinks, full history)\n' "${src}" "${clone}"
git clone --no-hardlinks --quiet -- "${src}" "${clone}"
git -C "${clone}" switch --detach --quiet "${base}"

# Strip every remote: the fixture must not be able to reach canonical at all.
while read -r remote; do
  [ -n "${remote}" ] || continue
  git -C "${clone}" remote remove "${remote}"
done < <(git -C "${clone}" remote)

# `clone` never copies config, but the host cascade (system/global) still
# applies. Report what the host carried before neutralising it, so the
# assertion below is checking the neutralisation rather than passing vacuously.
host_helper=$(git -C "${src}" config --get-all credential.helper 2>/dev/null | tr '\n' ' ' || true)
if [ -n "${host_helper% }" ]; then
  rig_warn "host git config carries credential.helper: ${host_helper}"
  rig_warn "neutralising it in the fixture with a local empty override"
  git -C "${clone}" config --local credential.helper ""
fi

root_commit=$(git -C "${clone}" rev-list --max-parents=0 HEAD | tail -1)
src_count=$(git -C "${src}" rev-list --count "${base}")

printf 'asserting heavy-fixture invariants (EX-3)\n'
rig_assert_eq "HEAD is at exactly B" \
  "${base}" "$(git -C "${clone}" rev-parse HEAD)"
rig_assert_eq "no remotes" \
  "" "$(git -C "${clone}" remote | tr -d '\n')"
rig_assert_eq "no credential.helper (effective, whole config cascade)" \
  "" "$(git -C "${clone}" config --get-all credential.helper 2>/dev/null | tr -d '\n' || true)"
rig_assert_eq "not a shallow clone" \
  "false" "$(git -C "${clone}" rev-parse --is-shallow-repository)"
rig_assert_eq "full history — same commit count as the source at B" \
  "${src_count}" "$(git -C "${clone}" rev-list --count HEAD)"
rig_assert "full history — merge-base reaches the root commit" \
  git -C "${clone}" merge-base --is-ancestor "${root_commit}" HEAD
rig_assert "objects are not shared with the source (no alternates)" \
  test ! -s "${clone}/.git/objects/info/alternates"

decl_src="${RIG_DIR}/fixtures/heavy/interpretation-surface.txt"
[ -f "${decl_src}" ] || rig_die "missing authored declaration: ${decl_src}"
cp -- "${decl_src}" "${fixture}/interpretation-surface.txt"

rig_assert "declaration is present, as a sibling of the clone" \
  test -f "${fixture}/interpretation-surface.txt"
# F-5: nothing inside the clone to substitute. PHASE-05 builds the variant that
# manufactures the exposure; the BASE fixture must not carry it already.
rig_assert "declaration is OUTSIDE the clone (F-5 non-live in the base fixture)" \
  test ! -e "${clone}/interpretation-surface.txt"

rig_assert_done "fixture-heavy"
printf 'heavy fixture ready: %s at %s\n' "${clone}" "${base}"
