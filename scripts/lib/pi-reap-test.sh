#!/usr/bin/env bash
# pi-reap-test.sh — behavioural test for pi_await_and_reap (scripts/lib/pi-reap.sh).
#
# The function is shared by all four `--mode rpc` spawn scripts, and its failure
# mode is silent: a broken reap leaves an orphaned pi holding an API session, and
# the spawn still reports success because the output file lands either way. That
# is exactly how ISS-293 stayed invisible. So it gets a test.
#
# No pi, no API, no network: the real chain (`timeout` -> bwrap -> wrapper -> pi)
# is stood up with `timeout` -> `sh` -> `sleep`, which reproduces the property
# that matters — the thing to be killed is a GRANDCHILD, so a bare `kill` on the
# shell's own `$!` misses it.
#
# Usage: scripts/lib/pi-reap-test.sh    (exit 0 = pass)
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/pi-reap.sh
. "$SCRIPT_DIR/pi-reap.sh"

REPORT=$(mktemp)
ERRLOG=$(mktemp)
trap 'rm -f "$REPORT" "$ERRLOG"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL — $1" >&2; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

# Stand up a caller-shaped fixture: a fifo-holding $KEEP with a `sleep` child,
# and a `timeout -> sh -> sleep` chain whose leaf carries a --session-dir marker.
# Mirrors the spawn scripts exactly, `set -m` included.
spawn_fixture() {
  sess=$1
  out=$(mktemp)
  fifo=$(mktemp -u) && mkfifo "$fifo"
  set -m
  { printf 'prompt\n'; sleep 60; } >"$fifo" &
  KEEP=$!
  timeout 60 sh -c "exec sleep 60 # --session-dir $sess" <"$fifo" >"$out" 2>&1 &
  PI=$!
  sleep 0.4
}

# The report is captured by REDIRECTING to a file, never with `$(...)`. Command
# substitution runs the function in a SUBSHELL, where the fixture pids are not
# children, so its `wait` cannot reap them — zombies survive and bash announces
# them ("Killed ..."). That is the function's second documented precondition, and
# it is easy to trip precisely when you want to assert on the output.
run_reap() {
  local rc=0
  pi_await_and_reap "$@" >"$REPORT" 2>"$ERRLOG" || rc=$?
  return "$rc"
}

# Every pid in either job's process group == everything the fixture spawned.
fixture_pids() {
  ps -eo pid,pgid --no-headers 2>/dev/null |
    awk -v a="$KEEP" -v b="$PI" '$2==a||$2==b {print $1}' | sort -n
}

echo "1. reaps the whole tree, including the grandchild and the fifo holder"
spawn_fixture "reaptest-tree-$$"
before=$(fixture_pids | tr '\n' ' ')
run_reap "$out" "$PI" "$KEEP" "reaptest-tree-$$" 60 "[test]"
sleep 0.5
survivors=""
for p in $before; do kill -0 "$p" 2>/dev/null && survivors="$survivors $p"; done
check "no survivors from the fixture" "${survivors:-none}" "none"
zomb=$(ps -eo stat,pgid --no-headers 2>/dev/null |
  awk -v a="$KEEP" -v b="$PI" '($2==a||$2==b) && $1 ~ /^Z/ {n++} END{print n+0}')
check "no zombies left by the queued SIGKILL" "$zomb" "0"
if grep -q "survived the reap" "$ERRLOG"; then bad "no spurious survivor warning"
else ok "no spurious survivor warning"; fi
rm -f "$out" "$fifo"

echo "2. detects agent_settled far from EOF (the ISS-293 regression)"
spawn_fixture "reaptest-settled-$$"
# agent_settled at EOF, preceded by more than the old 128KiB window of padding —
# the exact geometry that made the original poll never fire.
head -c 700000 /dev/zero | tr '\0' 'x' >>"$out"
printf '{"type":"agent_settled"}\n' >>"$out"
start=$(date +%s)
run_reap "$out" "$PI" "$KEEP" "reaptest-settled-$$" 60 "[test]"
elapsed=$(($(date +%s) - start))
case $(cat "$REPORT") in
  *"reason=agent_complete"*) ok "reason=agent_complete" ;;
  *) bad "reason=agent_complete (got: $(cat "$REPORT"))" ;;
esac
if [ "$elapsed" -lt 10 ]; then ok "returned promptly (${elapsed}s), did not burn the backstop"
else bad "burned ${elapsed}s — the poll did not fire"; fi
rm -f "$out" "$fifo"

echo "3. reports elapsed-vs-backstop, and warns when the backstop is burned"
spawn_fixture "reaptest-burn-$$"
run_reap "$out" "$PI" "$KEEP" "reaptest-burn-$$" 2 "[test]"
case $(cat "$REPORT") in
  *"reason=timeout after "*"s of 2s backstop"*) ok "elapsed-vs-backstop reported" ;;
  *) bad "elapsed-vs-backstop reported (got: $(cat "$REPORT"))" ;;
esac
if grep -q "burned the full backstop" "$ERRLOG"; then ok "warned on full-backstop burn"
else bad "warned on full-backstop burn"; fi
rm -f "$out" "$fifo"

echo "4. refuses pids that would signal the caller's own process group"
# `kill -9 -0` signals the CALLER'S group: a ${pi:-0} style fallback here would
# fell the orchestrator. mem.pattern.shell.default-must-be-inert-in-its-consumer.
for badpid in 0 1 "" abc; do
  out=$(mktemp)
  run_reap "$out" "$badpid" 99999 "reaptest-guard-$$" 5 "[test]"
  check "refuses pi='$badpid' (rc 2)" "$?" "2"
  run_reap "$out" 99999 "$badpid" "reaptest-guard-$$" 5 "[test]"
  check "refuses keep='$badpid' (rc 2)" "$?" "2"
  rm -f "$out"
done
# Positive control: this shell must still be alive after all that.
kill -0 $$ 2>/dev/null && ok "caller survived the invalid-pid cases"

echo "5. belt check fires when something still holds the session dir"
# The belt is the one leg whose failure is completely silent: if the detection
# stops working, a surviving pi holding an API session is simply never reported
# and the spawn looks clean. So it gets a decoy that deliberately outlives the
# reap. `; :` defeats sh's exec-through optimisation so the process keeps its own
# argv — the closest stand-in for real pi, which genuinely receives these args.
sess="reaptest-belt-$$"
spawn_fixture "$sess"
sh -c 'sleep 30; :' pi --session-dir "$sess" &
DECOY=$!
sleep 0.3
run_reap "$out" "$PI" "$KEEP" "$sess" 2 "[test]"
if grep -q "WARNING: pi survived the reap for $sess" "$ERRLOG"; then
  ok "warned about the surviving holder"
else
  bad "warned about the surviving holder (stderr: $(cat "$ERRLOG"))"
fi
kill -9 "$DECOY" 2>/dev/null
wait "$DECOY" 2>/dev/null
rm -f "$out" "$fifo"

echo
echo "pi-reap: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
