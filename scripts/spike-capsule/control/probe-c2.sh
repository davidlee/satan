#!/usr/bin/env bash
# control/probe-c2.sh — P-C2, the confinement matrix (EX-5, EX-6, VA-3).
#
#   usage: probe-c2.sh [row…]              (dispatched by `rig c2`)
#          rows: write-floor canonical git-creds api-cred env escape-git resource
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# ── every row is a `bash -c` INSIDE the sandbox (DQ-2) ───────────────────────
#
# Not a request to a worker, and not an inspection of the profile from outside.
# A probe "contained" by a worker politely declining is void, and a probe that
# reads the mount list and reasons about it is asserting on the rig's intent
# rather than on the kernel's behaviour. Note also `mem_019fbd3cb782`: a script's
# shebang interpreter is a mount dependency of the sandbox, so a row that fails
# to EXEC is not a row that passed — the positive controls below are what
# separate those two.
#
# ── every row asserts on a NAMED OBSERVABLE (DQ-3, VA-3) ────────────────────
#
# A sentinel that must not exist, a ref that must not move, a path that must not
# resolve — never on absence of error output. Under nested confinement the OUTER
# jail may be doing the hiding, which reads exactly like the profile working
# (`mem_019fbd70c924`), so every absence assertion goes through `absent_inside`,
# which proves its subject reachable from HERE before asserting it is not
# reachable from INSIDE, and records `n/a` WITH ITS REASON when it is not.
#
# The observable is a COLUMN in the results file, not a comment, and the probe
# refuses to finish if any row left it empty. That is VA-3 made mechanical.
#
# ── what this probe does NOT do ─────────────────────────────────────────────
#
# It does not mint a refusal token. The closed vocabulary (pipeline.sh 5.1) is
# what `assert_outcome` keys off, and the resource row below records STATUSES —
# the sandbox's own `RIG_EXIT_*` — exactly as PHASE-02 does. `verify/resource-cap`
# is not in the closed set and is not created here; see the resource row's note.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-probe.sh
. "${RIG_DIR}/lib/sandbox-probe.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/rows.sh
. "${RIG_DIR}/lib/rows.sh"

ALL_ROWS='write-floor canonical git-creds api-cred env escape-git resource'

rows=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      sed -n '2,7p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) rig_die "unknown flag: $1" ;;
    *)
      case " ${ALL_ROWS} " in
        *" $1 "*) rows+=("$1") ;;
        *) rig_die "unknown row: $1 (${ALL_ROWS})" ;;
      esac
      ;;
  esac
  shift
done
[ "${#rows[@]}" -gt 0 ] || read -r -a rows <<<"${ALL_ROWS}"

# I6 — FIRST, as a STATEMENT (F-P01-1).
rig_enter

CAPSULE="${RIG_ROOT}/capsules/probe-c2"
sandbox_probe_bind "${CAPSULE}"

FIXTURE="${RIG_ROOT}/fixtures/light/repo"
REPORT="${RIG_ROOT}/probes/c2/results.tsv"
SMOKE_REPORT="${RIG_ROOT}/probes/smoke/results.tsv"

REPO=$(rig_repo_root) || rig_die 'cannot resolve this repository root'

# The sentinel every escape row writes. ONE name (STD-001): three rows plant it
# at different targets, and a per-row literal would let a row assert the absence
# of a name no one ever wrote.
SENTINEL='capsule-escape-sentinel'

# ── recording ───────────────────────────────────────────────────────────────

REPORT_COLUMNS=$'row\tobservable\toutcome\tdetail'

# `row_begin` / `row_outcome` / `record_row{,_na}` now live in lib/rows.sh, so
# P-C3 records rows the same way rather than growing a second recorder that
# drifts (PHASE-05 T3). The lift was behaviour-preserving; the shape and the
# reasoning behind it are documented there.
#
# This matrix's columns are `row observable outcome detail`, which is the
# recorder's default: the derived outcome is spliced in third, and the observable
# it refuses to finish without is second.
ROWS_OUTCOME_FIELD=3
ROWS_OBSERVABLE_FIELD=2

