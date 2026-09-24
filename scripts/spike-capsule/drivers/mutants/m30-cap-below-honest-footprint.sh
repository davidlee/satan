#!/usr/bin/env bash
# M30 — THE CAP IS SET BELOW THE HONEST FOOTPRINT.
#
# 128 MiB, under the heavy capsule's measured 201M and well over light's 1.5M.
# The vehicle sizes its blob off `ulimit -f`, so the refusal is UNCHANGED on
# both fixtures — what moves is whether the row can still attribute it.
#
# Under test: `H7_planted`'s cumulative clause, which is D-P05-18's attribution
# control. It must red on HEAVY and hold on LIGHT: a clause that reported the
# same thing under both would not be measuring the capsule at all.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

# Consumed by `c3_row_worker_disk_cap` and `H7_planted` in the harness this
# overlay is loaded into, which shellcheck cannot see from here.
# shellcheck disable=SC2034
C3_H7_WORKER_CAP=$((128 * 1024 * 1024))
