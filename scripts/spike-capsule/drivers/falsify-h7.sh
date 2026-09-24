#!/usr/bin/env bash
# drivers/falsify-h7.sh — the falsifiability round for H7 (SL-241 PHASE-05 T4c).
#
#   usage: drivers/falsify-h7.sh            (writes its sweep to stdout)
#   env:   SPIKE_CAPSULE_ROOT   default ~/capsules-shake — NEVER the scored root
#
# Six mutants, each wrapping ONE thing and calling through. Every one asserts a
# red AND an isolation control naming what still held: the red says a clause
# noticed, the control says which clause was load-bearing and which would have
# scored the defect green.
#
# Run AFTER shakeout and BEFORE scoring (F-P05-31). The round mutates nothing on
# disk that survives it — each mutant is a file the harness sources, so the rig
# under test is byte-identical between this sweep and the scored run.
set -euo pipefail

FX_HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=falsify-lib.sh
. "${FX_HERE}/falsify-lib.sh"

M="${FX_HERE}/mutants"

printf 'falsify H7 — six mutants, root %s\n' "${FX_ROOT}"

# ── M26 — the sandbox never reports the bound ───────────────────────────────
expect_assert m26 "${M}/m26-cap-never-fired.sh" H7 "the capsule's own status is the disk bit"
fx_show 6
fx_held 'm26 isolation: the hostile payload still landed — only the REPORT changed' 'planted\?'

# ── M27 — the oversize is not empty ─────────────────────────────────────────
expect_planted m27 "${M}/m27-oversize-not-empty.sh" H7
fx_held 'm27 isolation: the capsule still died on the disk bit — the refusal is untouched' \
  "the capsule's own status is the disk bit"
fx_held 'm27 isolation: … and the boundary still re-derives' 'the boundary § 5.6 re-derives'

# ── M28 — the capsule died holding nothing ──────────────────────────────────
expect_assert m28 "${M}/m28-no-honest-result.sh" H7 'published a result ref before it died'
fx_show 8
fx_held 'm28 isolation: the TOKEN is unchanged — the boundary still re-derives' \
  'the boundary § 5.6 re-derives'
fx_held 'm28 isolation: … and nothing was ingested, exactly as before' \
  'no result ref in the quarantine'
fx_held 'm28 isolation: … and the payload still landed' 'planted\?'

# ── M29 — the pathological tree never landed ────────────────────────────────
expect_planted m29 "${M}/m29-no-deep-tree.sh" H7
fx_held 'm29 isolation: the blob and the refusal are untouched' \
  "the capsule's own status is the disk bit"

# ── M30 — the cap is set below the honest footprint ─────────────────────────
#
# The one mutant that must red on ONE fixture and hold on the other. Asserted
# both ways over one capture, for `c3_assert_range`'s reason: a clause that
# reported the same thing under both fixtures would not be measuring the
# capsule at all.
expect_planted m30 "${M}/m30-cap-below-honest-footprint.sh" H7
rig_assert 'm30: the HEAVY cell reds — 201M does not fit under 128 MiB' \
  command grep -qE '^  FAIL  H7/heavy.*planted\?' <<<"${FX_OUT}"
rig_assert 'm30 isolation: the LIGHT cell HOLDS — 1.5M still does, so the clause measures the capsule' \
  command grep -qE '^  ok    H7/light.*planted\?' <<<"${FX_OUT}"
fx_held 'm30 isolation: and the refusal is unchanged under both — the vehicle sizes off ulimit' \
  "the capsule's own status is the disk bit"

# ── M31 — canonical gains the capsule's objects ─────────────────────────────
expect_assert m31 "${M}/m31-canonical-gains-objects.sh" H7 'canonical OBJECT COUNT unchanged'
fx_show 12
fx_held 'm31 isolation: canonical REFS are unchanged — the refs clause is BLIND to it' \
  'canonical refs unchanged'
fx_held 'm31 isolation: every clause of the ROW still held — the row cannot see this' \
  'no result ref in the quarantine'

rig_assert_done 'falsify H7'
