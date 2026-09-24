#!/usr/bin/env bash
# capsule/worker-agent.sh — the REAL AGENT worker (P-C1b, DEC-109 opt-in).
#
#   usage: worker-agent.sh <task-file>          (runs INSIDE the sandbox)
#
# The sibling of `worker-stub.sh` and deliberately its twin at the boundary:
# same doorbell, same result ref, same bundle, same fail-closed env reads, same
# ring-last ordering. Everything that crosses the capsule boundary is IDENTICAL,
# because P-C1b's claim is about the capsule model and not about a second
# protocol. What differs is the middle — where the stub makes a scripted commit,
# this invokes an LLM and lets it work.
#
# `--stub` is the rig default and `--agent` is explicit opt-in (DEC-109): only
# P-C1 needs an LLM, everything in P-C2 and P-C3 is scripted by DQ-2 mandate,
# and a probe "contained" by a worker politely declining is void.
#
# ── I1a: total freedom inside ────────────────────────────────────────────────
#
# The agent may commit, amend, rebase and iterate however it likes. The boundary
# is where the constraint lives, not the workspace. Nothing here is a permission
# check, and nothing here reviews the agent's work — the pipeline's four stages
# do that trusted-side, after the ring.
#
# ── the usage JSON leaves over STDOUT, and that is deliberate (F-P06-5) ──────
#
# Token usage is the one measurement with no trusted-side source: the harness
# that counts tokens runs in the capsule, which is what EX-3 requires. So the
# next best thing — it is STREAMED to the parent rather than written to a file
# in the capsule's rw root. The parent holds the only copy from the moment it is
# emitted and the capsule cannot revise it afterwards. It is recorded, never
# asserted: no stage, token or outcome reads it (I5 holds).
set -euo pipefail

INNER_CAPSULE=/capsule
CLONE="${INNER_CAPSULE}/repo"

# The marker the control plane greps its captured stdout for. One literal, named
# once, because the emitter and the reader are in different trust domains and a
# drifted copy would silently yield "no usage recorded" rather than an error.
USAGE_MARKER='p-c1b-usage:'

die() {
  printf 'worker-agent: %s\n' "$*" >&2
  exit 1
}

# Every name that crosses the boundary comes from the CONTROL PLANE, over the
# sandbox env — this script runs inside the sandbox and cannot source the
# library that defines them. FAIL CLOSED rather than defaulting (F-P02-6); the
# bundle path is also RT-4/F-6 stated positively, since a capsule free to choose
# its own harvest path would choose a symlink.
DOORBELL="${INNER_CAPSULE}/${RIG_DOORBELL:?worker-agent: RIG_DOORBELL not set — the control plane names the doorbell}"
RESULT_REF="${RIG_RESULT_REF:?worker-agent: RIG_RESULT_REF not set — the control plane names the result ref}"
BUNDLE="${INNER_CAPSULE}/${RIG_BUNDLE:?worker-agent: RIG_BUNDLE not set — the control plane names the bundle path}"

task_file=${1:?worker-agent: no task file — the control plane names the phase}

[ -d "${CLONE}" ] || die "nothing provisioned at ${CLONE} — run provision.sh first"
[ -r "${task_file}" ] || die "task file unreadable: ${task_file}"

cd -- "${CLONE}"

base_oid=$(git rev-parse HEAD)

# ── the phase ────────────────────────────────────────────────────────────────
#
# `--output-format json` for the usage block; `--dangerously-skip-permissions`
# because a headless agent that cannot edit cannot execute a phase. That flag is
# a property of the HARNESS inside an already-confined capsule, not a widening
# of the sandbox: the confinement is the bwrap profile, where the canonical repo
# is absent, the credentials are absent, and the rw root is /capsule and nothing
# else. Granting the agent free rein WITHIN that is precisely the capsule
# model's claim — that confinement need not be re-litigated per tool. Its own
# help says "recommended only for sandboxes", which is what this is.
#
# The flag name was READ FROM `claude --help`, not recalled: this build has
# `--dangerously-skip-permissions` and no `--permission-mode`.
#
# Status is DATA. An agent that fails, refuses, or times out must still flow
# into an ordinary pipeline outcome rather than dying here, because "the agent
# did not finish" is a result about the capsule model and not a rig error.
agent_status=0
usage_json=$(claude -p \
  --output-format json \
  --dangerously-skip-permissions \
  "$(cat -- "${task_file}")" 2>/dev/null) || agent_status=$?

# Emitted whatever happened — a failed run still has a cost, and D-P06-2's
# "any prior attempt is disclosed and its usage recorded" needs the number to
# exist even when the phase did not reach green.
printf '%s %s\n' "${USAGE_MARKER}" "$(printf '%s' "${usage_json}" | tr -d '\n')"
printf 'worker-agent: claude exit %s\n' "${agent_status}" >&2

# ── did the AGENT commit? ────────────────────────────────────────────────────
#
# Recorded, not enforced. "Does an agent in a capsule complete the ritual" is
# one of the things P-C1b is here to find out, and a worker that quietly
# committed on the agent's behalf would answer it with its own behaviour. So the
# fact is emitted first, and only then is the residue swept up — otherwise the
# pipeline has nothing to harvest and the run measures nothing at all.
agent_committed=no
[ "$(git rev-parse HEAD)" = "${base_oid}" ] || agent_committed=yes
tree_dirty=no
[ -z "$(git status --porcelain)" ] || tree_dirty=yes

printf 'p-c1b-ritual: agent-committed=%s tree-dirty=%s\n' "${agent_committed}" "${tree_dirty}"

if [ "${tree_dirty}" = yes ]; then
  git add -A
  git commit --quiet -m '[add] capsule agent residue — uncommitted work swept by the worker'
fi

[ "$(git rev-parse HEAD)" = "${base_oid}" ] &&
  die "the agent produced no commit and left no residue — nothing to harvest"

# The result the control plane will harvest. A REF the capsule owns, at a name
# the control plane chose — the capsule never names the harvest path, and the
# ref is read exactly once and pinned to an OID trusted-side (RT-5).
git update-ref "${RESULT_REF}" HEAD

# M-B's artifact, written BEFORE the ring — the doorbell is the signal that the
# bundle is complete. One worker serves both mechanisms so the matrix loops
# without branching; M-A ignores this file entirely.
git bundle create --quiet "${BUNDLE}" "${RESULT_REF}" 2>/dev/null ||
  die "could not write the bundle at ${BUNDLE}"

# Ring. The doorbell carries NO AUTHORITY: content is never read, so what goes
# in the file is irrelevant by construction rather than by convention.
printf 'capsule=%s oid=%s\n' "${INNER_CAPSULE}" "$(git rev-parse HEAD)" >"${DOORBELL}"

printf 'worker-agent: %s at %s\n' "${RESULT_REF}" "$(git rev-parse HEAD)"