# ── shared row plumbing ─────────────────────────────────────────────────────

# Plant the sentinel at every host path a capsule must not reach. The write is
# attempted and its failure is NOT the assertion — inside, `/tmp` is a tmpfs, so
# that write SUCCEEDS and is simply invisible outside. Asserting "the write
# failed" would score that row wrong in both directions.
plant_outside() {
  # The expansion must run INSIDE the sandbox, so it is deliberately not
  # expanded out here.
  # shellcheck disable=SC2016
  in_sandbox -- sh -c '
    for p in "$@"; do : >"$p" 2>/dev/null || true; done
  ' sh "$@" >/dev/null 2>&1 || true
}

# The host paths a sentinel must never appear at, asserted from HERE.
assert_no_sentinel() {
  local target
  for target in "$@"; do
    rig_assert "no sentinel at ${target}" test '!' -e "${target}"
    # If the profile IS broken this probe has just written into a real tree.
    # Removing it is not tidying — leaving it would make the NEXT run pass.
    rm -f -- "${target}" 2>/dev/null || true
  done
}

# Prove a variable set OUT HERE does not cross `--clearenv`. Same discipline as
# `absent_inside`, for the env channel: a leak assertion whose subject was never
# set outside passes for the wrong reason.
env_absent_inside() {
  local desc=$1 name=$2
  if [ -z "${!name:-}" ]; then
    printf '  n/a   %s — %s is unset out here; nothing to leak\n' "${desc}" "${name}"
    return 0
  fi
  # The name is expanded here; the LOOKUP runs inside.
  rig_assert "${desc}" in_sandbox -- sh -c "[ -z \"\${${name}:-}\" ]"
}

# ── row: write floor ────────────────────────────────────────────────────────

row_write_floor() {
  row_begin 'write floor — a sentinel written outside the capsule reaches nowhere'
  reset_capsule

  local targets=("${REPO}/${SENTINEL}" "/tmp/${SENTINEL}" "${RIG_ROOT}/${SENTINEL}")

  # POSITIVE CONTROL, and it is the load-bearing half. "The sentinel is nowhere"
  # is true of a probe looking in the wrong place, of a sandbox that failed to
  # start, and of a `sh -c` that never executed. This proves the probe can SEE a
  # sentinel the capsule wrote, at a path the capsule is allowed to write.
  plant_outside "/capsule/${SENTINEL}"
  rig_assert 'positive control: a sentinel written INSIDE the capsule IS visible out here' \
    test -e "${CAPSULE}/${SENTINEL}"

  plant_outside "${targets[@]}"
  assert_no_sentinel "${targets[@]}"

  record_row write-floor \
    "sentinel absent at ${REPO}, /tmp and ${RIG_ROOT}; present at the capsule root (control)" \
    'writes outside the rw bind reach nowhere; /tmp is a tmpfs inside, so the write succeeds and is simply invisible — the observable is the host path, never the write status'
}

# ── row: canonical invisibility ─────────────────────────────────────────────

row_canonical() {
  row_begin 'canonical invisibility — the control-plane repo does not resolve'
  reset_capsule

  # POSITIVE CONTROL. A section of "does not resolve" assertions passes
  # vacuously if NOTHING resolves — a sandbox that failed to start scores green.
  rig_assert 'positive control: /nix/store RESOLVES inside the sandbox' \
    in_sandbox -- test -d /nix/store

  absent_inside "ABSENT: the canonical repo (${REPO}) does not resolve" "${REPO}"
  absent_inside "ABSENT: the capsule root (other capsules) does not resolve" "${RIG_ROOT}"
  absent_inside "ABSENT: the light fixture does not resolve" "${FIXTURE}"

  # The spec names `git -C <canonical>` as well as `ls`, and it is a different
  # claim: a path can fail `test -e` while git still reaches it through a
  # configured worktree or an env var. `git` is proven to RUN inside by the
  # credential row's control; here it must fail to find a repository.
  rig_assert_fails 'git -C <canonical> cannot reach a repository from inside' \
    in_sandbox -- git -C "${REPO}" rev-parse --show-toplevel

  record_row canonical \
    "${REPO}, ${RIG_ROOT} and ${FIXTURE} do not resolve inside; git -C <canonical> finds no repository; /nix/store does (control)" \
    'absent by construction under an allowlist floor — asserted anyway, because by-construction is exactly what a later profile edit breaks silently'
}

