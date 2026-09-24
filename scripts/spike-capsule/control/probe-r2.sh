#!/usr/bin/env bash
# probe-r2.sh — settle R2 (PHASE-01 T7, EX-6, VA-2, VA-3).
#
#   usage: probe-r2.sh [--keep]
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# R2 as the plan states it — "does `slice conformance --against B..S --strict`
# match the import belt's undeclared-path semantics" — conflates two predicates,
# because `worktree import` has TWO scope postures. This probe splits them:
#
#   R2a  SELECTOR AGREEMENT. Does `--strict` reach the same undeclared/clean
#        verdict as the belt's scope leg over the same range?
#
#   R2b  SEPARATION. Does `--strict` refuse `.doctrine/`/`.claude/` touches on
#        its own? It should NOT — those are the R-5 belt's job, and design § 5.2
#        makes them a separate conform leg (leg 3). If `--strict` covered them,
#        leg 3 is redundant; if it does not, leg 3 is LOAD-BEARING and PHASE-03
#        must not skip it.
#
# WHAT IS COMPARED, AND WHY IT IS NOT A REIMPLEMENTATION. The belt's scope leg
# (`src/worktree/import.rs:159`) and `conformance --against` (`src/slice.rs`,
# `conformance::compute`) call the SAME pure predicate,
# `crate::conformance::undeclared_paths`. Re-deriving glob matching in shell
# would test this script's matcher, not the belt. So the probe asserts the two
# things that genuinely CAN diverge:
#
#   1. PATH EXTRACTION. The belt gathers `--name-only`
#      (`src/mcp_server/dispatch.rs:487`); conformance gathers `--name-status`
#      and folds it (`actual_from_range`). Different gathers, same claimed
#      hardening — so non-ASCII and rename edges are probed directly.
#   2. THE PREFIX LEGS, which the belt runs BEFORE the scope leg and which
#      `--strict` has no equivalent of at all. That is R2b.
#
# D-P01-1: the comparator is the belt's documented semantics and its reference
# invocation, NOT a live `worktree import --slice` run — import needs HEAD == B,
# a clean coordination worktree and a durable fork binding, none of which a
# fixture has (design § 2.1 F1/F2).
#
# EDGE 6 IS WHY THIS SCRIPT BUILDS ITS OWN SLICES. Probed against the light
# fixture's base slice (selectors `src/**` only), a `.doctrine/` path is
# undeclared, so `--strict` refuses it — for the WRONG REASON, and R2b scores
# backwards as "yes, --strict covers the prefix legs". Edges 5 and 6 therefore
# run against a slice that DECLARES the `.doctrine/` path, which is the only
# arrangement where refuse-as-forbidden and refuse-as-undeclared are separable.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) keep=1 ;;
    -h | --help)
      sed -n '2,45p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) rig_die "unknown argument: $1" ;;
  esac
  shift
done

rig_enter

light="${RIG_ROOT}/fixtures/light/repo"
work="${RIG_ROOT}/probes/r2/repo"
[ -d "${light}" ] || rig_die "light fixture missing — run control/fixture-light.sh first"
guard_not_real_repo "${work}"

doctrine_bin="${DOCTRINE_BIN:-$(rig_repo_root)/target/debug/doctrine}"
[ -x "${doctrine_bin}" ] || rig_die "no doctrine binary at ${doctrine_bin}"

# Probe apparatus, not a fixture variant: the base light fixture stays pristine
# (EX-11), and this clone is disposable.
rm -rf -- "${work}"
mkdir -p -- "$(dirname -- "${work}")"
git clone --no-hardlinks --quiet -- "${light}" "${work}"
git -C "${work}" remote remove origin
git -C "${work}" config --local user.name "r2 probe"
git -C "${work}" config --local user.email "r2@spike-capsule.invalid"
git -C "${work}" config --local commit.gpgsign false

# Three selector arrangements. SL-001 is the fixture's own (`src/**`). SL-002
# additionally declares the `.doctrine/probe/**` path, so edges 5/6 can tell a
# forbidden-path refusal from an undeclared-path one. SL-003 declares nothing,
# for edge 8's fail-closed question.
"${doctrine_bin}" slice new "R2 doctrine-declaring" --path "${work}" >/dev/null
"${doctrine_bin}" slice selector add 2 'src/**' '.doctrine/probe/**' \
  --intent design-target --path "${work}" >/dev/null
"${doctrine_bin}" slice new "R2 no selectors" --path "${work}" >/dev/null
git -C "${work}" add -A
git -C "${work}" commit --quiet -m "[add] r2 probe slices"

