#!/usr/bin/env bash
# Shared observation helpers for the probes that assert INSIDE the sandbox.
# SOURCED, never executed. Requires `lib/common.sh` already sourced and
# `rig_enter` already run (RIG_ROOT published).
#
# Extracted from PHASE-02's `probe-capsule.sh` when PHASE-04's `probe-c2.sh`
# needed the same observations. Extraction rather than a second copy is the
# whole point: `absent_inside` in particular encodes a correctness rule that was
# WRONG in its first two writings (F-P02-1, then F-P03-2), and a probe carrying
# its own copy would carry its own version of that rule.
#
# One capsule per consumer, named ONCE:
#
#   sandbox_probe_bind "${RIG_ROOT}/capsules/probe-cNN"
#   reset_capsule
#   rig_assert '…' in_sandbox -- test -d /nix/store

# The sandbox binary, single-sourced here rather than re-derived per probe
# (STD-001). Self-locating from this library's own path, so it is correct
# however the consumer was invoked.
SANDBOX=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/capsule/sandbox.sh

SANDBOX_PROBE_CAPSULE=""

# Bind the capsule every helper below observes. Guards it as a STATEMENT: this
# calls `guard_not_real_repo`, which refuses by `exit`, and a caller forced into
# `$( … )` to read a return value would lose that refusal (F-P01-1).
sandbox_probe_bind() {
  SANDBOX_PROBE_CAPSULE=$(rig_resolve "${1:?sandbox_probe_bind: capsule required}")
  guard_not_real_repo "${SANDBOX_PROBE_CAPSULE}"
  [ -x "${SANDBOX}" ] || rig_die "missing runner: ${SANDBOX}"
}

# The disk bound is CUMULATIVE over the capsule tree, so residue from one case
# is a real input to the next: the first run of PHASE-02's bounds section
# reddened its own positive control because the oversized case's file was still
# there. The reset is the fix; the cumulative behaviour is correct and stays.
reset_capsule() {
  rm -rf -- "${SANDBOX_PROBE_CAPSULE}"
  mkdir -p -- "${SANDBOX_PROBE_CAPSULE}"
}

# Run a command inside the sandbox, capturing its status without tripping -e.
# The capsule's stdout is UNTRUSTED TEXT (I5) — read only to assert on an
# observable the probe itself asked for, never parsed for a verdict.
in_sandbox() {
  local status=0
  "${SANDBOX}" --capsule "${SANDBOX_PROBE_CAPSULE}" "$@" || status=$?
  return "${status}"
}

# The status itself, when an assertion needs to tell one nonzero from another —
# a script's own refusal (1) from an exec that never happened (RIG_EXIT_SANDBOX).
sandbox_status() {
  local status=0
  in_sandbox "$@" >/dev/null 2>&1 || status=$?
  printf '%s' "${status}"
}

# An ABSENT-not-ro assertion is only worth its green if its subject is VISIBLE
# TO THE PROBE. `test ! -e` against a path the probe cannot see either passes
# for the wrong reason and says nothing about the CAPSULE profile — F-P02-1's
# shape, and it was live on two legs of PHASE-02's posture section until
# F-P03-2. So: prove the subject reachable OUTSIDE the capsule, then assert it
# does not resolve INSIDE. A subject that is not reachable outside is recorded
# `n/a` WITH ITS REASON — a legal outcome; a silent green is not.
#
# ENVIRONMENT-CONDITIONAL, and deliberately so (PHASE-01 EX-9's discipline).
# `~/.ssh` exists on the host but is hidden by the OUTER bubblewrap jail, so
# in-jail this leg is `n/a` — the jail is doing the hiding, not the capsule, and
# the leg would pass with no capsule sandbox at all. On a HOST run the subject
# is visible and the same leg becomes load-bearing without an edit. That
# self-adaptation is the point: the gate is reachability from where the probe
# stands, never a hardcoded verdict about the path.
absent_inside() {
  local desc=$1 path=$2
  if [ ! -e "${path}" ]; then
    printf '  n/a   %s — subject not visible from here; the capsule is not what hides it\n' "${desc}"
    return 0
  fi
  rig_assert "${desc}" in_sandbox -- test '!' -e "${path}"
}

# The credential-helper leg needs two positive controls of its own, for two
# distinct vacuity routes (F-P03-2):
#
#   1. `git` might not be on the sandbox's allowlist at all, in which case the
#      substitution comes back empty and `[ -z … ]` is true for the wrong
#      reason. RESOLVES is not RUNS (F-P02-2), and neither is ABSENT.
#   2. NO helper is configured on this host, so `[ -z … ]` is true UNCONFINED.
#      Without a control the leg cannot tell "the profile hides the helper"
#      from "there was never a helper" — it is the DQ-3 trap wearing a
#      credential costume.
#
# Control 2 runs on the host against a config THIS PROBE OWNS; the operator's
# real ~/.gitconfig is never written. It exercises the global cascade, which is
# the route ~/.gitconfig itself takes.
probe_credential_helper() {
  rig_assert 'positive control: git EXECUTES inside the sandbox' \
    in_sandbox -- git --version

  local fake="${RIG_ROOT}/probes/credential-helper-control"
  mkdir -p -- "$(dirname -- "${fake}")"
  rm -f -- "${fake}"
  git config --file "${fake}" credential.helper 'store --file=/dev/null'
  # The substitution runs under the probe's own GIT_CONFIG_GLOBAL, so it is
  # deliberately not expanded here either.
  # shellcheck disable=SC2016
  rig_assert 'positive control: the check DETECTS a helper when one is present' \
    env GIT_CONFIG_GLOBAL="${fake}" \
    sh -c '[ -n "$(git config --get credential.helper)" ]'

  # And none crosses. ~/.gitconfig is not bound, and `--clearenv` drops
  # GIT_CONFIG_GLOBAL — neither route reaches inside. The substitution must run
  # INSIDE, so it is deliberately not expanded here.
  # shellcheck disable=SC2016
  rig_assert 'ABSENT: no git credential helper on the effective cascade' \
    in_sandbox -- sh -c '[ -z "$(git config --get credential.helper || true)" ]'
}
