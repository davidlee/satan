#!/usr/bin/env bash
# M37 — THE EVASION VIEW IS NOT THE EVASION VIEW.
#
# `guards_range_rename_aware` is the ONE place guard (c) looks at the range
# through git's rename detector. Rebound to the belt's own `--no-renames` form,
# it now returns a range in which the `.doctrine/` source is still present.
#
# Under test: the both-directions clause. Guard (c)'s claim is not merely "leg 3
# refused" — it is "leg 3 refused AND the source genuinely hides when rename
# detection is on, so `--no-renames` is load-bearing". Only the second half can
# distinguish a belt that needs the flag from one that happens to have it, and
# only this clause carries it.
#
# The isolation control is the pipeline refusal, which is untouched: the run
# still lands `conform/forbidden-path`. A leg asserting the refusal alone would
# score this mutant green while having shown nothing about the flag at all.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../rebind.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../rebind.sh"

rebind guards_range_rename_aware
guards_range_rename_aware() { c3_range "$@"; }