# ── row: git credentials ────────────────────────────────────────────────────

row_git_creds() {
  row_begin 'git creds — no credential reaches the capsule, and a push has nowhere to go'
  reset_capsule

  probe_credential_helper

  # The home ROOT is the load-bearing subject. `~/.ssh` exists on the host but
  # the OUTER jail hides it, so in-jail that leg is `n/a` and says nothing about
  # the capsule; the home root certainly exists and carries the general claim.
  absent_inside 'ABSENT: the host home root does not resolve' "${HOME}"
  absent_inside 'ABSENT: ~/.ssh does not resolve' "${HOME}/.ssh"
  absent_inside 'ABSENT: ~/.gitconfig does not resolve' "${HOME}/.gitconfig"

  # ── push, asserted on the DESTINATION and not on the message ──────────────
  #
  # "Fails on transport, not policy prose" is not checkable by reading stderr —
  # that is the DQ-3 trap in its purest form. So the destination is a real bare
  # repo out here, and the observable is the ref it does NOT gain.
  local target="${RIG_ROOT}/probes/c2/push-target.git"
  rm -rf -- "${target}"
  mkdir -p -- "$(dirname -- "${target}")"
  git init --quiet --bare -- "${target}"

  # POSITIVE CONTROL: the target is pushable, and this probe would notice. Run
  # from OUT HERE against the provisioned capsule clone, then wound back — if
  # this leg cannot move the ref, the leg below proves only that pushing is hard.
  in_sandbox --source "${FIXTURE}" -- /rig/provision.sh \
    "$(git -C "${FIXTURE}" rev-parse HEAD)" >/dev/null 2>&1 ||
    rig_die 'git-creds row: could not provision the capsule clone'
  rig_assert 'positive control: the push target IS pushable from out here' \
    git -C "${CAPSULE}/repo" push --quiet "${target}" HEAD:refs/heads/control
  rig_assert 'positive control: the pushed ref is observable on the target' \
    git -C "${target}" rev-parse --verify --quiet refs/heads/control
  git -C "${target}" update-ref -d refs/heads/control

  rig_assert_fails 'a file:// push to a control-plane path FAILS from inside' \
    in_sandbox -- sh -c "cd /capsule/repo && git push --quiet '${target}' HEAD:refs/heads/escaped"
  rig_assert_fails 'and the target gained no ref — the observable, not the message' \
    git -C "${target}" rev-parse --verify --quiet refs/heads/escaped

  rig_assert_fails 'an ssh push FAILS from inside (no key material, no route to a host)' \
    in_sandbox -- sh -c 'cd /capsule/repo && git push --quiet git@example.invalid:x.git HEAD:refs/heads/escaped'

  record_row git-creds \
    "no credential helper on the effective cascade (control: one IS detected when present); ${HOME} does not resolve; the file:// target gains no ref (control: it is pushable from out here)" \
    'the push legs assert on the DESTINATION, never on stderr wording — "fails on transport, not policy prose" is not readable from an error message'
}

# ── row: API credential presence ────────────────────────────────────────────

