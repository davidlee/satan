#!/usr/bin/env bash
# Shared library for the SL-241 capsule spike rig. SOURCED, never executed.
#
# Disposable scaffolding: the rig builds evidence for RFC-025's capsule
# authority model and nothing in it migrates into dispatch machinery
# (slice-241.md § Scope). Entry points set their own shell options; a library
# does not impose them on its caller.

# ── diagnostics ──────────────────────────────────────────────────────────────

# Exit codes are distinguishable on purpose: an I6 refusal must not read as a
# usage error in a matrix cell's recorded outcome.
#
# The bound codes are the same discipline one layer down. They are STATUSES,
# not refusal tokens: `verify-timeout` and `harvest/resource-cap` are computed
# TRUSTED-SIDE by PHASE-03's pipeline (I5), and nothing here authors them.
RIG_EXIT_USAGE=2
RIG_EXIT_GUARD=3
# Consumed by sourcing entry points, not by this library — a library that used
# every constant it published would not be a library.
# shellcheck disable=SC2034
RIG_EXIT_DISK=4     # the disk cap bit (PHASE-03 maps it to `harvest/resource-cap`)
# shellcheck disable=SC2034
RIG_EXIT_SANDBOX=5  # the sandbox itself failed to start — NOT a verdict on the capsule
RIG_EXIT_TIMEOUT=124 # `timeout`'s own code, propagated verbatim rather than renamed
# shellcheck disable=SC2034
RIG_EXIT_DEFECT=6   # a token outside the closed vocabulary — a RIG defect, NOT a result
# The shell's own two "I could not run that" codes, named because the rig now
# keys on them: a tool it cannot INVOKE is a defect of the rig, never a verdict
# on the capsule (F-P05-29).
# shellcheck disable=SC2034
RIG_EXIT_NOEXEC=126  # found, not executable
# shellcheck disable=SC2034
RIG_EXIT_NOTFOUND=127 # not found — or its ELF interpreter is not

rig_warn() { printf 'rig: %s\n' "$*" >&2; }
rig_die() { rig_warn "$*"; exit "${RIG_EXIT_USAGE}"; }

# ── path resolution (T3 / EX-8) ──────────────────────────────────────────────

# Canonicalise a path WITHOUT requiring it to exist (`-m`): the capsule root is
# created by the rig, so it does not exist the first time the guard inspects it.
# Resolution MUST precede every comparison — comparing an unresolved string is
# not a guard (mem.pattern.safety.resolve-every-ref-before-pure-compare).
rig_resolve() {
  realpath -m -- "${1:?rig_resolve: path required}"
}

# The capsule / fixture root. A rig PARAMETER, never a hardcoded path (EX-8).
# Default `~/capsules` — out of repo by operator ruling, which makes a
# mis-resolved root less likely and does NOT make the I6 guard optional.
rig_capsule_root() {
  rig_resolve "${SPIKE_CAPSULE_ROOT:-${HOME}/capsules}"
}

# The repository the rig itself lives in — I6's subject. Derived from this
# library's own location, so it is correct however the rig is invoked.
rig_repo_root() {
  local here top
  here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return 1
  top=$(git -C "${here}" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "${top}" ] || return 1
  rig_resolve "${top}"
}

# ── I6: the rig cannot touch the real repository ─────────────────────────────

# guard_not_real_repo <path>
#
# Refuses when <path> resolves to this repository's root, or to anything inside
# it. Runs at EVERY entry point BEFORE any provisioning — a guard that runs late
# is not a guard (design § 5.5 I6).
#
# EX-2 mandates equality; this refuses CONTAINMENT too (D-P01-2). Equality alone
# leaves `<repo>/scripts/spike-capsule/fixtures` open, and a mutator running
# there is the failure I6 exists to prevent — the criterion's own justification,
# not a widening of it.
#
# Fails CLOSED: a guard that cannot determine what it is protecting refuses.
guard_not_real_repo() {
  local candidate repo
  candidate=$(rig_resolve "${1:?guard_not_real_repo: path required}")
  repo=$(rig_repo_root) || {
    rig_warn "I6: cannot resolve this repository's root — refusing (fail closed)"
    exit "${RIG_EXIT_GUARD}"
  }
  # The `#` strip is a prefix test on RESOLVED paths with the separator
  # included, so a sibling (`<repo>-other`) is not swallowed. `"${repo}"` is
  # quoted inside the expansion so a glob character in the path is a literal.
  if [ "${candidate}" = "${repo}" ] || [ "${candidate#"${repo}"/}" != "${candidate}" ]; then
    rig_warn "I6: refusing — ${candidate} is the real repository (${repo}), or inside it"
    exit "${RIG_EXIT_GUARD}"
  fi
}

