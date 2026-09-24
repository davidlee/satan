#!/usr/bin/env bash
# drivers/rebind.sh — the one primitive every mutant is built from.
# SOURCED by a mutant overlay, never executed.
#
# `rebind <fn>` copies <fn> to `real_<fn>`, leaving <fn> free to be redefined as
# a WRAPPER that perturbs and then calls through. That indirection is the whole
# discipline: a mutant which restated the body would prove its own copy was
# broken, and say nothing about the function the harness actually runs.
#
# Fails CLOSED on a name that does not exist — a mutant silently wrapping
# nothing is a green falsification round that proved nothing, which is worse
# than a red one.

rebind() {
  local fn=${1:?rebind: function name required}
  declare -F "${fn}" >/dev/null ||
    rig_die "rebind: no such function: ${fn} (renamed? then the mutant is stale)"
  eval "real_${fn}() $(declare -f "${fn}" | tail -n +2)"
}
