#!/usr/bin/env bash
# Reusable dispatch pi worker spawn (subprocess arm).
# Breaks on the pi `agent_end` event instead of waiting out the timeout
# (fifo holds stdin open so pi never self-exits; we kill it on completion).
# Usage: pi-spawn.sh <B> <BRANCH> <DIR> <PROMPT_FILE> [BACKSTOP_SECS]
set -u
B="$1"
BR="$2"
D="$3"
PF="$4"
BACKSTOP="${5:-1800}"
ROOT=/workspace/doctrine
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# The rpc poll/reap lives in one place for all four spawn scripts — it was four
# byte-identical copies, and that is how CHR-051 came to be fixed in two of them.
# Preconditions it relies on: `set -m` before the first background job (below),
# and being called from this shell so `wait` can reach our own children.
# shellcheck source=scripts/lib/pi-reap.sh
. "$SCRIPT_DIR/lib/pi-reap.sh"
DOCTRINE=~/.cargo/bin/doctrine

# Fork is orchestrator-classed: run it from the orchestrator root, never from a
# worker-stamped worktree (else `worktree fork` resolves to worker-mode + refuses).
cd "$ROOT" || { echo "cd ROOT failed"; exit 1; }
rm -rf "$D"

"$DOCTRINE" worktree fork --base "$B" --branch "$BR" --dir "$D" --worker ||
  {
    echo "FORK FAILED $?"
    exit 1
  }
cp "$ROOT/AGENTS.md" "$D/" || {
  echo "AGENTS copy failed"
  exit 1
}
echo "[spawn] fork $BR @ $B -> $D (HEAD $(git -C "$D" rev-parse --short HEAD))"

OUT=$(mktemp)
# `set -m` before the FIRST background job so each `&` job gets its OWN process
# group and the reaps below can signal a whole group — load-bearing for BOTH
# jobs, $KEEP included (its `sleep` orphans otherwise and holds our stderr open,
# ISS-293). `setsid` is ABSENT from this jail; do not "simplify" to it. CHR-051 §2.
set -m
PI_FIFO=$(mktemp -u) && mkfifo "$PI_FIFO"
MSG=$(jq -Rs . <"$PF")
{
  printf '%s\n' '{"type":"set_auto_retry","enabled":false}'
  printf '{"type":"prompt","message":%s}\n' "$MSG"
  sleep "$BACKSTOP"
} >"$PI_FIFO" &
KEEP=$!

timeout "$BACKSTOP" env -C "$D" DOCTRINE_WORKER=1 \
  pi --mode rpc --thinking off --session-dir "$D/.pi-session" \
  --no-extensions --no-skills --no-themes \
  --offline --approve --tools read,bash,edit,write,grep,find,ls \
  <"$PI_FIFO" >"$OUT" 2>&1 &
PI=$!

pi_await_and_reap "$OUT" "$PI" "$KEEP" "$D/.pi-session" "$BACKSTOP" "[spawn]"
rm -f "$PI_FIFO"
echo "----- worker tail -----"
tail -40 "$OUT"
echo "----- worker commit -----"
git -C "$D" log --oneline -1 2>&1
git -C "$D" rev-parse HEAD 2>&1
