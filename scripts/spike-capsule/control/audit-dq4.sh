#!/usr/bin/env bash
# audit-dq4.sh — the trusted side never runs the project's toolchain.
#
#   usage: audit-dq4.sh [--root DIR] [--declaration FILE] [--positive-control]
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# DQ-4: "the trusted side never executes/evaluates capsule content outside a
# capsule (no `direnv allow`, no `nix build`, no `cargo` anything on harvested
# trees on the control-plane side; RT-1). Any probe step that needs candidate
# execution runs in a verify capsule."
#
# The subjects are the ACTIVE declaration's `exec:` tokens, read from the
# interpretation-surface file rather than hardcoded — the declaration is the
# thing under test, and an audit carrying its own copy of the token list would
# keep passing after the declaration changed.
#
# ── what "absent from control/**" cannot mean ───────────────────────────────
#
# Taken as a string search it forbids the WORD. `control/pipeline.sh` explains
# why `verify:` is run through `sh -c` and quotes `node -e "process.exit(1)"` to
# do it; a rig that could not discuss its own hazards in a comment would be a
# worse rig. Taken as "never appears as a command" it is unimplementable in
# shell: `rig_assert '…' npm run build` executes npm without npm being in
# command position anywhere a regex can see.
#
# So the audit reports SITES and requires each to be accounted for:
#
#   comment lines            not execution — excluded
#   quoted-only occurrences  the shell invokes UNQUOTED words, so a token that
#                            survives only inside a '…' or "…" span is prose or
#                            data, not a command. This is what separates
#                            `(cd … && npm test)` from a results-file detail
#                            string that happens to mention npm.
#   sandbox-routed lines     the token is handed to `in_sandbox` / "${SANDBOX}"
#                            / a /rig runner, i.e. it runs INSIDE a capsule,
#                            which is what DQ-4 directs such steps to do
#   everything else          a CANDIDATE. It must appear in the exemption table
#                            below, with a reason, or the audit refuses.
#
# STATED BLIND SPOT: quote-stripping would miss a trusted-side `sh -c 'npm
# test'`, where the invocation is itself inside quotes. So an unrouted `sh -c` /
# `bash -c` / `eval` on the line makes it a site whatever the quoting. An audit
# that does not say where it cannot see is the more dangerous kind.
#
# The exemption table is printed on every clean run, with its site count. An
# allowlist nobody reads is how "the control plane never runs the toolchain"
# becomes false without anyone deciding it should be. Each exemption is also
# checked for STALENESS — an exemption whose file no longer has a site is an
# assertion about code that has moved, and it is removed rather than kept.
#
# ── the positive control (EX-7) ─────────────────────────────────────────────
#
# `--positive-control` copies the rig to a scratch root under the capsule root,
# requires the audit to PASS, plants an unexempted trusted-side invocation,
# requires it to REFUSE, removes it, and requires it to PASS again. Both
# directions: a negative grep without a positive control proves only that grep
# ran (`mem_019fa18161f4…`), and an audit that refuses everything is exactly as
# broken as one that refuses nothing.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

SELF=$(basename -- "${BASH_SOURCE[0]}")

# ── the exemption table ─────────────────────────────────────────────────────
#
# `<relative-path>|<reason>`. A file, never a line number: line numbers rot on
# the first edit and an audit that silently stopped covering a file is worse
# than one that never covered it.
#
# BOTH ENTRIES ARE CONDITIONAL, and the condition is the finding. Read them as
# obligations on future phases, not as dispensations already granted.
DQ4_EXEMPTIONS=(
  "control/fixture-light.sh|runs npm at fixture BUILD time, on a tree it assembles from this repo's OWN authored sources — no capsule has touched it and nothing has been harvested, so it is outside DQ-4's subject (capsule content / harvested trees). CONDITIONAL: this holds only while the fixture is authored-content-only. A PHASE-05 payload-bearing variant (H11 postinstall) that reuses this build loop would execute the planted payload TRUSTED-SIDE and break DQ-4 for real."
)

