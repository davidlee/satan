#!/usr/bin/env bash
# pi-reap.sh — completion poll and reap for the pi `--mode rpc` spawn arm.
#
# SOURCED, never executed. Provides one function, `pi_await_and_reap`, shared by
# pi-spawn.sh, spawn-confined.sh, pi-respawn-nofork.sh and pi-review.sh —
# every script that runs `pi --mode rpc` behind a fifo. It was four byte-identical
# copies before this file existed, which is how CHR-051's fixes came to be applied
# to two of the four while pi-respawn-nofork.sh kept the original defects.
#
# NOT for the `--print` arm (pi-agent, and its pi-scout / pi-research shims):
# `--print` self-exits once stdin closes and needs no fifo, poll, or reap.
#
# Two preconditions the caller MUST meet:
#
#   1. `set -m` before its FIRST background job, so both the pi job and the
#      fifo-holding job are process-group leaders. The group kills below are
#      no-ops otherwise and the reap silently reverts to the ISS-293 behaviour.
#   2. Call from the shell that owns both pids — not a subshell or a pipeline.
#      `wait` only works on the calling shell's own children. The trap here is
#      `report=$(pi_await_and_reap …)`: command substitution IS a subshell, so
#      the reap silently degrades to leaving zombies at exactly the moment you
#      wanted to inspect its output. Redirect to a file and read that instead.
#
# Usage:
#   . "$SCRIPT_DIR/lib/pi-reap.sh"
#   pi_await_and_reap "$OUT" "$PI" "$KEEP" "$D/.pi-session" "$BACKSTOP" "[spawn]"

# shellcheck shell=bash

# Is any live process still holding this spawn's --session-dir?
#
# `pgrep -f` reads /proc/<pid>/cmdline directly, so it needs neither a pipeline
# nor the `[-]-` self-exclusion trick the old `ps -eo args | grep` form used.
# procps arrived in the jail with flake.nix deb2cf44; before that this had to be
# `ps | grep` and carried an SC2009 suppression.
#
# Note the hazard both forms share: the pattern is matched against every process's
# full command line, so a CALLER whose own argv happens to contain this text would
# match itself. The spawn scripts derive the session dir internally rather than
# taking it as an argument, so none of them can.
session_dir_held() {
  pgrep -f -- "--session-dir $1" >/dev/null 2>&1
}

pi_await_and_reap() {
  local out=$1 pi=$2 keep=$3 session_dir=$4 backstop=$5 tag=$6
  local start end reason elapsed

  # Validate the pids BEFORE any signal, and never paper over a missing one with
  # a `${pi:-0}` style fallback: `0` is not an inert pid here. `kill -9 -0`
  # signals the CALLER'S OWN process group, so this shared function would fell
  # the orchestrator that invoked it — the guard would destroy exactly what it
  # exists to protect. `1` is init. Refuse both, and anything non-numeric.
  # See mem.pattern.shell.default-must-be-inert-in-its-consumer.
  case $pi in '' | *[!0-9]*) echo "$tag ERROR: invalid pi pid '$pi'" >&2; return 2 ;; esac
  case $keep in '' | *[!0-9]*) echo "$tag ERROR: invalid keep pid '$keep'" >&2; return 2 ;; esac
  if [ "$pi" -le 1 ] || [ "$keep" -le 1 ]; then
    echo "$tag ERROR: refusing to signal pid <= 1 (pi=$pi keep=$keep)" >&2
    return 2
  fi

  # Poll the TAIL, not the whole file. pi's rpc stream re-serializes accumulated
  # conversation state on every event, so $out grows super-linearly — 50-150MB
  # for an ordinary turn is normal, not a runaway. `grep -q` over the whole file
  # every 2s therefore costs more I/O than the model costs tokens, and it
  # degrades as the turn goes on.
  #
  # The terminal event is `agent_settled`, NOT `agent_end` (ISS-293). `agent_end`
  # carries the accumulated state with it, so it is pushed arbitrarily far back
  # from EOF as the turn grows: measured 684,768 bytes from EOF on one census
  # turn. A 128KiB window is 5.2x too small and the poll NEVER fires on a real
  # turn — every spawn runs to the backstop holding a live pi and an open API
  # session, and nothing warns, because the output lands on time so it looks
  # clean. `agent_settled` is a bare `{"type":"agent_settled"}` 17 bytes from EOF
  # and is robust to any window; matching either keeps this working if the order
  # changes again. 4MiB at a 2s cadence is still four orders of magnitude below
  # the file.
  start=$(date +%s)
  end=$((start + backstop))
  reason=timeout
  while [ "$(date +%s)" -lt "$end" ]; do
    if tail -c 4194304 "$out" 2>/dev/null | grep -qE '"(agent_settled|agent_end)"'; then
      reason=agent_complete
      break
    fi
    if ! kill -0 "$pi" 2>/dev/null; then
      reason=pi_exit
      break
    fi
    sleep 2
  done

  # Negative pid = signal the whole process group (see precondition 1). The chain
  # is timeout -> [bwrap ->] wrapper -> pi, so the caller's $! is the TIMEOUT; a
  # bare `kill -9` fells only that and leaves the real pi alive as an orphan
  # holding its API session — and a background `wait` on the spawning script does
  # not return until that orphan dies, so completion arrives minutes late and the
  # job looks like it is still running. Observed: two orphans alive 16 minutes
  # after both had written output. `bwrap --die-with-parent` did not cover it.
  # Fall back to the bare pid if the group is already gone. $keep is group-killed
  # for the same reason: its `sleep $backstop` child is the orphan that outlives
  # a bare kill and holds the caller's stderr open.
  #
  # `setsid` would also give each job its own group but is ABSENT from this jail
  # — do not "simplify" to it, and do not go back to a bare kill (CHR-051 §2).
  kill -9 -"$pi" 2>/dev/null || kill -9 "$pi" 2>/dev/null
  kill -9 -"$keep" 2>/dev/null || kill -9 "$keep" 2>/dev/null
  # `kill -9` only QUEUES the signal. Without this `wait`, $pi and $keep — the
  # caller's own children — linger as zombies that `ps` still lists, and the belt
  # below reports a survivor that is already dead (ISS-294).
  wait "$pi" "$keep" 2>/dev/null

  # Settle: the grandchildren (timeout -> bwrap -> wrapper -> pi) are NOT the
  # caller's children and cannot be waited on, so give the group kill a bounded
  # window to land before believing `ps`.
  local _
  for _ in 1 2 3 4 5; do
    session_dir_held "$session_dir" || break
    sleep 0.2
  done

  # Belt: confirm nothing from this spawn outlived the reap. A surviving pi holds
  # an API session open and silently blocks any caller that `wait`s on the script.
  if session_dir_held "$session_dir"; then
    echo "$tag WARNING: pi survived the reap for $session_dir" >&2
  fi

  # Elapsed-vs-backstop is the ONLY signal that distinguishes a clean early
  # finish from a silent full-backstop burn — the output lands either way, so
  # without this line the operator has to catch it in `ps` (ISS-293). This is
  # what made the poll defect above invisible for as long as it was.
  elapsed=$(($(date +%s) - start))
  echo "$tag terminated reason=$reason after ${elapsed}s of ${backstop}s backstop"
  if [ "$reason" = timeout ]; then
    echo "$tag WARNING: burned the full backstop — completion never detected" >&2
  fi
}