# The first action of EVERY entry point — `rig` and every control script alike.
# Resolves the capsule root, THEN guards it: resolution before comparison, or
# the guard compares an unresolved string.
#
# Publishes RIG_ROOT rather than printing it, and that is load-bearing. A guard
# that refuses by `exit` must run in the ENTRY SHELL: inside `$( … )` the exit
# ends only the subshell, and `set -e` does not propagate a failed substitution
# in argument position — so `dispatch … "$(rig_enter)"` printed the refusal and
# then dispatched anyway, with an empty root. Observed during T1 (F-P01-1).
rig_enter() {
  # Tripwire for exactly that. The guard probe subshells `guard_not_real_repo`
  # on purpose; `rig_enter` is the entry wrapper and must never be subshelled.
  if [ "${BASHPID}" != "$$" ]; then
    rig_warn "I6: rig_enter called from a subshell — a refusal could not propagate"
    exit "${RIG_EXIT_GUARD}"
  fi
  RIG_ROOT=$(rig_capsule_root)
  guard_not_real_repo "${RIG_ROOT}"
}

# ── the rig's evidence-file shape ────────────────────────────────────────────

# rig_field <file> <key> — the first `key=value` line's value, empty if absent.
#
# Every file the rig writes for a later reader is one fact per line in this
# shape: the run contract, H14's three doorbell legs, H11's payload record. The
# `sed` had been spelled out three times before it was named, which is three
# places for the quoting to drift and one class of `key2=` prefix collision to
# be fixed in only some of them.
#
# Distinct from `declaration_field` below, which parses `key:  value` — a
# DECLARED surface authored by a human, not evidence written by a run.
rig_field() { sed -n "s/^$2=//p" -- "$1" | head -1; }

# ── the interpretation-surface declaration ───────────────────────────────────

# The declaration is default-deny and read BY FIELD (DEC-099). `verify:` is the
# one place project execution is wanted, and it runs inside the verify capsule;
# `exec:` names the tokens the DQ-4 audit holds the trusted side to.
#
# Here rather than in the pipeline because it has two consumers with nothing
# else in common: the pipeline reads `verify:`, and `control/audit-dq4.sh` reads
# `exec:`. An audit that re-derived the parser could disagree with the pipeline
# about what the declaration says, which is the one disagreement neither would
# report.
declaration_field() {
  local file=$1 field=$2
  sed -n "s/^${field}:[[:space:]]*//p" "${file}" | head -1
}

# ── the doorbell (§ 5.4, EX-5) ───────────────────────────────────────────────

# The file the worker touches inside the capsule's rw root. Named once, because
# both sides of the doorbell refer to it and a drifting literal would make a
# lost ring indistinguishable from a mistyped one.
RIG_DOORBELL=result-ready

# ── the other two names that cross the boundary ──────────────────────────────
#
# Same discipline as the doorbell, for the same reason (F-P02-6): the ringer,
# the waiter and the probe each carrying their own literal is a join nothing
# checks. All three names are chosen HERE by the control plane and passed in
# over `--setenv`, and the capsule reads them FAIL-CLOSED.
#
# It is also the RT-4/F-6 requirement stated positively: **the capsule never
# names the harvest path.** A capsule that chose its own bundle location would
# choose a symlink.
# shellcheck disable=SC2034
RIG_RESULT_REF=refs/heads/capsule-result
# shellcheck disable=SC2034
RIG_BUNDLE=result.bundle

# Where the harvested result lands INSIDE the quarantine. Under `refs/heads/`
# deliberately: the verify capsule clones out of the quarantine, and `git clone`
# fetches `refs/heads/*` — a result parked under a private namespace would be
# invisible to the clone and stage 3 would verify the base instead of the
# result, silently. Quarantine is disposable, so a branch there costs nothing.
# shellcheck disable=SC2034
RIG_QUARANTINE_REF=refs/heads/quarantine-result

# ── the bundle-hygiene mutators (EX-3's four legs) ──────────────────────────
#
# Shared rather than probe-local: `selftest_bundle` (A-1's bundle section) and
# P-C3's H13 attack the SAME artifact at the same path, and two copies would be
# two places for the attack to drift from the boundary it is measuring. Each
# takes the bundle path and nothing else, so a caller supplies its own scenario.
#
# The fourth leg — the size cap — is deliberately NOT here. It is a THRESHOLD
# (`RIG_BUNDLE_CAP`), not a mutation of the artifact: the leg bites on an honest
# bundle, which is the whole point of capping below the real size rather than
# forging an oversized file.

# A symlink at the bundle path is RT-4's first attack verbatim. The target is
# deliberately NONEXISTENT: that is the case which proves the leg ORDER, since
# an `-e` test would report it as merely absent and score the attack as an
# ordinary missing file.
bundle_symlink() {
  rm -f -- "$1"
  ln -s /nonexistent/target "$1"
}
bundle_remove() { rm -f -- "$1"; }
bundle_truncate() { printf 'PACK' >"$1"; }
bundle_leave() { :; }

