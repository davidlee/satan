#!/usr/bin/env bash
# drivers/falsify-t6.sh — the falsifiability round for the five guard probes
# (SL-241 PHASE-05 T6).
#
#   usage: drivers/falsify-t6.sh            (writes its sweep to stdout)
#   env:   SPIKE_CAPSULE_ROOT   default ~/capsules-shake — NEVER the scored root
#
# Four mutants, each wrapping ONE named seam and calling through. Every one
# asserts a red AND an isolation control naming what still held: the red says a
# clause noticed, the control says which clause was load-bearing and which would
# have scored the defect green.
#
# Run AFTER shakeout and BEFORE scoring (F-P05-31).
#
# ── the probe selector, and why it is set HERE ──────────────────────────────
#
# `FX_PROBE`/`FX_MUTANT_ENV` retarget `falsify-lib.sh` from P-C3 onto `rig
# guards`. Stated once at the top rather than threaded through every call: the
# whole sweep perturbs one probe, and a per-run parameter would be the same two
# strings repeated four times with nothing choosing between them.
#
# ── guard (a) has no mutant, and that is not an omission ────────────────────
#
# It is a CITATION, and its falsifiability is already inside the leg: the
# negative control asserts the counter returns zero for a conform token H8 never
# produced. A mutant that emptied `probes/c3/results.tsv` would red the
# existence clause, which is a fact about the file rather than about the
# citation's reasoning — the leg's own discriminator is the stronger check and
# it runs on every invocation, not only under a sweep.
set -euo pipefail

FX_HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=falsify-lib.sh
. "${FX_HERE}/falsify-lib.sh"

FX_PROBE=guards
FX_MUTANT_ENV=SPIKE_GUARDS_MUTANT

M="${FX_HERE}/mutants"

printf 'falsify T6 — four mutants, root %s\n' "${FX_ROOT}"

# ── M36 — a second governance path in guard (b)'s range ─────────────────────
#
# The isolation clause is the ONLY thing separating guard (b) from a re-run of
# H5, and this is the run that proves it: the refusal and the ingestion both
# stay green while the observation has quietly become about a different path.
fx_case m36 "${M}/m36-second-governance-path.sh" b
fx_show 16
fx_red_on 'm36: the isolation clause REDS — two governance paths in the range' \
  'EXACTLY ONE governance path'
fx_held 'm36 isolation: leg 3 STILL refuses forbidden-path — the token cannot see which path' \
  'REFUSES the non-ASCII governance path'
fx_held 'm36 isolation: … and the non-ASCII path was still ingested, so nothing else noticed' \
  'is in the range the trusted side folded'

# ── M37 — the evasion view is not the evasion view ──────────────────────────
fx_case m37 "${M}/m37-rename-detection-blind.sh" c
fx_show 16
fx_red_on 'm37: the vanishing clause REDS — the source no longer hides' \
  'SOURCE has VANISHED'
fx_held 'm37 isolation: the pipeline STILL refuses forbidden-path' \
  'REFUSES the renamed-out governance path'
fx_held 'm37 isolation: … so the refusal alone never carried the --no-renames claim' \
  'both legs of the rename are in'

# ── M38 — guard (d) with an honest suite ────────────────────────────────────
#
# The one mutant here that falsifies a leg's DESIGN rather than one of its
# clauses. Both I4a-flavoured controls hold while the guard goes unexercised.
fx_case m38 "${M}/m38-suite-not-broken.sh" d
fx_show 16
fx_red_on 'm38: the verdict clause REDS — with an honest suite there is no refusal to observe' \
  "the verdict is the RO-BOUND runner's"
fx_held 'm38 isolation: audit-i4a STILL refuses the mutated capsule — the static half is indifferent' \
  'audit-i4a REFUSES the mutated capsule'
fx_held 'm38 isolation: … and the planted runner still exits 0, so both controls look like proof' \
  'had it been the verdict'

# ── M39 — the control plane reads the capsule's declaration ─────────────────
#
# QUE-201's defect, injected. This is the run that makes guard (e)'s comparison
# unequal, and without it a byte-identical result would be unfalsifiable.
fx_case m39 "${M}/m39-trusted-side-reads-capsule.sh" e
fx_show 20
fx_red_on "m39: the provenance clause REDS — the resolved command is the capsule's" \
  "resolved B's command, never the capsule's"
fx_red_on 'm39: … and the byte-identical comparison REDS with it' \
  'BYTE-IDENTICAL to the F1 baseline'
fx_held 'm39 isolation: the F1 BASELINE is untouched — F1 has no in-repo copy to prefer' \
  'the baseline run refuses NOWHERE'
fx_held 'm39 isolation: … so the reds are attributable to the substitution, not to the overlay' \
  'verify is recorded PASSED'

rig_assert_done 'falsify-t6'