root="${RIG_DIR}"
declaration=""
positive_control=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      root=${2:?--root needs a directory}
      shift
      ;;
    --declaration)
      declaration=${2:?--declaration needs a file}
      shift
      ;;
    --positive-control) positive_control=1 ;;
    -h | --help)
      sed -n '2,10p' "${BASH_SOURCE[0]}"
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

# The ACTIVE declaration. Default is the light fixture's provisioned copy —
# the one the pipeline actually reads — falling back to the authored source, so
# the audit is runnable before `fixture-light.sh` has ever been run.
if [ -z "${declaration}" ]; then
  declaration="${RIG_ROOT}/fixtures/light/interpretation-surface.txt"
  [ -f "${declaration}" ] || declaration="${RIG_DIR}/fixtures/light/interpretation-surface.txt"
fi
[ -f "${declaration}" ] || rig_die "no interpretation-surface declaration at ${declaration}"

read -r -a EXEC_TOKENS <<<"$(declaration_field "${declaration}" exec)"
[ "${#EXEC_TOKENS[@]}" -gt 0 ] ||
  rig_die "the declaration at ${declaration} names no exec: tokens — nothing to audit"

# ── the scan ────────────────────────────────────────────────────────────────

# A line that hands the token to a capsule. `/rig/` covers the runners, which
# are ro-bound INSIDE the sandbox and are the one place a control-plane-authored
# script legitimately runs against capsule content.
# The shell invokes unquoted words. Stripping complete quoted spans leaves only
# what the shell would actually treat as command text — single quotes first, so
# a double-quoted span nested inside them goes with its host.
unquoted() {
  printf '%s' "$1" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g"
}

# The one construct quote-stripping cannot see through: a command built INSIDE a
# string. Unrouted, it is a site regardless of where the token sits.
indirect_exec() {
  case "$1" in
    # `*'sh -c'*` covers `bash -c` too — it is a substring of it.
    *'sh -c'* | *eval\ *) return 0 ;;
  esac
  return 1
}

sandbox_routed() {
  # The needles are SOURCE TEXT, so the `${SANDBOX}` in them is matched
  # literally and must not be expanded here.
  # shellcheck disable=SC2016
  case "$1" in
    *in_sandbox* | *'${SANDBOX}'* | */rig/*) return 0 ;;
  esac
  return 1
}

exempt_reason() {
  local entry
  for entry in "${DQ4_EXEMPTIONS[@]}"; do
    case "$1" in
      "${entry%%|*}") printf '%s' "${entry#*|}" ;;
    esac
  done
}

# Prints one line per unaccounted site; exit 0 when clean. The OUTPUT is the
# finding — an empty output with a nonzero exit would be the audit lying by
# omission.
#
# Publishes the per-file site counts the staleness check reads, rather than
# returning them: this runs inside `if`, so a `$( … )` here would put the whole
# scan in a subshell and lose them.
declare -A DQ4_SITES=()
audit() {
  local token file rel line no violations=0
  DQ4_SITES=()
  for token in "${EXEC_TOKENS[@]}"; do
    while IFS= read -r file; do
      rel="${file#"${root}"/}"
      while IFS=: read -r no line; do
        # A comment is not execution.
        case "$(printf '%s' "${line}" | sed 's/^[[:space:]]*//')" in
          '#'*) continue ;;
        esac
        sandbox_routed "${line}" && continue
        if ! indirect_exec "${line}"; then
          # Quoted-only: prose or data, never a command.
          case "$(unquoted "${line}")" in
            *"${token}"*) ;;
            *) continue ;;
          esac
        fi
        DQ4_SITES["${rel}"]=$((${DQ4_SITES["${rel}"]:-0} + 1))
        [ -n "$(exempt_reason "${rel}")" ] && continue
        printf 'DQ-4 VIOLATION: %s:%s runs %s trusted-side — %s\n' \
          "${rel}" "${no}" "${token}" "$(printf '%s' "${line}" | sed 's/^[[:space:]]*//')"
        violations=$((violations + 1))
      done < <(grep -nE "(^|[^[:alnum:]_./-])${token}([^[:alnum:]_.-]|$)" -- "${file}" || true)
    done < <(trusted_side_files)
  done
  [ "${violations}" -eq 0 ]
}