report="${RIG_ROOT}/probes/r2/results.tsv"
printf 'edge\tslice\tdelta-paths\tstrict-exit\tstrict-undeclared\tbelt-prefix\tverdict\n' >"${report}"

# ── the belt, in its own reference invocation ────────────────────────────────

# Gather exactly as `src/mcp_server/dispatch.rs:487` does. quotePath off so a
# non-ASCII path emits verbatim rather than C-quoted AND double-quoted;
# --no-renames so a source leg cannot hide behind a same-content destination;
# -z because NUL is the only byte-safe delimiter to parse in shell.
belt_paths() {
  git -C "${work}" -c core.quotePath=false diff --name-only --no-renames -z "$1"
}

# `classify_import`'s ORDER, which is load-bearing: the `.doctrine/`/`.claude/`
# prefix legs run BEFORE the scope leg, so a `.doctrine/` path is DoctrineTouch
# even when no selector declares it either (import.rs:656 asserts exactly this).
# Reports only the prefix legs — the scope leg is `undeclared_paths`, the same
# function `--strict` calls, and asserting a shell copy of it would prove
# nothing about the belt.
belt_prefix_verdict() {
  local range=$1 path
  while IFS= read -r -d '' path; do
    case "${path}" in
      .doctrine/*)
        printf 'doctrine-touch'
        return
        ;;
      .claude/*)
        printf 'claude-touch'
        return
        ;;
    esac
  done < <(belt_paths "${range}")
  printf 'prefix-legs-pass'
}

# The `undeclared (N):` block, as a comma-joined path list. Each entry is
# `  <status> <path>`; the block ends at the next `<word> (N):` header. Reported
# so a verdict can be read against WHICH paths drove it, not just an exit code.
strict_undeclared() {
  awk '
    /^undeclared \(/ { inblock = 1; next }
    /^[a-z]+ \(/     { inblock = 0 }
    inblock && NF > 1 { printf "%s%s", sep, $2; sep = "," }
  ' /tmp/r2-strict.out
}

# <edge> <slice> <range> <expect-strict:refuse|clean> <expect-belt-prefix> <reading>
#
# EXPECTATIONS ARE ASSERTED, not eyeballed. R2a predicts agreement, and a probe
# run by someone expecting agreement finds it — so every edge states its verdict
# up front and a mismatch is a failure, not a paragraph.
record() {
  local edge=$1 slice=$2 range=$3 want_strict=$4 want_belt=$5 reading=$6
  local exit_code=0 paths undeclared belt got_strict

  paths=$(belt_paths "${range}" | tr '\0' ',' | sed 's/,$//')
  [ -n "${paths}" ] || paths="(none)"

  "${doctrine_bin}" slice conformance "${slice}" --path "${work}" \
    --against "${range}" --strict --color never >/tmp/r2-strict.out 2>&1 || exit_code=$?
  undeclared=$(strict_undeclared)
  [ -n "${undeclared}" ] || undeclared="(none)"

  belt=$(belt_prefix_verdict "${range}")
  [ "${exit_code}" -eq 0 ] && got_strict=clean || got_strict=refuse

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${edge}" "SL-00${slice}" "${paths}" "${exit_code}" "${undeclared}" "${belt}" "${reading}" \
    >>"${report}"

  printf '\nedge %s (SL-00%s) — %s\n' "${edge}" "${slice}" "${reading}"
  printf '  delta:              %s\n' "${paths}"
  printf '  strict undeclared:  %s\n' "${undeclared}"
  rig_assert_eq "  edge ${edge}: --strict is ${want_strict}" "${want_strict}" "${got_strict}"
  rig_assert_eq "  edge ${edge}: belt prefix legs are ${want_belt}" "${want_belt}" "${belt}"
}

commit_at() { # <message> → prints the new HEAD
  git -C "${work}" add -A
  git -C "${work}" commit --quiet -m "[add] $1"
  git -C "${work}" rev-parse HEAD
}

printf '\nR2 probe — light fixture clone at %s\n\n' "${work}"

# ── edge 1 — path matching no selector ───────────────────────────────────────
A=$(git -C "${work}" rev-parse HEAD)
mkdir -p -- "${work}/docs"
printf 'notes\n' >"${work}/docs/notes.md"
B=$(commit_at "docs note, declared by nothing")
record 1 1 "${A}..${B}" refuse prefix-legs-pass \
  "path matching no selector — the scope leg's ordinary case"

# ── edge 2 — path matching a design-target selector ──────────────────────────
A=${B}
printf 'export const rate = 0.1\n' >"${work}/src/tax.ts"
B=$(commit_at "tax rate under src/")
record 2 1 "${A}..${B}" clean prefix-legs-pass \
  "path matching a design-target selector"

# ── edge 3 — NON-ASCII path under a declared selector ────────────────────────
# The quotePath hardening's direct test: with git's default quotePath=true this
# path emits as ".doctrine/na\303\257ve" style — C-quoted AND double-quoted —
# and a prefix test misses it. Under a DECLARED selector, so a spurious
# `undeclared` here means the path was mis-read, not mis-declared.
A=${B}
printf 'export const naive = true\n' >"${work}/src/naïve.ts"
B=$(commit_at "non-ASCII module under src/")
record 3 1 "${A}..${B}" clean prefix-legs-pass \
  "NON-ASCII path under a declared selector — the quotePath hardening holds"

# ── edge 4 — RENAME OUT of a declared selector ───────────────────────────────
# --no-renames is what makes the SOURCE leg visible. With rename detection on,
# --name-only prints only the destination and `src/money.ts` vanishes entirely.
A=${B}
mkdir -p -- "${work}/docs"
git -C "${work}" mv src/money.ts docs/money.ts
B=$(commit_at "move money out of src/")
record 4 1 "${A}..${B}" refuse prefix-legs-pass \
  "RENAME OUT of a declared selector — the source leg stays visible"

# Put it back, so later edges start from a working tree.
git -C "${work}" mv docs/money.ts src/money.ts
B=$(commit_at "move money back under src/")

# ── edge 5 — RENAME OUT of .doctrine/, against a slice that DECLARES it ──────
mkdir -p -- "${work}/.doctrine/probe"
printf 'probe payload\n' >"${work}/.doctrine/probe/payload.md"
B=$(commit_at "doctrine probe payload")
A=${B}
git -C "${work}" mv .doctrine/probe/payload.md src/payload.md
B=$(commit_at "move payload out of .doctrine/")
record 5 2 "${A}..${B}" clean doctrine-touch \
  "RENAME OUT of .doctrine/, both legs DECLARED — belt refuses, --strict does not"

# ── edge 6 — .doctrine/ touch, against a slice that DECLARES it ──────────────
# R2b's sharpest case. Both legs of the delta are declared by SL-002, so the
# scope leg has nothing to say and the ONLY thing that could refuse is a
# forbidden-path leg. If `--strict` exits 0 here, leg 3 is load-bearing.
A=${B}
printf 'edited\n' >>"${work}/.doctrine/probe/kept.md"
B=$(commit_at "touch a declared .doctrine/ path")
record 6 2 "${A}..${B}" clean doctrine-touch \
  "R2b DECISIVE — a DECLARED .doctrine/ touch is CONFORMANT to --strict"

# ── edge 7 — empty range ─────────────────────────────────────────────────────
record 7 1 "${B}..${B}" clean prefix-legs-pass \
  "empty range A..A — clean, not an error"

# ── edge 8 — a slice with NO selectors ───────────────────────────────────────
# The help text claims `--strict` "refuses a clean diff when the registry is
# unavailable or incomplete (fail-closed)". `run_conformance`'s `--against` arm
# states it bypasses BOTH the registry read AND the completeness ladder, so that
# sentence describes the OTHER arm. What this edge actually settles is the
# empty-selector asymmetry: `classify_import` with empty selectors is a
# documented no-op (import.rs:668), so the belt's scope leg cannot refuse.
#
# Its delta is an ORDINARY src/ path, deliberately not a `.doctrine/` one: reuse
# a prefix-leg delta here and the refusal has two candidate causes and settles
# neither.
A=${B}
printf 'export const audited = true\n' >"${work}/src/audit.ts"
B=$(commit_at "ordinary src path for the no-selector edge")
record 8 3 "${A}..${B}" refuse prefix-legs-pass \
  "NO SELECTORS — --strict refuses where the belt's scope leg is a no-op"

# The same delta against a slice that DOES declare it — the positive control for
# edge 8. Without it, "refused" is equally explained by a broken invocation.
record 8b 1 "${A}..${B}" clean prefix-legs-pass \
  "edge 8's positive control — same delta, selectors present, --strict clean"

rig_assert_done "probe-r2"
printf '\nresults: %s\n' "${report}"
[ "${keep}" -eq 1 ] || printf 'probe tree at %s\n' "${work}"
