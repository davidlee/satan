#!/usr/bin/env bash
# probe-smoke.sh — A2, as THREE assertions (EX-7, VA-1).
#
#   usage: probe-smoke.sh                       (dispatched by `rig smoke`)
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# ── why three, and never one ─────────────────────────────────────────────────
#
# **Credential availability and network egress are distinct failure modes and a
# single test conflates them** (A8). `claude -p` failing tells you nothing on
# its own: the capsule may have no route out, or a route and no credential, and
# those have opposite fixes. So:
#
#   1. UNAUTHENTICATED reachability — is there a route out of the sandbox?
#   2. AUTHENTICATED `claude -p 'print OK'` — does the credential survive the
#      nested bwrap into the agent home?
#   3. CAPABILITY — can the agent actually WORK: run a command and change the
#      capsule?
#
# The third leg is the same argument as the first split, taken one step further
# (F-P06-6). Legs 1 and 2 prove the agent's DEPENDENCIES; neither proves it can
# do anything with them. `print OK` needs no tools and writes nothing, and it
# passed green against a profile that made every shell call the harness
# attempted fail EROFS — the harness creates a per-session working directory
# under `$HOME` before the first tool runs, and the profile had the agent home
# read-only. A green smoke certified a profile that could not carry the
# workload, and P-C1b spent a real scored run finding that out.
#
# Run separately, recorded separately. Run EARLY (§ 5.4 step 2), because a
# failure here means the capsule model needs a CREDENTIAL-PROXY DESIGN or a
# profile that cannot host a harness, and both are worth learning on day one
# rather than after the pipeline is built on top of them (R3).
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

SANDBOX="${RIG_DIR}/capsule/sandbox.sh"
SMOKE_TIMEOUT=120
# The capability leg drives a tool-using agent turn rather than a one-shot
# answer, so it gets its own bound rather than loosening the cheap legs' one.
SMOKE_EXEC_TIMEOUT=300
# Written by the agent, read trusted-side. Named once: the prompt and the
# assertion are in different trust domains and a drifted copy would read as
# "the agent could not execute" (STD-001).
SMOKE_PROOF=exec-proof

case "${1:-}" in
  "") ;;
  -h | --help)
    sed -n '2,6p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *) rig_die "unknown argument: $1" ;;
esac

# I6 — FIRST, as a STATEMENT (F-P01-1).
rig_enter

[ -x "${SANDBOX}" ] || rig_die "missing runner: ${SANDBOX}"

capsule="${RIG_ROOT}/capsules/smoke"
guard_not_real_repo "${capsule}"
rm -rf -- "${capsule}"
mkdir -p -- "${capsule}"

report="${RIG_ROOT}/probes/smoke/results.tsv"
mkdir -p -- "$(dirname -- "${report}")"
printf 'assertion\tmechanism\toutcome\tdetail\n' >"${report}"

record() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${report}"
  printf '  %-6s %s — %s\n' "$3" "$1" "$4"
}

# The bound is the caller's, because the three legs are not the same shape: two
# are one round trip and the third is an agent turn with tools in it.
in_sandbox() {
  local secs=${1:?in_sandbox: no timeout}
  shift
  "${SANDBOX}" --capsule "${capsule}" --timeout "${secs}" -- "$@"
}

# The sandbox narrates its own bound accounting on stderr, and these legs
# capture stderr to report WHY a leg failed. Without this the rig's own
# diagnostics land in the evidence file as though the capsule had said them —
# untrusted text and trusted text in one column (I5's whole point).
strip_rig_noise() {
  grep -v '^rig: ' || true
}

printf '\nA2 smoke — THREE assertions, recorded separately (EX-7, VA-1)\n'

# ── 1. unauthenticated reachability ─────────────────────────────────────────
#
# `npm ping` reaches the public registry with no credential of ours. It
# exercises DNS, TLS trust, and egress — the three things the profile has to
# get right for the second assertion to be about credentials at all.
status=0
out=$(in_sandbox "${SMOKE_TIMEOUT}" npm ping 2>&1 | strip_rig_noise) || status=$?
if [ "${status}" -eq 0 ]; then
  record network unauthenticated pass 'npm ping reached the registry'
else
  record network unauthenticated FAIL "npm ping exit ${status}: $(printf '%s' "${out}" | tail -1)"
fi
network_status=${status}

# ── 2. authenticated claude -p ──────────────────────────────────────────────
#
# The credential arrives by the profile's read-only bind of the agent home. A
# failure HERE, with assertion 1 green, is the credential-proxy signal — the
# two are only separable because they were asserted separately.
status=0
out=$(in_sandbox "${SMOKE_TIMEOUT}" claude -p 'print OK' 2>&1 | strip_rig_noise) || status=$?
if [ "${status}" -eq 0 ]; then
  record credential authenticated pass "claude -p answered: $(printf '%s' "${out}" | tr -d '\n' | cut -c1-40)"
else
  record credential authenticated FAIL "claude -p exit ${status}: $(printf '%s' "${out}" | tr -d '\n' | tail -c 120)"
fi
credential_status=${status}

# ── 3. the agent can WORK ───────────────────────────────────────────────────
#
# Asserted by EFFECT, trusted-side, off the filesystem — the agent's own
# account of what it did is never read (I5). The proof content is the kernel
# release, which the agent cannot produce without running something: a leg that
# a file-writing tool could satisfy would pass in exactly the case F-P06-6
# describes, where the agent wrote a correct file and could not execute a line.
# The same shape as EX-3's positive control — a detector is worth nothing until
# it is shown able to report the other answer.
expect=$(uname -r)
proof="${capsule}/${SMOKE_PROOF}"
status=0
out=$(in_sandbox "${SMOKE_EXEC_TIMEOUT}" claude -p --dangerously-skip-permissions \
  "Run this exact shell command and nothing else: uname -r > /capsule/${SMOKE_PROOF}" \
  2>&1 | strip_rig_noise) || status=$?
got=""
if [ -f "${proof}" ]; then got=$(tr -d '\n' <"${proof}"); fi
if [ "${got}" = "${expect}" ]; then
  record execute capability pass "the agent ran a command — the proof file carries ${got}"
  execute_status=0
elif [ -n "${got}" ]; then
  record execute capability FAIL "proof file says ${got}, expected ${expect}"
  execute_status=1
else
  record execute capability FAIL "no proof written — claude exit ${status}: $(printf '%s' "${out}" | tr -d '\n' | tail -c 160)"
  execute_status=1
fi

printf '\nresults: %s\n' "${report}"

# Reported as a COMBINATION, because which legs fail together is the whole
# diagnostic. A green route with a red credential is the R3 finding; both red is
# a profile problem and says nothing about credentials yet; green dependencies
# with a red capability is F-P06-6's signature — a profile that authenticates
# and reaches the network and still cannot host a working agent.
if [ "${network_status}" -ne 0 ] && [ "${credential_status}" -ne 0 ]; then
  rig_warn 'A2: both dependency legs failed — this is a PROFILE fault, not a credential result'
elif [ "${network_status}" -eq 0 ] && [ "${credential_status}" -ne 0 ]; then
  rig_warn 'A2: route out, no credential — the capsule model needs a credential proxy (R3)'
elif [ "${execute_status}" -ne 0 ]; then
  rig_warn 'A2: dependencies green, capability RED — the profile certifies but cannot carry a phase (F-P06-6)'
fi

[ "${network_status}" -eq 0 ] && [ "${credential_status}" -eq 0 ] &&
  [ "${execute_status}" -eq 0 ] || exit 1
printf 'A2: all three assertions hold\n'