row_api_cred() {
  row_begin 'API cred presence — the one admitted secret arrives, and only it'
  reset_capsule

  # The credential arrives ro-bound INSIDE a writable agent home. This row
  # asserts the MOUNT; that the credential actually authenticates is A2's
  # assertion (design § 5.4 step 2, control/probe-smoke.sh) and is read from A2's
  # record rather than re-run — an authenticated `claude -p` per P-C2 run would
  # spend an API call to re-observe something already recorded.
  #
  # ── the observable is the CREDENTIAL, not its directory (F-P06-8) ───────────
  #
  # This row used to assert that a write to `/agent/.claude/<other-file>` failed,
  # and call that "the capsule cannot rewrite the credential". The two coincided
  # only while the whole of `~/.claude` was ro-bound, and D-P06-5's writable home
  # pulled them apart. The proxy was never sound in the direction that matters:
  # a read-only directory with the secret bind-mounted rw over it passes the old
  # leg while the secret is writable. So the legs below name the file.
  #
  # The POSITIVE CONTROL is what makes the refusals mean anything. The agent home
  # is writable by design — the harness creates a per-session directory there
  # before its first tool call (F-P06-6) — so "the capsule cannot write the
  # credential" must be shown against a capsule that demonstrably CAN write right
  # next to it, or the row would pass just as well on a broken write mechanism
  # (`mem_019fa18161f4`: a negative is untrustworthy without a positive control).
  rig_assert 'the agent home is the capsule HOME' \
    # The expansion must run INSIDE the sandbox, so it is deliberately not
    # expanded out here.
    # shellcheck disable=SC2016
    in_sandbox -- sh -c '[ "${HOME}" = /agent ]'
  rig_assert 'the credential resolves at /agent/.claude/.credentials.json' \
    in_sandbox -- test -f /agent/.claude/.credentials.json
  rig_assert 'and it READS — an unreadable secret would fail these legs for the wrong reason' \
    in_sandbox -- sh -c 'head -c 1 /agent/.claude/.credentials.json >/dev/null'
  rig_assert 'positive control: the agent home IS writable — the harness needs a session dir' \
    in_sandbox -- sh -c 'printf x >>/agent/.claude/.capsule-write-probe'
  rig_assert_fails 'the capsule cannot APPEND to the credential' \
    in_sandbox -- sh -c 'printf x >>/agent/.claude/.credentials.json'
  rig_assert_fails 'the capsule cannot TRUNCATE it' \
    in_sandbox -- sh -c ': >/agent/.claude/.credentials.json'
  rig_assert_fails 'the capsule cannot UNLINK it — a rw dir would otherwise allow replacement' \
    in_sandbox -- sh -c 'rm -f /agent/.claude/.credentials.json'

  local a2
  if [ -f "${SMOKE_REPORT}" ] &&
    a2=$(grep -m1 '^credential	authenticated	pass' "${SMOKE_REPORT}") && [ -n "${a2}" ]; then
    rig_assert 'A2 recorded an authenticated run with this credential arrangement' \
      test -n "${a2}"
    record_row api-cred \
      'HOME=/agent; the credential reads and is refused on append, truncate and unlink, against a positive control writing beside it; A2 recorded an authenticated claude -p run' \
      'the admitted secret, named: its blast radius is API usage, accepted (probe-specs P-C2). The legs name the FILE, not its directory (F-P06-8). Authentication itself is A2 evidence, cited not re-run'
  else
    # Not a silent pass and not a failure of THIS row: the mount assertions
    # above held, and the thing missing is another probe's record.
    record_row_na api-cred \
      'HOME=/agent; the credential reads and is refused on append, truncate and unlink, against a positive control writing beside it' \
      "no A2 authenticated record at ${SMOKE_REPORT} — run \`rig smoke\`; the mount legs above passed, only the authentication citation is missing"
  fi
}

# ── row: env probe ──────────────────────────────────────────────────────────

