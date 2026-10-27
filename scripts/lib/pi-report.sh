#!/usr/bin/env bash
# pi-report.sh — the one place a spawn script renders a worker's raw event stream.
#
# SOURCED, never executed. `pi_report <stream> [tag]` reduces the stream to what
# an orchestrator needs — tool calls, the final answer, alert lines — and prints
# it. It replaces the `tail -40` these scripts used to do: the raw stream is a
# wire log of 175 KB+ per small turn and ~72% of it is context echo, so forty
# lines from the tail is the least useful window in the file.
#
# Artefacts (transcript.md, status.json) go to a fresh temp dir — never under the
# worker's worktree, where untracked files would land in the delta the
# orchestrator imports. The reducer's status line names that path.
#
# Env:
#   PI_ALERTS              space-separated regexes to warn about, e.g. 'FAIL|\.doctrine/'
#   PI_REDUCE              reducer command, split on whitespace; its first word must
#                          be executable, so paths with spaces are unsupported
#                          (default: quotient reduce)
#   PI_REPORT_TAIL_LINES   fallback tail length (default 40)
#
# The reducer is quotient's `reduce` subcommand, a self-contained launcher (no
# node needed on PATH). Where it is unavailable (a jail without quotient, a
# host without the flakes agents.quotient feature) this degrades to the old
# tail rather than reporting nothing: a noisy report beats a silent one.
#
# Only pi `--mode json` / `--mode rpc` streams reduce. The claude arm emits a
# different event schema, so spawn-confined.sh calls this on the pi arm only.
# shellcheck shell=bash

pi_report() {
  local stream=$1 tag=${2:-[spawn]}
  local -a reduce
  read -ra reduce <<<"${PI_REDUCE:-quotient reduce}"

  if [ -n "${reduce[0]:-}" ] && command -v "${reduce[0]}" >/dev/null; then
    # Bash 3.2 (the macOS arm) errors on expanding an empty array under `set -u`,
    # hence the ${alerts[@]+...} form.
    local alerts=() pattern
    for pattern in ${PI_ALERTS:-}; do alerts+=(--alert "$pattern"); done
    echo "----- $tag report -----"
    # The reducer exits non-zero on a failed or incomplete run; that verdict is
    # the caller's to interpret, not a reason to abort the spawn script.
    "${reduce[@]}" -v --out "$(mktemp -d)" ${alerts[@]+"${alerts[@]}"} "$stream" || true
    return 0
  fi

  echo "----- $tag tail (no reducer: ${reduce[0]:-PI_REDUCE} not executable) -----"
  tail -"${PI_REPORT_TAIL_LINES:-40}" "$stream"
}
