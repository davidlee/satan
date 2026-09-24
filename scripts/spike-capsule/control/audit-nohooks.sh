#!/usr/bin/env bash
# audit-nohooks.sh — the census DELETE rows B1–B6, witnessed UNREPRESENTABLE.
#
#   usage: audit-nohooks.sh [--root DIR] [--positive-control]
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# ── two claims, and only one of them is a grep ──────────────────────────────
#
# P-C2's pass condition is "the run used no SubagentStart/WorktreeCreate hooks,
# no marker, no `worker_mode` logic — grep the rig for their absence (the census
# DELETE rows B1–B6 witnessed unrepresentable, not just unused)".
#
# ABSENT FROM THE RIG IS *UNUSED*. It is satisfied by a rig that simply has not
# got round to it, and it is satisfied by a rig that reintroduces the mechanism
# under another name tomorrow. EX-8 asks for something stronger and easy to meet
# cheaply and wrongly: that the mechanism could not be expressed HERE even if
# someone wanted it — that the thing it acted on does not exist in this model.
#
# So each census row below carries TWO legs:
#
#   the token leg     its identifying tokens are absent from the tree (unused)
#   the witness leg   a POSITIVE, checkable fact about this rig that removes the
#                     mechanism's SUBJECT (unrepresentable)
#
# The witness leg is what makes the row worth its green. A negative grep on its
# own proves only that grep ran (`mem_019fa18161f4…`), and a negative grep whose
# structural reason lives in prose proves only that someone wrote prose.
#
# ── the positive control (EX-7) ─────────────────────────────────────────────
#
# `--positive-control` copies the rig to a scratch root, requires the audit to
# PASS there, plants a token, requires it to REFUSE, removes it, and requires it
# to PASS again. Both directions, because an audit that refuses everything is
# exactly as broken as one that refuses nothing. The plant goes to a COPY under
# the capsule root, never into this repository — the I6 guard covers the capsule
# root, and a rig that wrote payloads into its own source tree in a repo shared
# with other agents would be a worse hazard than the one it audits.
#
# ── it excludes itself, deliberately and narrowly ───────────────────────────
#
# This file NAMES the machinery it forbids — that is VT-2's whole point, and an
# audit that scanned itself would refuse on its own subject list. Exactly one
# path is excluded, by basename, and it is stated here rather than discovered:
# hook logic hidden in a file called `audit-nohooks.sh` would evade this audit.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

SELF=$(basename -- "${BASH_SOURCE[0]}")

# ── the forbidden tokens (census B1–B6) ─────────────────────────────────────
#
# The exact machinery the census marks DELETE, so its absence is WITNESSED
# rather than assumed. Named once, consumed by both the audit and the census
# table below (STD-001) — a second copy is how a row starts auditing a token no
# census row claims.
NOHOOK_TOKENS=(
  'SubagentStart'                  # B5 — the stamp hook
  'WorktreeCreate'                 # B3/B5 — the worktree-creation hook
  'worker_mode'                    # B2 — role detection
  'DOCTRINE_WORKER'                # B2 — the worker-on-main env leg
  'state/dispatch/worker'          # B1/B4 — the disk marker
  'marker --stamp-subagent'        # B5 — the stamping verb
  'marker --clear'                 # B4 — the operator recovery verb
  'verify-worker'                  # B6 — the post-spawn ancestor check
)

root="${RIG_DIR}"
positive_control=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      root=${2:?--root needs a directory}
      shift
      ;;
    --positive-control) positive_control=1 ;;
    -h | --help)
      sed -n '2,6p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) rig_die "unknown flag: $1" ;;
    *) rig_die "unexpected argument: $1" ;;
  esac
  shift
done

# I6 — FIRST, as a STATEMENT (F-P01-1).
rig_enter

root=$(rig_resolve "${root}")
[ -d "${root}" ] || rig_die "audit root does not exist: ${root}"

