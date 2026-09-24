#!/usr/bin/env bash
# pi-review.sh — confined, READ-ONLY pi reviewer. No worktree, no fork.
#
# Sibling of spawn-confined.sh, stripped to a review posture. The dispatch
# worker spawn forks a worktree because a worker WRITES; a reviewer does not.
# Dropping the fork also drops the whole isolation-arm hazard class (ISS-034:
# `isolation: worktree` losing the git-lock race and silently falling back to a
# moving base) — there is no base to get wrong when nothing is written.
#
# Confinement: `--ro-bind / /` makes the entire filesystem read-only inside the
# namespace, including the tree under review. rw is re-granted to exactly two
# paths: `~/.pi` (pi writes session/auth state at runtime) and $OUT_DIR. The
# reviewer therefore CANNOT mutate the repo — that is an OS guarantee, not a
# prompt instruction.
#
# Model: no `--model` flag is passed, so pi resolves its configured default
# (`~/.pi/agent/settings.json` → deepseek/deepseek-v4-pro). This is deliberate
# and load-bearing: it makes the cheap tier the ONLY tier reachable through this
# script. Top-shelf review goes through the codex MCP, never through pi.
#
# Usage: pi-review.sh <LABEL> <PROMPT_FILE> <OUT_DIR> [BACKSTOP_SECS]
#
# Env:
#   REVIEW_ROOT   tree to review, ro-bound   (default: git toplevel of $PWD)
#   PI_THINKING   thinking level             (default: low)
#   PI_TOOLS      tool allowlist             (default: read,bash,grep,find,ls,write)
#
# Writes $OUT_DIR/<LABEL>.log (raw rpc stream) and expects the reviewer to write
# its own findings to $OUT_DIR/<LABEL>.md (the prompt must say so).
set -u

[ $# -ge 3 ] || {
  echo "usage: pi-review.sh <LABEL> <PROMPT_FILE> <OUT_DIR> [BACKSTOP_SECS]" >&2
  exit 2
}
LABEL="$1"
PF="$2"
OUT_DIR="$3"
BACKSTOP="${4:-1800}"

command -v bwrap >/dev/null || { echo "[review] bwrap not found" >&2; exit 1; }
command -v pi >/dev/null || { echo "[review] pi not found" >&2; exit 1; }
[ -f "$PF" ] || { echo "[review] prompt file not found: $PF" >&2; exit 1; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# The rpc poll/reap lives in one place for all four spawn scripts — it was four
# byte-identical copies, and that is how CHR-051 came to be fixed in two of them.
# Preconditions it relies on: `set -m` before the first background job (below),
# and being called from this shell so `wait` can reach our own children.
# shellcheck source=scripts/lib/pi-reap.sh
. "$SCRIPT_DIR/lib/pi-reap.sh"
REVIEW_ROOT="${REVIEW_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
# bwrap --bind/--chdir require ABSOLUTE paths: under `--ro-bind / /` it cannot
# mkdir a relative mountpoint against the read-only new root.
case "$REVIEW_ROOT" in /*) ;; *) REVIEW_ROOT="$(cd "$REVIEW_ROOT" && pwd -P)" ;; esac
mkdir -p "$OUT_DIR" || { echo "[review] cannot create $OUT_DIR" >&2; exit 1; }
OUT_DIR="$(cd "$OUT_DIR" && pwd -P)"

[ -d "$REVIEW_ROOT" ] || { echo "[review] REVIEW_ROOT missing: $REVIEW_ROOT" >&2; exit 1; }

OUT="$OUT_DIR/$LABEL.log"
SESSION_DIR="$OUT_DIR/.pi-session-$LABEL"
mkdir -p "$SESSION_DIR"

# The prompt rides the rpc stream as a JSON string. The fifo stays open (the
# trailing sleep holds the write end) because pi self-exits on stdin EOF; we
# reap it ourselves on the typed completion event instead.
#
# `set -m` (job control) is enabled HERE, before the first background job, not
# just before the pi spawn: it puts each `&` job in its OWN process group so the
# reaps below can signal a whole group. It is load-bearing for BOTH jobs.
# For $KEEP: `kill -9 $KEEP` fells only the subshell and ORPHANS its `sleep
# $BACKSTOP` child, which inherits this script's stderr and so holds the pipe
# open for any caller that pipes or `wait`s on us — the script exits promptly and
# the CALLER hangs to the backstop anyway (ISS-293; the residual of IMP-024 §6's
# "orphans block a wait"). Observed: sleeps at ppid=1, 29 minutes after their
# raiser finished. `setsid` would also work but is ABSENT from this jail — do not
# "simplify" to it, and do not go back to a bare kill (CHR-051).
set -m
PI_FIFO=$(mktemp -u) && mkfifo "$PI_FIFO"
MSG=$(jq -Rs . <"$PF")
{
  printf '%s\n' '{"type":"set_auto_retry","enabled":false}'
  printf '{"type":"prompt","message":%s}\n' "$MSG"
  sleep "$BACKSTOP"
} >"$PI_FIFO" &
KEEP=$!

# $OUT and $PI_FIFO are host paths opened as fds by THIS shell before bwrap
# execs, so the inner `--tmpfs /tmp` cannot sever them. $OUT_DIR is bound AFTER
# the tmpfs so it survives as a real rw path even when it lives under /tmp —
# order matters, later mounts layer over earlier ones.
PREFIX=( bwrap
  --ro-bind / /
  --dev /dev --proc /proc --tmpfs /tmp
  --bind "$HOME/.pi" "$HOME/.pi"
  --bind "$OUT_DIR" "$OUT_DIR"
  --chdir "$REVIEW_ROOT"
  --die-with-parent )

echo "[review] $LABEL: ro=$REVIEW_ROOT rw=$OUT_DIR thinking=${PI_THINKING:-low}"

# --no-context-files matters for cost, not just hygiene: without it pi slurps
# the tree's AGENTS.md + CLAUDE.md, which `@`-import the ~28KB boot snapshot
# into every single reviewer. The bucket prompt carries what the reviewer needs.
# `set -m` (enabled above, at the first background job) puts this job in its OWN
# process group, pgid == $PI, so the reap below can signal the WHOLE group.
# Without it, `kill -9 $PI` fells only `timeout`; the real pi is a grandchild
# (timeout -> bwrap -> pi wrapper -> pi) and survives as an orphan holding its
# API session open and blocking any caller that `wait`s on this script. Observed:
# two such orphans still live 16 minutes after writing output and reporting
# agent_end.
timeout "$BACKSTOP" "${PREFIX[@]}" \
  pi --mode rpc --thinking "${PI_THINKING:-low}" \
  --session-dir "$SESSION_DIR" \
  --no-extensions --no-skills --no-themes --no-context-files \
  --offline --approve --tools "${PI_TOOLS:-read,bash,grep,find,ls,write}" \
  <"$PI_FIFO" >"$OUT" 2>&1 &
PI=$!

pi_await_and_reap "$OUT" "$PI" "$KEEP" "$SESSION_DIR" "$BACKSTOP" "[review] $LABEL"
rm -f "$PI_FIFO"
if [ -s "$OUT_DIR/$LABEL.md" ]; then
  echo "[review] $LABEL findings: $OUT_DIR/$LABEL.md ($(wc -l <"$OUT_DIR/$LABEL.md") lines)"
else
  echo "[review] $LABEL WROTE NO FINDINGS FILE — inspect $OUT" >&2
fi
