#!/usr/bin/env bash
# One-off: respawn a confined pi worker against an EXISTING fork dir (no re-fork,
# preserves working tree + warm target/). Mirrors spawn-confined.sh minus the
# fork step. Usage: pi-respawn-nofork.sh <DIR> <PROMPT_FILE> [BACKSTOP_SECS]
set -u
D="$1"
PF="$2"
BACKSTOP="${3:-1800}"
ROOT=/workspace/doctrine
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# The rpc poll/reap lives in one place for all four spawn scripts — it was four
# byte-identical copies, and that is how CHR-051 came to be fixed in two of them.
# Preconditions it relies on: `set -m` before the first background job (below),
# and being called from this shell so `wait` can reach our own children.
# shellcheck source=scripts/lib/pi-reap.sh
. "$SCRIPT_DIR/lib/pi-reap.sh"
case "$D" in /*) ;; *) D="$ROOT/$D" ;; esac
[ -d "$D" ] || { echo "fork dir missing: $D"; exit 1; }
echo "[respawn] $D (HEAD $(git -C "$D" rev-parse --short HEAD))"

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

timeout "$BACKSTOP" \
  bwrap \
    --ro-bind / / \
    --dev /dev --proc /proc --tmpfs /tmp \
    --bind "$HOME/.pi" "$HOME/.pi" \
    --bind "$D" "$D" \
    --chdir "$D" \
    --die-with-parent \
    --setenv DOCTRINE_WORKER 1 \
    pi --mode rpc --thinking off --session-dir "$D/.pi-session" \
    --no-extensions --no-skills --no-themes \
    --offline --approve --tools read,bash,edit,write,grep,find,ls \
    <"$PI_FIFO" >"$OUT" 2>&1 &
PI=$!

pi_await_and_reap "$OUT" "$PI" "$KEEP" "$D/.pi-session" "$BACKSTOP" "[respawn]"
rm -f "$PI_FIFO"
echo "----- worker tail -----"
tail -25 "$OUT"