row_env() {
  row_begin 'env probe — nothing canonical leaks through the environment'
  reset_capsule

  # POSITIVE CONTROL: `env` runs and the profile's own names DO cross. Without
  # this, every leak assertion below is satisfied by an empty dump.
  rig_assert 'positive control: the profile-set names DO cross (RIG_DOORBELL)' \
    # The expansion must run INSIDE the sandbox, so it is deliberately not
    # expanded out here.
    # shellcheck disable=SC2016
    in_sandbox -- sh -c '[ -n "${RIG_DOORBELL:-}" ]'
  rig_assert 'positive control: env produces a dump at all' \
    in_sandbox -- sh -c 'env | grep -q .'

  # The control plane's own variables, proven set OUT HERE first. These are the
  # ones a `--clearenv` regression would let through, and they name the exact
  # paths the profile exists to hide.
  env_absent_inside 'SPIKE_CAPSULE_ROOT does not cross --clearenv' SPIKE_CAPSULE_ROOT
  env_absent_inside 'SPIKE_WORKER_MODE does not cross --clearenv' SPIKE_WORKER_MODE
  env_absent_inside 'DOCTRINE_BIN does not cross --clearenv' DOCTRINE_BIN
  env_absent_inside 'GIT_CONFIG_GLOBAL does not cross --clearenv' GIT_CONFIG_GLOBAL

  # And the general claim, over VALUES rather than names: no variable inside
  # mentions the canonical repo, the capsule root, or the host home. PATH is the
  # interesting case — it is rebuilt from /nix/store entries only, so a host
  # PATH entry under $HOME would surface right here.
  local dump
  dump=$(in_sandbox -- env 2>/dev/null | grep -v '^rig: ' || true)
  rig_assert_eq 'no environment VALUE mentions the canonical repo' \
    '' "$(printf '%s' "${dump}" | grep -F "${REPO}" || true)"
  rig_assert_eq 'no environment VALUE mentions the capsule root' \
    '' "$(printf '%s' "${dump}" | grep -F "${RIG_ROOT}" || true)"
  # HOME=/agent is the profile's own rewrite, so the HOST home path is the
  # subject — not the variable name.
  rig_assert_eq 'no environment VALUE mentions the host home path' \
    '' "$(printf '%s' "${dump}" | grep -F "${HOME}" || true)"

  record_row env \
    "no variable inside names ${REPO}, ${RIG_ROOT} or ${HOME}; SPIKE_CAPSULE_ROOT/SPIKE_WORKER_MODE/DOCTRINE_BIN do not cross (each proven set out here); RIG_DOORBELL does (control)" \
    'asserted over VALUES as well as names — PATH is rebuilt from /nix/store entries only, so a host PATH entry under the host home would surface here'
}

# ── row: escape via .git ────────────────────────────────────────────────────

row_escape_git() {
  row_begin 'escape via .git — hook and config rewrites are ALLOWED, and still reach nowhere'
  reset_capsule

  in_sandbox --source "${FIXTURE}" -- /rig/provision.sh \
    "$(git -C "${FIXTURE}" rev-parse HEAD)" >/dev/null 2>&1 ||
    rig_die 'escape-git row: could not provision the capsule clone'

  local targets=("${REPO}/${SENTINEL}" "/tmp/${SENTINEL}" "${RIG_ROOT}/${SENTINEL}")

  # The capsule rewrites its own `.git` and installs a post-commit hook that
  # tries to plant the sentinel everywhere, then commits so the hook FIRES.
  # Per probe-specs this row's pass condition is "allowed (capsule-local)" — so
  # both halves are assertions: the rewrite must SUCCEED, and it must reach
  # nothing outside. A row where the rewrite silently failed would record the
  # same green while proving the opposite thing.
  rig_assert 'the capsule CAN rewrite its own .git/config (capsule-local, allowed)' \
    in_sandbox -- sh -c 'cd /capsule/repo && git config --local capsule.escaped true'

  # The expansion must run INSIDE the sandbox, so it is deliberately not
  # expanded out here.
  # shellcheck disable=SC2016
  in_sandbox -- sh -c '
    cd /capsule/repo
    mkdir -p .git/hooks
    {
      printf "#!/usr/bin/env bash\n"
      for p in "$@"; do printf ": >%s 2>/dev/null || true\n" "$p"; done
      printf ": >/capsule/hook-fired\n"
    } >.git/hooks/post-commit
    chmod +x .git/hooks/post-commit
    git commit -q --allow-empty -m "[add] hook trigger"
  ' sh "${targets[@]}" >/dev/null 2>&1 || true

  # POSITIVE CONTROL: the hook actually RAN. Without it, "the sentinel is
  # nowhere" is what a hook that never fired also looks like — and an unfired
  # hook is the single most likely way this row lies.
  rig_assert 'positive control: the post-commit hook FIRED inside the capsule' \
    test -e "${CAPSULE}/hook-fired"

  assert_no_sentinel "${targets[@]}"

  record_row escape-git \
    "capsule.escaped is set in the capsule's own .git/config; /capsule/hook-fired exists (control: the hook ran); no sentinel at ${REPO}, /tmp or ${RIG_ROOT}" \
    'allowed and contained: hooks execute with the capsule as their whole world. Ingestion is where this matters (P-C3), and this row is what makes that a real precondition rather than an assumption'
}

