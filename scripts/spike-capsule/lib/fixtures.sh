#!/usr/bin/env bash
# lib/fixtures.sh — THE FIXTURE TABLE. SOURCED, never executed.
#
# Lifted out of control/probe-c3.sh at PHASE-05 T6, unchanged in behaviour, so
# P-C3 and the guard probes share one table rather than growing two that drift.
# The same move `lib/rows.sh` made at T3, for the same reason and with the same
# bar: a second real caller, not a generalisation invented for one.
#
# ── these are JOINS, not paths (EX-8: a rig PARAMETER, never hardcoded) ─────
#
# Four facts per fixture, and three of them join with something outside the
# fixture directory:
#
#   slice   conform leg 2 folds the result range against THIS slice's
#           design-target selectors, so it must name a slice the fixture's own
#           `.doctrine/` carries — 001 in the `ledger` fixture, 241 in the heavy
#           clone of this repository.
#   stub    where the stub worker writes. A control-plane choice because it is
#           a join with those same selectors: a stub landing outside them makes
#           every cell refuse at conform leg 2 for a reason about the rig
#           rather than about the model (capsule/worker-stub.sh).
#
# A DRIFTING COPY OF THIS TABLE IS THE F-P05-14/18/21 FAILURE, and it is worth
# naming because all three findings were the same mistake at different sites: a
# caller that spelt a fixture's declared surface for itself planted at a path
# the fixture does not declare, the cell refused `undeclared-path`, and the
# results table read that as a defect of the capsule MODEL. One table is the
# structural fix; STD-001 is the rule it satisfies.
#
# ── the four fixtures ───────────────────────────────────────────────────────
#
#   light         F1 — TypeScript, the `ledger` project. The declaration sits
#                 OUTSIDE the repo, as a sibling (F-5's provenance).
#   light-inrepo  F2 — F1 plus a declaration copy INSIDE the repository. The
#                 substitution exposure QUE-201 candidates 1 and 2 describe,
#                 MANUFACTURED because the rig as drawn does not carry it
#                 (EX-11). Guard probe (e)'s subject.
#   light-plan    F3 — F1 plus a plan and a driven phase. The H10/H16 conflict
#                 sub-probe's fixture (EX-15); `prepare-review`'s phase-
#                 completion gate is what it exists for. `lib/conflict.sh`
#                 resolves it itself and does not read this table.
#   heavy         F4 — this repository, Rust. The altitude vocabulary reads off
#                 the light/heavy split: `unproven-beyond-rust` is literally
#                 "heavy only".
#
# `light-inrepo` inherits every light join, and that is the POINT rather than a
# convenience: guard probe (e) compares an F2 run against an F1 run and calls
# them byte-identical trusted-side, so any join that differed between them would
# be a difference the comparison could not distinguish from the attack.

fixture_repo() { printf '%s' "${RIG_ROOT}/fixtures/$1/repo"; }
fixture_declaration() { printf '%s' "${RIG_ROOT}/fixtures/$1/interpretation-surface.txt"; }

fixture_slice() {
  case "$1" in
    light | light-inrepo) printf '001' ;;
    heavy) printf '241' ;;
    *) rig_die "no slice join for fixture: $1" ;;
  esac
}

fixture_stub() {
  case "$1" in
    light | light-inrepo) printf 'src/capsule-stub.ts' ;;
    heavy) printf 'scripts/spike-capsule/capsule-stub.txt' ;;
    *) rig_die "no stub path for fixture: $1" ;;
  esac
}

# The VERIFY capsule's two bounds, per fixture (D-P05-7). Both defaults were
# sized by the LIGHT fixture, and a Rust workspace overruns both — measured at
# 352s and 4.4G, against 300s and 256 MiB. An unnamed overrun does not read as
# "the bound was wrong": the disk leg lands on `verify/resource-cap` and the
# clock leg on `verify/verify-timeout`, and the SECOND of those is a LEGAL
# token, so `assert_outcome` would accept an honest run as a refusal without
# ever announcing itself (F-P05-15). Sized with headroom over the measurement,
# not to it — a cold registry fetch is not a fixed cost.
fixture_verify_timeout() {
  case "$1" in
    light | light-inrepo) printf '300' ;;
    heavy) printf '900' ;;
    *) rig_die "no verify timeout for fixture: $1" ;;
  esac
}

fixture_verify_disk_cap() {
  case "$1" in
    light | light-inrepo) printf '%s' $((256 * 1024 * 1024)) ;;
    heavy) printf '%s' $((8 * 1024 * 1024 * 1024)) ;;
    *) rig_die "no verify disk cap for fixture: $1" ;;
  esac
}
