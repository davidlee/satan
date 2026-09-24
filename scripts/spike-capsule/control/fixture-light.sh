#!/usr/bin/env bash
# fixture-light.sh — provision the LIGHT fixture and its variants (PHASE-01 T5,
# EX-4; PHASE-05 T1, EX-11/EX-15).
#
# `ledger`: a small TypeScript project, deliberately unlike this repo (D5) —
# trunk `mainline`, `[add] …` commit style, npm scripts, no Rust anywhere. Its
# job is to test the taxonomy's PORTABILITY: does a known trigger class have a
# TypeScript instance? A fixture conventioned like this repo would pass every
# row for reasons that say nothing about portability.
#
#   usage: fixture-light.sh [--variant <base|inrepo|plan>] [--force]
#   env:   SPIKE_CAPSULE_ROOT   capsule / fixture root (default: ~/capsules)
#
# One provisioner, three variants. A second script would fork the whole
# red→green→install sequence in order to change what happens after it:
#
#   base    F1 — the declaration is a SIBLING of the repo, so the F-5
#           substitution attack is not live here
#   inrepo  F2 — plus a COMMITTED in-repo copy of the declaration. That copy is
#           the exposure guard probe (e) attacks; QUE-201's only evidence input
#   plan    F3 — plus a plan whose PHASE-01 is driven to `completed`, so the
#           H10/H16 sub-probe meets `prepare-review`'s phase-completion gate
#
# Layout — the declaration is a SIBLING of the repo, never inside it (F-5),
# except under `inrepo`, which exists precisely to make that exposure live:
#
#   $SPIKE_CAPSULE_ROOT/fixtures/light[-inrepo|-plan]/
#     repo/                        the project, doctrine-installed
#     interpretation-surface.txt   copied from the rig's authored source
#
# No dependencies and NO `npm install`: Node strips TypeScript types natively
# and `tsc` comes from the environment. Provisioning therefore needs no network
# — one less thing to be flaky inside a capsule.
set -euo pipefail

RIG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
. "${RIG_DIR}/lib/common.sh"

force=0
variant=base
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --variant)
      shift
      variant=${1:-}
      [ -n "${variant}" ] || rig_die "--variant requires <base|inrepo|plan>"
      ;;
    --variant=*) variant=${1#--variant=} ;;
    -h | --help)
      sed -n '2,33p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) rig_die "unknown argument: $1" ;;
  esac
  shift
done

# I6 — FIRST, before any provisioning.
rig_enter

# One authored source for all three variants: the delta is what the provisioner
# does after the base sequence, never a second copy of the project.
src="${RIG_DIR}/fixtures/light"
case "${variant}" in
  base) fixture="${RIG_ROOT}/fixtures/light" ;;
  inrepo | plan) fixture="${RIG_ROOT}/fixtures/light-${variant}" ;;
  *) rig_die "unknown variant: ${variant} — expected base|inrepo|plan" ;;
esac
repo="${fixture}/repo"

[ -d "${src}" ] || rig_die "missing authored fixture source: ${src}"
guard_not_real_repo "${repo}"

if [ -e "${repo}" ]; then
  [ "${force}" -eq 1 ] || rig_die "fixture exists: ${repo} — pass --force to rebuild"
  rm -rf -- "${repo}"
fi
mkdir -p -- "${repo}"

# `git -C` everywhere, and identity pinned locally: the fixture's history must
# not depend on the host's git identity being configured, and must never adopt
# it silently.
git -C "${repo}" init --quiet --initial-branch=mainline
git -C "${repo}" config --local user.name "ledger fixture"
git -C "${repo}" config --local user.email "fixture@spike-capsule.invalid"
git -C "${repo}" config --local commit.gpgsign false

# The authored source carries `gitignore`, not `.gitignore`. A dotfile there
# would be a live ignore rule inside THIS repository's tree; it becomes a real
# `.gitignore` only once it is inside the fixture.
install -m 644 "${src}/gitignore" "${repo}/.gitignore"

commit() { git -C "${repo}" commit --quiet -m "[add] $1"; }

# ── commit 1 — scaffold ──────────────────────────────────────────────────────
install -m 644 "${src}/package.json" "${src}/tsconfig.json" "${src}/README.md" "${repo}/"
git -C "${repo}" add .gitignore package.json tsconfig.json README.md
commit "ledger scaffold — npm scripts, strict tsconfig"

# ── commit 2 — the failing test ──────────────────────────────────────────────
mkdir -p -- "${repo}/src"
install -m 644 "${src}/src/money.test.ts" "${repo}/src/"
git -C "${repo}" add src/money.test.ts
commit "failing test for cents conversion and rendering"

# RED, OBSERVED. A red→green claim backed by nothing but commit subjects is a
# claim about commit subjects. `money.ts` does not exist yet, so the import
# fails and `npm test` must be nonzero HERE.
printf 'observing RED at %s\n' "$(git -C "${repo}" rev-parse --short HEAD)"
if (cd "${repo}" && npm test) >/dev/null 2>&1; then
  rig_die "red step passed — the failing test does not fail (fixture is vacuous)"