# THE TRUSTED SIDE, enumerated — `control/` and `lib/` and the `rig` entry
# point. Two directories are deliberately NOT here, and neither omission is an
# oversight:
#
#   capsule/    the runners. They are ro-bound at /rig and execute INSIDE a
#               capsule by mount posture (I4a) — running the toolchain is their
#               job, and auditing them would forbid the thing DQ-4 directs such
#               steps to do.
#   fixtures/   the project under test. `package.json` naming `node --test` is
#               the fixture being a TypeScript project, not the control plane
#               running one.
trusted_side_files() {
  local dir
  for dir in control lib; do
    [ -d "${root}/${dir}" ] && find "${root}/${dir}" -type f ! -name "${SELF}" -print
  done
  [ -f "${root}/rig" ] && printf '%s\n' "${root}/rig"
  return 0
}

report_exemptions() {
  local entry rel
  printf '\nexemptions — accounted-for sites, printed every run (control/**)\n'
  for entry in "${DQ4_EXEMPTIONS[@]}"; do
    rel="${entry%%|*}"
    printf '  %s — %s site(s)\n    %s\n' \
      "${rel}" "${DQ4_SITES["${rel}"]:-0}" "${entry#*|}"
    # An exemption whose file no longer has a site is an assertion about code
    # that has moved. Kept, it silently widens to whatever lands there next.
    rig_assert "exemption for ${rel} is not stale — it still covers a real site" \
      test "${DQ4_SITES["${rel}"]:-0}" -gt 0
  done
}

# ── run ─────────────────────────────────────────────────────────────────────

if [ "${positive_control}" -eq 0 ]; then
  printf 'audit-dq4: exec tokens %s (from %s)\n' "${EXEC_TOKENS[*]}" "${declaration}"
  if audit; then
    printf 'audit-dq4: clean — no unaccounted trusted-side invocation under %s\n' "${root}"
    report_exemptions
    rig_assert_done 'audit-dq4'
    exit 0
  fi
  rig_warn "audit-dq4: the trusted side runs the project's toolchain under ${root}"
  exit 1
fi

# ── positive control (EX-7) ─────────────────────────────────────────────────

SCRATCH="${RIG_ROOT}/probes/c2/audit-dq4-scratch"
control_root="${SCRATCH}/rig"
guard_not_real_repo "${control_root}"
rm -rf -- "${control_root}"
mkdir -p -- "${control_root}"
cp -R -- "${RIG_DIR}/." "${control_root}/"

root="${control_root}"
rig_assert 'unplanted: the audit PASSES on a clean copy of the rig' audit

# The plant is the ORDINARY REFLEX, spelled out: a control script running the
# project's suite on a harvested tree to "just check" it. Not a contrived
# payload — it is what a shell rig does by habit, which is why it is the thing
# worth catching. Unexempted, so it must be found.
planted="${control_root}/control/regression.sh"
cat >"${planted}" <<'PLANT'
#!/usr/bin/env bash
# Convenience: check the harvested tree before ingesting it.
(cd "${quarantine}/work" && npm test) || exit 1
PLANT

rig_assert_fails 'planted: the audit REFUSES a trusted-side npm on a harvested tree' \
  audit

rm -f -- "${planted}"
rig_assert 'unplanted again: the audit PASSES on the same tree' audit

rm -rf -- "${control_root}"
rig_assert_done 'audit-dq4 positive control'