# ── the token leg ───────────────────────────────────────────────────────────
#
# Prints one line per violation; exit 0 when clean. Deliberately silent about
# how it searched — the OUTPUT is the finding, and an empty output with a
# nonzero exit would be the audit lying by omission.
audit() {
  local token violations=0 hit
  for token in "${NOHOOK_TOKENS[@]}"; do
    while IFS= read -r hit; do
      [ -n "${hit}" ] || continue
      printf 'NOHOOKS VIOLATION: %s\n' "${hit}"
      violations=$((violations + 1))
    done < <(
      find "${root}" -type f ! -name "${SELF}" -print0 |
        xargs -0 -r grep -Fn -- "${token}" /dev/null || true
    )
  done
  [ "${violations}" -eq 0 ]
}

# ── the witness leg (EX-8) ──────────────────────────────────────────────────
#
# Each of these is a POSITIVE fact that has to hold for the corresponding
# mechanism to be inexpressible. They are asserted against the REAL rig, not
# against `--root`, because they are claims about the model this rig implements.

SCRATCH="${RIG_ROOT}/probes/c2/audit-nohooks-scratch"
SANDBOX="${RIG_DIR}/capsule/sandbox.sh"

mounts_of() {
  mkdir -p -- "${SCRATCH}/capsule"
  "${SANDBOX}" --capsule "${SCRATCH}/capsule" --print-mounts
}

# B2/B6's shared witness: the capsule's world holds exactly ONE writable path
# and no coordination tree. `--ro-bind` is a distinct token, so counting the
# bare `--bind` lines counts writable binds and only those.
writable_bind_count() { mounts_of | grep -cx -- '--bind' || true; }

# What of this repository reaches the capsule, stated exactly.
#
# The naive witness — "no mount resolves under this repository" — is FALSE here,
# and finding that out is worth more than the assertion would have been: the
# profile ro-binds the control-plane RUNNERS at /rig, and they live under
# `scripts/spike-capsule/capsule/`. That is I4a on purpose (the runner whose exit
# status is the verdict must not sit on a path the capsule can write), and it is
# the one admitted repo-derived mount.
#
# So the witness is the EXACT SET, not an emptiness claim. B2's mechanism needs
# a coordination TREE — a repository the worker could be mis-placed onto — and
# what crosses is one leaf directory of shell scripts with no `.git` under it.
repo_derived_mounts() {
  local repo
  repo=$(rig_repo_root) || return 1
  mounts_of | grep -F -- "${repo}" || true
}

rig_grep() {
  find "${RIG_DIR}" -type f ! -name "${SELF}" -print0 |
    xargs -0 -r grep -Fql -- "$1" /dev/null
}