# ── the doctrine binary the rig calls (conform leg 2) ────────────────────────
#
# The documented ladder, not a bare `doctrine`: the corpus verbs must come from
# a build that carries this tree's rules. `$DOCTRINE_BIN` first (the dispatch
# forward), then this repo's dev build, then PATH.
#
# EVERY RUNG IS PROVEN TO RUN, NOT MERELY TO EXIST — `[ -x ]` was the bug
# (F-P05-29). The executable bit says nothing about whether the binary can
# START: a co-agent's build of `target/debug/doctrine` against a nix store this
# jail does not mount is `-x` and exits 127 on every call. The ladder took that
# rung and never reached the working one bwrap already provides on PATH
# (`flake.nix` ro-binds the crane build at `~/.cargo/bin/doctrine`). One exec
# per rung, once per pipeline run, is the whole cost of not believing it.
rig_doctrine_runs() {
  [ -n "${1:-}" ] && "$1" --version >/dev/null 2>&1
}

rig_doctrine_bin() {
  local repo
  if rig_doctrine_runs "${DOCTRINE_BIN:-}"; then
    printf '%s' "${DOCTRINE_BIN}"
    return 0
  fi
  if repo=$(rig_repo_root) && rig_doctrine_runs "${repo}/target/debug/doctrine"; then
    printf '%s' "${repo}/target/debug/doctrine"
    return 0
  fi
  # PATH, unprobed and deliberately so: the last rung is what conform leg 2
  # then RAISES A DEFECT on if it too cannot be invoked. Probing it here would
  # only move the same refusal to a place with less to say about it.
  printf 'doctrine'
}

# rig_wait_doorbell <capsule> <deadline-secs> <interval-secs>
#
# Blocks until <capsule> rings, printing the capsule it was ASKED about.
# Returns RIG_EXIT_TIMEOUT at the deadline.
#
# The doorbell carries NO AUTHORITY, and each clause below is one of § 5.4's
# four properties made mechanical rather than commented:
#
#   content is never read      — only `[ -e ]`. A ring naming another capsule
#                                cannot name anything, because nothing parses it (I5).
#   identity from the caller   — the capsule echoed back is the ARGUMENT, which
#                                the control plane chose; never a value from the file.
#   loss degrades to polling   — an interval and a WALL-CLOCK DEADLINE, so a lost
#                                ring costs latency, not correctness. It never hangs.
#   duplication is a no-op     — existence is idempotent; a second ring is the same
#                                observation, and the pipeline is content-addressed (I2).
#
# It is a lib function rather than a control script because PHASE-03's pipeline
# is its only other consumer; the design names no file for it.
rig_wait_doorbell() {
  local capsule=${1:?rig_wait_doorbell: capsule required}
  local deadline=${2:?rig_wait_doorbell: deadline required}
  local interval=${3:?rig_wait_doorbell: interval required}
  local bell="${capsule}/${RIG_DOORBELL}" end
  end=$(($(date +%s) + deadline))
  while [ "$(date +%s)" -lt "${end}" ]; do
    if [ -e "${bell}" ]; then
      printf '%s\n' "${capsule}"
      return 0
    fi
    sleep "${interval}"
  done
  rig_warn "doorbell: no ring from ${capsule} within ${deadline}s — polling deadline reached"
  return "${RIG_EXIT_TIMEOUT}"
}

# ── assertions ───────────────────────────────────────────────────────────────
#
# Failures ACCUMULATE rather than exiting at the first, so one run reports every
# broken invariant instead of one per rebuild. `rig_assert_done` is the gate.

RIG_ASSERT_FAILURES=0

rig_assert() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  ok    %s\n' "${desc}"
  else
    printf '  FAIL  %s\n' "${desc}" >&2
    RIG_ASSERT_FAILURES=$((RIG_ASSERT_FAILURES + 1))
  fi
}

# The inverse: assert the command REFUSES. Every positive control needs this —
# "the audit fails when a payload is planted" is the half of the pair that
# makes the other half mean anything.
#
# It exists because the obvious spelling does not work: `rig_assert '…' ! audit`
# passes `!` as the COMMAND NAME (it is a shell keyword, not a program), so the
# assertion reds on the invocation and never scores the refusal at all. Observed
# on this phase's own I4a positive control — the audit was correct throughout.
rig_assert_fails() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  FAIL  %s — expected refusal, got success\n' "${desc}" >&2
    RIG_ASSERT_FAILURES=$((RIG_ASSERT_FAILURES + 1))
  else
    printf '  ok    %s\n' "${desc}"
  fi
}

rig_assert_eq() {
  local desc=$1 want=$2 got=$3
  if [ "${want}" = "${got}" ]; then
    printf '  ok    %s\n' "${desc}"
  else
    printf '  FAIL  %s — want %s, got %s\n' "${desc}" "${want}" "${got}" >&2
    RIG_ASSERT_FAILURES=$((RIG_ASSERT_FAILURES + 1))
  fi
}

rig_assert_done() {
  local what=$1
  if [ "${RIG_ASSERT_FAILURES}" -ne 0 ]; then
    rig_warn "${what}: ${RIG_ASSERT_FAILURES} assertion(s) failed"
    exit 1
  fi
  printf '%s: all assertions hold\n' "${what}"
}