# ── row: resource bounds (EX-6) ─────────────────────────────────────────────

row_resource() {
  row_begin 'resource bounds — the wall clock and the disk cap, as a row in its own right'
  reset_capsule

  # POSITIVE CONTROLS FIRST. A bound assertion made of "it was killed" passes
  # vacuously against a sandbox that kills everything, and a disk assertion made
  # of "the write was refused" passes against one that refuses every write.
  rig_assert 'positive control: a short run SURVIVES the wall-clock bound' \
    in_sandbox --timeout 30 -- sh -c 'exit 0'

  local t0 t1 status=0 elapsed
  t0=$(date +%s)
  in_sandbox --timeout 3 -- sleep 600 || status=$?
  t1=$(date +%s)
  elapsed=$((t1 - t0))
  rig_assert_eq "wall clock: a hung run is KILLED (status ${status})" \
    "${RIG_EXIT_TIMEOUT}" "${status}"
  rig_assert "wall clock: killed at the bound, not at the 600s sleep (${elapsed}s)" \
    test "${elapsed}" -lt 30

  local cap=$((8 * 1024 * 1024))
  reset_capsule
  rig_assert 'positive control: a write inside the cap succeeds' \
    in_sandbox --disk-cap "${cap}" -- \
    sh -c 'dd if=/dev/zero of=/capsule/thin bs=1K count=64 2>/dev/null'

  reset_capsule
  rig_assert_eq 'disk: an oversized write is REFUSED' \
    "${RIG_EXIT_DISK}" \
    "$(sandbox_status --disk-cap "${cap}" -- \
      sh -c 'dd if=/dev/zero of=/capsule/fat bs=1M count=64 2>/dev/null')"

  record_row resource \
    "status ${RIG_EXIT_TIMEOUT} and elapsed < 30s for a 600s sleep under a 3s bound; status ${RIG_EXIT_DISK} for a 64MiB write under an 8MiB cap; both controls (a short run and a small write) succeed" \
    'STATUSES, not tokens — the bounds are trusted-side and emit no vocabulary (I5). PHASE-02 probe-capsule bounds carries the exhaustive treatment, including the sparse-oversize leg that separates ulimit -f from du, and both capsule kinds; this row is the P-C2 matrix entry EX-6 requires'
}

# ── run ─────────────────────────────────────────────────────────────────────

printf '\nP-C2 — the confinement matrix (EX-5, EX-6, VA-3)\n'

for row in "${rows[@]}"; do
  case "${row}" in
    write-floor) row_write_floor ;;
    canonical) row_canonical ;;
    git-creds) row_git_creds ;;
    api-cred) row_api_cred ;;
    env) row_env ;;
    escape-git) row_escape_git ;;
    resource) row_resource ;;
  esac
done

# ── VA-3, made mechanical ───────────────────────────────────────────────────
#
# "Every row is recorded with its observable named" is a property of the file,
# so it is checked against the file rather than believed. A row whose observable
# column is empty is exactly the silent pass probe-specs forbids.
printf '\n'
rows_assert_complete 'VA-3' "${#rows[@]}"

rows_write "${REPORT}" "${REPORT_COLUMNS}" \
  "$(printf 'p-c2: %s\tin-jail\trows=%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${rows[*]}")"

printf '\nresults: %s\n' "${REPORT}"
printf '%s\n' "${ROWS_RECORDED[@]}" | cut -f1,3 | sed 's/^/  /'

rig_assert_done 'probe-c2'