census() {
  printf '\ncensus DELETE rows — token absent AND subject unrepresentable (EX-8)\n'

  # B1 / B4 — the disk marker, and the operator recovery around it.
  rig_assert_fails 'B1/B4 token: no disk worker marker path anywhere in the rig' \
    rig_grep 'state/dispatch/worker'
  rig_assert_eq 'B1/B4 witness: authority is conferred by the SANDBOX, not by a file' \
    1 "$(writable_bind_count)"
  printf '  reason B1/B4: there is no marker to stamp or clear. Identity here is the\n'
  printf '        OS process the control plane exec-ed into a profile it chose; a file\n'
  printf '        the capsule created inside its one writable bind confers nothing,\n'
  printf '        because no trusted-side check reads one. Recovery is rm -rf, not a\n'
  printf '        marker state to be unwound.\n'

  # B2 — the worker-on-main catch.
  rig_assert_fails 'B2 token: no DOCTRINE_WORKER env leg' rig_grep 'DOCTRINE_WORKER'
  rig_assert_fails 'B2 token: no worker_mode role detection' rig_grep 'worker_mode'
  rig_assert_eq 'B2 witness: exactly ONE repo-derived path crosses — the ro-bound runners' \
    "${RIG_DIR}/capsule" "$(repo_derived_mounts)"
  rig_assert 'B2 witness: and it carries no repository for a worker to be placed on' \
    test '!' -e "${RIG_DIR}/capsule/.git"
  printf '  reason B2: "on main" has no referent. What crosses from this repository is\n'
  printf '        ONE leaf directory of control-plane runners, read-only at /rig, with\n'
  printf '        no .git under it (I4a). There is no coordination tree in the capsule'"'"'s\n'
  printf '        world to be mis-placed onto, so a role-detection rule would have\n'
  printf '        nothing to discriminate between.\n'

  # B3 — the fail-closed marker-absent-linked-worktree rule.
  rig_assert_fails 'B3 token: no WorktreeCreate hook' rig_grep 'WorktreeCreate'
  rig_assert_fails 'B3 witness: the rig never creates a linked worktree' rig_grep 'git worktree'
  rig_assert 'B3 witness: capsules are CLONES — the replacement mechanism is present' \
    rig_grep 'git clone'
  printf '  reason B3: there is no linked worktree and no stamp. A capsule is a clone\n'
  printf '        with its own object store, so the rule that contains an unstamped\n'
  printf '        worker in a shared .git has no shared .git to be about.\n'

  # B5 — the SubagentStart stamp hook, and the hook-choreography class.
  rig_assert_fails 'B5 token: no SubagentStart hook' rig_grep 'SubagentStart'
  rig_assert_fails 'B5 token: no stamping verb' rig_grep 'marker --stamp-subagent'
  rig_assert 'B5 witness: the worker is exec-ed as an OS process under the profile' \
    grep -Fq 'exec timeout' "${RIG_DIR}/capsule/sandbox.sh"
  printf '  reason B5: there is no in-session worker for a hook to fire on. The worker\n'
  printf '        is confined BEFORE its first instruction, by the exec that starts it;\n'
  printf '        a stamp racing that first command is not late here, it is meaningless.\n'

  # B6 — base-by-placement.
  rig_assert_fails 'B6 token: no post-spawn ancestor check' rig_grep 'verify-worker'
  # A FIXED-STRING search for source text, so the `${1:?…}` in it is the needle
  # and must not be expanded here.
  # shellcheck disable=SC2016
  rig_assert 'B6 witness: the base is an explicit ARGUMENT to provisioning' \
    grep -Fq 'base=${1:?usage: provision.sh <base-oid>}' "${RIG_DIR}/capsule/provision.sh"
  rig_assert 'B6 witness: and it is pinned in the work contract' \
    grep -Fq 'base=%s' "${RIG_DIR}/control/pipeline.sh"
  printf '  reason B6: placement cannot determine the base, because the capsule is not\n'
  printf '        placed anywhere — it is created at a base the contract names, and\n'
  printf '        there is no second repository it could have been forked from by\n'
  printf '        accident (B2 witness).\n'
}

# ── run ─────────────────────────────────────────────────────────────────────

if [ "${positive_control}" -eq 0 ]; then
  if audit; then
    printf 'audit-nohooks: clean — none of the census DELETE machinery under %s\n' "${root}"
    census
    rig_assert_done 'audit-nohooks'
    exit 0
  fi
  rig_warn "audit-nohooks: census DELETE machinery is present under ${root}"
  exit 1
fi

# ── positive control (EX-7) ─────────────────────────────────────────────────

control_root="${SCRATCH}/rig"
guard_not_real_repo "${control_root}"
rm -rf -- "${control_root}"
mkdir -p -- "${control_root}"
cp -R -- "${RIG_DIR}/." "${control_root}/"

root="${control_root}"
rig_assert 'unplanted: the audit PASSES on a clean copy of the rig' audit

# The plant is the ORDINARY REGRESSION, spelled out: one role-detection branch
# creeping back into a control script. Not a contrived payload.
planted="${control_root}/control/regression.sh"
cat >"${planted}" <<'PLANT'
#!/usr/bin/env bash
# A role-detection branch, of the kind the census marks DELETE.
if [ "${worker_mode:-}" = worker ]; then exit 3; fi
PLANT

rig_assert_fails 'planted: the audit REFUSES a role-detection branch in a control script' \
  audit

rm -f -- "${planted}"
rig_assert 'unplanted again: the audit PASSES on the same tree' audit

rm -rf -- "${control_root}"
rig_assert_done 'audit-nohooks positive control'