fi
printf '  ok    npm test fails before the implementation lands\n'

# ── commit 3 — the implementation ────────────────────────────────────────────
install -m 644 "${src}/src/money.ts" "${repo}/src/"
mkdir -p -- "${repo}/tools"
install -m 644 "${src}/tools/format.mjs" "${repo}/tools/"
git -C "${repo}" add src/money.ts tools/format.mjs
commit "cents conversion, rendering, and a formatter"

printf 'observing GREEN at %s\n' "$(git -C "${repo}" rev-parse --short HEAD)"
(cd "${repo}" && npm test) >/dev/null 2>&1 ||
  rig_die "green step failed — HEAD does not pass its own suite"
printf '  ok    npm test passes at HEAD\n'

# ── doctrine ─────────────────────────────────────────────────────────────────
# A-install: `doctrine install` works in non-Rust projects (operator ruling), so
# a failure here is a real POL-002 finding, not an expected snag.
doctrine_bin="${DOCTRINE_BIN:-$(rig_repo_root)/target/debug/doctrine}"
[ -x "${doctrine_bin}" ] || rig_die "no doctrine binary at ${doctrine_bin}"

"${doctrine_bin}" install --path "${repo}" --yes >/dev/null ||
  rig_die "doctrine install failed on a non-Rust project — POL-002 finding, STOP and consult"

"${doctrine_bin}" slice new "Ledger rounding" --path "${repo}" >/dev/null
"${doctrine_bin}" slice selector add 1 'src/**' \
  --intent design-target --path "${repo}" >/dev/null
# H5 needs conform leg 3 (`forbidden-path`) to be REACHABLE on this fixture, and
# with `src/**` alone it is not: a `.doctrine/` plant is refused by leg 2 as
# `undeclared-path` first, making H5/light a restatement of H4/light (F-P05-14,
# D-P05-9). Leg 3 is load-bearing precisely where a selector declares a path it
# then forbids, so the fixture has to be able to express that condition.
#
# `design-target` and not `scope-relevant`: only design-target clears
# conformance `--strict`, so a scope-relevant selector would still report
# undeclared and leave leg 2 refusing first — the same dead end, reached by a
# subtler route (mem: only design-target selectors clear conformance --strict).
"${doctrine_bin}" slice selector add 1 '.doctrine/**' \
  --intent design-target --path "${repo}" >/dev/null

git -C "${repo}" add -A
commit "doctrine install, scratch slice SL-001, design-target selectors"

# ── declaration, OUTSIDE the repo ────────────────────────────────────────────
install -m 644 "${src}/interpretation-surface.txt" "${fixture}/interpretation-surface.txt"

# ── the variant delta (PHASE-05 T1) ──────────────────────────────────────────
#
# Both variants add exactly one commit to the base sequence. Neither carries a
# payload, and neither reuses the trusted-side `npm` build loop above — S3's
# condition on the inherited DQ-4 exemption. Payloads go into a capsule's result
# tree per cell, never into a fixture build.
case "${variant}" in
  base) ;;

  inrepo)
    # F2 — the same declaration, ALSO inside the repo and committed. In the base
    # fixture the declaration is unreachable from a capsule, so F-5 is not live
    # and guard probe (e) has nothing to attack; this variant manufactures the
    # exposure, simulating QUE-201's candidates 1 and 2 (a `doctrine.toml` block
    # and a dedicated manifest both live in the repository the capsule clones).
    #
    # Copied from the SAME authored source as the sibling, so "byte-identical at
    # provision" is a property of the build rather than of a second edit — and
    # the invariant probe (e) tests is that the trusted side reads `B`, never `S`.
    install -m 644 "${src}/interpretation-surface.txt" "${repo}/interpretation-surface.txt"
    git -C "${repo}" add interpretation-surface.txt
    commit "in-repo interpretation-surface copy — the F-5 exposure, made live"
    ;;

  plan)
    # F3 — SL-001 gains a plan with one phase, driven to `completed`. Design
    # § 5.3's "a fixture needs no plan and no phases" is scoped to the PIPELINE,
    # where `prepare-review`'s phase-completion gate is out of scope; the H10/H16
    # sub-probe runs `prepare-review` explicitly and so must meet it.
    #
    # The scaffolded PHASE-01 is left as authored — empty `name`/`objective` are
    # what `doctrine slice plan` writes, `validate` reads the corpus clean, and
    # the criterion is a phase that exists and completes, not a phase that says
    # something. Filling it would be the rig asserting its own prose.
    "${doctrine_bin}" slice plan 1 --path "${repo}" >/dev/null
    "${doctrine_bin}" slice phases 1 --path "${repo}" >/dev/null
    "${doctrine_bin}" slice status 1 started --path "${repo}" >/dev/null
    "${doctrine_bin}" slice phase 1 PHASE-01 --status in_progress --path "${repo}" >/dev/null
    "${doctrine_bin}" slice phase 1 PHASE-01 --status completed --path "${repo}" >/dev/null

    git -C "${repo}" add .doctrine
    commit "plan for SL-001 with PHASE-01 driven to completed"
    ;;
