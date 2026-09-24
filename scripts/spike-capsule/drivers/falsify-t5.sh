#!/usr/bin/env bash
# drivers/falsify-t5.sh — the falsifiability round for the H10/H16 conflict
# sub-probe (SL-241 PHASE-05 T5).
#
#   usage: drivers/falsify-t5.sh            (writes its sweep to stdout)
#   env:   SPIKE_CAPSULE_ROOT   default ~/capsules-shake — NEVER the scored root
#
# Four mutants, two per row, each wrapping ONE thing and calling through. Every
# one asserts a red AND an isolation control naming what still held: the red
# says a clause noticed, the control says which clause was load-bearing and
# which would have scored the defect green.
#
# Run AFTER shakeout and BEFORE scoring (F-P05-31).
#
# ── the legs selector, and why it is set HERE ───────────────────────────────
#
# `SPIKE_C3_LEGS=conflict` for the whole sweep. H10 and H16 are `harness=both`
# rows, so an unselected run would also drive their four PIPELINE cells — legs
# that are already scored, that no mutant here perturbs, and whose reds would
# arrive in the same capture as the sub-probe's. Exported rather than threaded
# through `fx_run`: `rig` execs the probe with the environment intact, so the
# existing runner needs no fifth parameter for one caller.
set -euo pipefail

FX_HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=falsify-lib.sh
. "${FX_HERE}/falsify-lib.sh"

export SPIKE_C3_LEGS=conflict

M="${FX_HERE}/mutants"

# `fx_case` was `t5_run`, local here, on the "one caller does not earn a library
# entry" rule. T6 became the second caller and it moved to `falsify-lib.sh`
# exactly as that note said it would — same body, same behaviour.
printf 'falsify T5 — four mutants, root %s\n' "${FX_ROOT}"

# ── M32 — canonical's half is not from B ────────────────────────────────────
fx_case m32 "${M}/m32-peer-not-from-b.sh" H10
fx_show 12
fx_red_on 'm32: the parentage clause REDS — the peer is no longer a child of B' \
  'child of B'
fx_held 'm32 isolation: the pair STILL conflicts, and is still classified Conflicted' \
  'records the Conflicted classification'
fx_held 'm32 isolation: … so the conflict itself was never what the clause was watching' \
  'the two halves DISAGREE'

# ── M33 — the two halves agree ──────────────────────────────────────────────
#
# The classification clause's only chance to be wrong: this is the run where the
# row is legitimately `created` rather than `conflicted`.
fx_case m33 "${M}/m33-halves-agree.sh" H10
fx_show 12
fx_red_on 'm33: the classification REDS — the ledger says created, not conflicted' \
  'records the Conflicted classification'
fx_red_on 'm33: … and its positive control reds with it, which is correct' \
  'the two halves DISAGREE'
fx_held 'm33 isolation: the pair is still from ONE base — only the CONTENT changed' \
  'child of B'
fx_held 'm33 isolation: … and F3 still cleared the phase-completion gate' \
  'phase-completion gate'

# ── M34 — trunk never moves ─────────────────────────────────────────────────
fx_case m34 "${M}/m34-trunk-never-moves.sh" H16
fx_show 14
fx_red_on 'm34: the staleness control REDS — nothing advanced past the pinned base' \
  'canonical moved to a CHILD'
fx_red_on 'm34: … and integrate takes the fast-forward it was refusing' \
  'integrate refuses a close target'
fx_held 'm34 isolation: BOTH admissions still hold — admission never noticed either way' \
  'accepts the close target with trunk already moved'

# ── M35 — the move happens before the candidates pin B ──────────────────────
#
# The pair to M34, and the contrast is the finding: the hazard is INTACT here —
# the trunk really did advance, on the same disjoint path — so the planted
# control holds while the refusal reds. A leg asserting only "it moved and
# integrate refused" would score this green.
fx_case m35 "${M}/m35-move-before-pinning.sh" H16
fx_show 14
fx_red_on 'm35: the refusal REDS — a candidate minted on the moved base fast-forwards' \
  'integrate refuses a close target'
fx_held 'm35 isolation: the advance STILL HAPPENED — the planted control cannot see order' \
  'canonical moved to a CHILD'
fx_held 'm35 isolation: … which is precisely why the refusal clause is load-bearing' \
  'it moved on a path the result never names'

rig_assert_done 'falsify-t5'