esac

# ── assertions (EX-4, EX-5) ──────────────────────────────────────────────────
printf 'asserting light-fixture invariants (EX-4, EX-5) — variant %s\n' "${variant}"
rig_assert_eq "trunk is 'mainline', not this repo's convention" \
  "mainline" "$(git -C "${repo}" branch --show-current)"
rig_assert_eq "every commit uses the '[add] …' style" \
  "0" "$(git -C "${repo}" log --format=%s | command grep -cv '^\[add\] ' || true)"
# Each variant adds exactly ONE commit. Asserting the count rather than a floor
# is what catches a delta that committed twice, or one that never committed at
# all and is sitting in a working tree the next assertion then calls clean.
expected_commits=4
[ "${variant}" = base ] || expected_commits=5
rig_assert_eq "history is the red→green→install sequence plus this variant's delta" \
  "${expected_commits}" "$(git -C "${repo}" rev-list --count HEAD)"

# Each script is RUN, not merely read out of package.json. Asserting that a key
# exists proves the fixture was authored; asserting it exits zero proves the
# fixture works — and the two came apart here (`build`/`lint` were declared and
# broken, because `tsc` cannot resolve `node:test` without @types/node).
# `clean` runs last: it deletes what `build` produced.
for script in build lint format test clean; do
  rig_assert "npm run ${script} succeeds" \
    npm --prefix "${repo}" run --silent "${script}"
done

rig_assert "doctrine is installed (.doctrine/ present)" test -d "${repo}/.doctrine"
# Both selectors, and the SECOND is not decoration: `.doctrine/**` is what makes
# conform leg 3 reachable on this fixture at all (D-P05-9). Asserted so a future
# rebuild cannot quietly drop it and leave H5 restating H4.
rig_assert_eq "the scratch slice declares src/** and .doctrine/** as design-target" \
  "$(printf 'src/** design-target\n.doctrine/** design-target')" \
  "$("${doctrine_bin}" slice selector list 1 --path "${repo}" --color never |
    tr -s ' ' | sed 's/ *-$//;s/ *$//')"
rig_assert "working tree is clean after provisioning" \
  test -z "$(git -C "${repo}" status --porcelain)"

rig_assert "declaration is present, as a sibling of the repo" \
  test -f "${fixture}/interpretation-surface.txt"

if [ "${variant}" = inrepo ]; then
  rig_assert "declaration is ALSO inside the repo — the F-5 exposure probe (e) attacks" \
    test -f "${repo}/interpretation-surface.txt"
  # Present-but-untracked would be an exposure a capsule never sees: it clones
  # the repo, so only what is COMMITTED is reachable from inside one.
  rig_assert "the in-repo copy is TRACKED, not merely present" \
    git -C "${repo}" ls-files --error-unmatch interpretation-surface.txt
  rig_assert "the two copies are byte-identical at provision — probe (e) compares against this" \
    cmp -s "${fixture}/interpretation-surface.txt" "${repo}/interpretation-surface.txt"
else
  rig_assert "declaration is OUTSIDE the repo (F-5 not live in this variant)" \
    test ! -e "${repo}/interpretation-surface.txt"
fi

if [ "${variant}" = plan ]; then
  rig_assert "SL-001 carries an authored plan" \
    test -f "${repo}/.doctrine/slice/001/plan.toml"
  rig_assert "the plan is TRACKED — a clone of the fixture must carry it" \
    git -C "${repo}" ls-files --error-unmatch .doctrine/slice/001/plan.toml
  # Read through the CLI, not out of the tracking TOML: the gate's own view is
  # the one that matters, and the rig has no business parsing runtime storage.
  rig_assert_eq "PHASE-01 reads completed — prepare-review's phase-completion gate" \
    "1/1" \
    "$("${doctrine_bin}" slice status 1 --path "${repo}" --color never |
      sed -n 's/.*phases: //p' | head -1)"
  # Load-bearing for T5, and asserted rather than commented because it is the
  # kind of fact a sub-probe discovers the expensive way: the completion lives in
  # RUNTIME state (`.doctrine/state/`, gitignored), so it is a property of THIS
  # directory. A sub-probe that cloned the fixture first would find no completed
  # phase and read the gate's refusal as a finding about the candidate layer.
  rig_assert_fails "phase tracking is runtime state, NOT committed — completion does not survive a clone" \
    git -C "${repo}" ls-files --error-unmatch .doctrine/state/slice/001/phases/phase-01.toml
fi

rig_assert_done "fixture-light (${variant})"
printf 'light fixture (%s) ready: %s at %s\n' \
  "${variant}" "${repo}" "$(git -C "${repo}" rev-parse HEAD)"
