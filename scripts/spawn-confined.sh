#!/usr/bin/env bash
# Reusable dispatch worker spawn (subprocess arm) — CONFINED, one shape for every
# harness. SL-254 generalised this from `pi-spawn-confined.sh` (DEC-209): the
# claude arm collapses onto THIS script rather than onto in-session subagents, so
# `pi` is now a profile rather than the premise.
#
# IMP-004 D-B3 spike: nested bwrap confinement. Discharges ADR-006 D2b at the OS
# level (governing ADR-008). The worker's exec is wrapped in a nested bwrap that
# rw-binds ONLY its own worktree ($D) and ro-binds everything else (main tree,
# .doctrine/* authored+runtime state, sibling worktrees). The fork itself is
# orchestrator-classed, runs in $ROOT before confinement, and is untouched.
#
# Everything harness-specific reduces to two facts (design §5.2.1): the config
# directory bound into the jail, and the exec line. One further divergence is
# real and stated: `pi --mode rpc` never self-exits, so the pi profile holds
# stdin open with a fifo and polls for `agent_settled`; `claude -p` EXITS on
# completion, so the claude profile needs neither the fifo, the keepalive
# subshell, nor `pi_await_and_reap` — its completion signal is process exit
# (§5.2.1, R4). That is a simplification, not a gap.
#
# Usage: spawn-confined.sh <harness> <B> <BRANCH> <DIR> <PROMPT_FILE> [BACKSTOP_SECS]
set -u
HARNESS="$1"
B="$2"
BR="$3"
D="$4"
PF="$5"
BACKSTOP="${6:-1800}"

# Harness profile — the config dir bound rw into the jail. `pi` writes ~/.pi at
# runtime even with the session under $D; `claude` needs ~/.claude wholesale for
# the SUBSCRIPTION credential (DEC-210 — an API key forfeits the billing EVD-023
# establishes, which is this arm's whole authorisation). The narrowed mount set
# from ../microvm-spike is the known refinement, deliberately not taken here.
case "$HARNESS" in
  pi) CFG_DIR="$HOME/.pi" ;;
  claude) CFG_DIR="$HOME/.claude" ;;
  *)
    echo "[spawn] unknown harness: $HARNESS (expected: pi | claude)" >&2
    exit 1
    ;;
esac

# ROOT / DOCTRINE are host-resolved, override-friendly (SL-185 PHASE-04): the
# caller may export them (the Linux jail sets ROOT=/workspace/doctrine); else
# derive portably so the Darwin arm runs on a stock mac (no /workspace, no
# ~/.cargo/bin). ROOT ← git toplevel of the script's own dir; DOCTRINE ← PATH,
# then the cargo-bin fallback.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT="${DOCTRINE_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo /workspace/doctrine)}"
DOCTRINE="${DOCTRINE_BIN:-$(command -v doctrine || echo "$HOME/.cargo/bin/doctrine")}"

# Linux capability probe (SL-254 D7, RV-355 F-6). DEC-208's fail-closed argument
# leans on a NAMED refusal. A missing `bwrap` always failed closed — a missing
# binary is a non-zero exec — but UNNAMED, and only after a fork had been minted
# and torn down. Probe first, name the reason, spawn nothing. The token is
# `jail.rs`'s `REASON_NO_BWRAP` value; `bwrap_core_argv_matches_spawn_core_flags`'s
# sibling test reads this file and asserts the two still agree (STD-001 — the
# duplicate is CHECKED, not merely commented, because a shell cannot import it).
# The macOS arm is already named, via `worktree jail-prefix` below.
if [ "$(uname)" != Darwin ]; then
  command -v bwrap >/dev/null 2>&1 || {
    echo "[spawn] bwrap-unavailable — refusing to spawn an unconfined worker" >&2
    exit 1
  }
fi

# Fork is orchestrator-classed: run it from the orchestrator root, never from a
# worker-stamped worktree (else `worktree fork` resolves to worker-mode + refuses).
cd "$ROOT" || {
  echo "cd ROOT failed"
  exit 1
}
# bwrap --bind/--chdir require an ABSOLUTE path: under `--ro-bind / /` it cannot
# mkdir a relative mountpoint against the read-only new root. Absolutize $D
# (relative dirs are resolved against $ROOT) so callers keep the pi-spawn.sh
# relative-dir convention.
case "$D" in /*) ;; *) D="$ROOT/$D" ;; esac

# PI_REUSE_FORK=1 attaches a second turn to an EXISTING fork instead of minting a
# new one: the review pass reads the worker's delta, and an escalation model cleans
# it up in place. Re-forking would destroy the very work both need, so the fork,
# the `rm -rf`, and $B are skipped — everything downstream (confinement, prompt,
# completion) is unchanged.
if [ "${PI_REUSE_FORK:-0}" = 1 ]; then
  [ -d "$D" ] || {
    echo "[spawn] PI_REUSE_FORK=1 but $D does not exist"
    exit 1
  }
  echo "[spawn] reuse $D (HEAD $(git -C "$D" rev-parse --short HEAD))"
else
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
fi

OUT=$(mktemp)

if [ "$HARNESS" = pi ]; then
  # The rpc poll/reap lives in one place for all four spawn scripts — it was four
  # byte-identical copies, and that is how CHR-051 came to be fixed in two of them.
  # Preconditions it relies on: `set -m` before the first background job (below),
  # and being called from this shell so `wait` can reach our own children. Sourced
  # INSIDE the pi profile: `claude -p` exits on completion and has no fifo to poll,
  # so the reap machinery is pi-specific by construction (EX-3, EX-4).
  # shellcheck source=scripts/lib/pi-reap.sh
  . "$SCRIPT_DIR/lib/pi-reap.sh"
  # `set -m` (job control) is enabled HERE, before the FIRST background job, not
  # just before the pi spawn: it puts each `&` job in its OWN process group so the
  # reaps below can signal a whole group. It is load-bearing for BOTH jobs.
  # For $KEEP: `kill -9 $KEEP` fells only the subshell and ORPHANS its `sleep
  # $BACKSTOP` child, which inherits this script's stderr and so holds the pipe
  # open for any caller that pipes or `wait`s on us — the script exits promptly and
  # the CALLER hangs to the backstop anyway (ISS-293). Observed: sleeps at ppid=1,
  # 29 minutes after their raiser finished. `setsid` would also work but is ABSENT
  # from this jail — do not "simplify" to it, and do not go back to a bare kill
  # (CHR-051 §2).
  set -m
  PI_FIFO=$(mktemp -u) && mkfifo "$PI_FIFO"
  MSG=$(jq -Rs . <"$PF")
  {
    printf '%s\n' '{"type":"set_auto_retry","enabled":false}'
    printf '{"type":"prompt","message":%s}\n' "$MSG"
    sleep "$BACKSTOP"
  } >"$PI_FIFO" &
  KEEP=$!
fi

# Confinement boundary. --ro-bind / / makes the whole fs read-only inside the
# namespace, then --bind "$D" "$D" re-grants rw to just the worker's worktree
# (its in-tree target/ rides along, so cargo builds stay writable). OUT and
# PI_FIFO are host-/tmp paths opened as fds by THIS shell before bwrap execs, so
# the inner --tmpfs /tmp does not sever them. --die-with-parent lets the kill -9
# below reap the worker through bwrap.
case "$(uname)" in
  Darwin)
    # macOS (Seatbelt) arm — SL-185 PHASE-04 (RISK-1 cleared). The Rust
    # `jail-prefix` mac branch resolves the floor, materializes the `.sb`, and
    # writes a NUL-delimited `sandbox-exec … --` prefix to `--out`; we read it
    # into PREFIX and wrap the worker exec once (children inherit — SL-183-probed).
    #
    # OQ-b: a real harness WRITES its config dir at runtime even with the session
    # under $D, so we grant $CFG_DIR as an --extra-rw (jail-prefix realpath's +
    # validates it, fail-closed if absent) — parity with the Linux `--bind`.
    # Worker identity rides `sandbox_exec_argv`'s trailing `env` token, which
    # carries DOCTRINE_WORKER=1 alongside TMPDIR (RV-355 F-2) — the one place
    # macOS parity was not true by construction.
    JAIL_ARGV="$D/.tmp/jail.argv"
    mkdir -p "$D/.tmp"
    "$DOCTRINE" worktree jail-prefix --dir "$D" --main-root "$ROOT" \
      --extra-rw "$CFG_DIR" --out "$JAIL_ARGV" ||
      {
        echo "[spawn] jail-prefix failed ($?) — aborting (no unconfined worker)" >&2
        exit 1
      }
    # Portable NUL-delimited array read — macOS ships bash 3.2 (no `mapfile`).
    # `--out` has NO trailing NUL (AR-1), so `read -d ''` returns non-zero on the
    # final token; `|| [ -n "$tok" ]` captures it. Works on bash 3.2 and 5.
    PREFIX=()
    while IFS= read -r -d '' tok || [ -n "$tok" ]; do PREFIX+=("$tok"); done <"$JAIL_ARGV"
    ;;
  *)
    # Linux inline bwrap array — tokens BYTE-UNCHANGED from the prior inline exec
    # (EX-1). Same flags, same order; only the harness config bind is now a
    # variable. The Linux confinement-prefix reader path is proven in
    # tests/e2e_worktree_jail_prefix.rs; this inline array is its twin, and
    # tests/e2e_worker_confinement.rs exercises THESE tokens live.
    PREFIX=( bwrap
      --ro-bind / /
      --dev /dev --proc /proc --tmpfs /tmp
      --bind "$CFG_DIR" "$CFG_DIR"
      --bind "$D" "$D"
      --chdir "$D"
      --die-with-parent
      --setenv DOCTRINE_WORKER 1
      # TMPDIR must point INSIDE the jail's writable set. Inherited, it names an
      # orchestrator-side path (`/work/tmp`, `/tmp/...`) that `--ro-bind / /`
      # leaves read-only, and a harness that mkdirs a per-session scratch dir
      # under TMPDIR then fails on EVERY tool call. Observed live at SL-254
      # PHASE-09: a confined `claude` worker's Bash tool returned `EROFS:
      # read-only file system, mkdir '$TMPDIR/claude-<uid>/<slug>'` before any
      # command ran — it could Read/Edit but could not execute one thing, so
      # the role band's own "verify as you go" contract was unsatisfiable. `pi`
      # never surfaced it (no TMPDIR scratch dir on tool startup), which is why
      # it survived the generalisation. `/tmp` is the `--tmpfs` mounted three
      # lines up: writable, and destroyed with the namespace. The macOS arm has
      # always set TMPDIR (`ENV_TMPDIR`, D-mac3) — this is Linux catching up,
      # inverting §5.2.1's "Darwin is the arm that needs the extra token".
      # NOTE deliberately `/tmp`, not `$D/.tmp`: a TMPDIR inside the worktree
      # would land harness scratch files in the working-tree delta the
      # orchestrator imports.
      --setenv TMPDIR /tmp )
    ;;
esac
# Fail-closed guard: an empty confinement PREFIX must never fall through to an
# unconfined exec (EX-2; defence-in-depth for the reader path).
[ "${#PREFIX[@]}" -gt 0 ] || {
  echo "[spawn] empty confinement PREFIX — aborting" >&2
  exit 1
}

if [ "$HARNESS" = pi ]; then
  # PI_THINKING / PI_TOOLS default to the historic hardcoded values, so existing
  # callers are byte-unchanged. A capable-but-loose worker model wants `high`; a
  # read-only review turn wants the tool list without `edit,write`.
  timeout "$BACKSTOP" "${PREFIX[@]}" \
    pi --mode rpc --thinking "${PI_THINKING:-off}" --session-dir "$D/.pi-session" \
    --no-extensions --no-skills --no-themes \
    --offline --approve --tools "${PI_TOOLS:-read,bash,edit,write,grep,find,ls}" \
    <"$PI_FIFO" >"$OUT" 2>&1 &
  PI=$!
  pi_await_and_reap "$OUT" "$PI" "$KEEP" "$D/.pi-session" "$BACKSTOP" "[spawn]"
  rm -f "$PI_FIFO"
else
  # claude profile (DEC-215). Foreground: `claude -p` exits when the turn ends,
  # so process exit IS the completion signal and there is nothing to poll or reap.
  #   -p                          headless, non-interactive — the premise (DEC-202)
  #   --output-format stream-json typed event stream, at parity with pi's RPC
  #   --strict-mcp-config         with no --mcp-config: NO MCP in the worker, at
  #                               parity with pi's --no-extensions. Every
  #                               privileged act is the orchestrator's (DEC-216)
  #   --permission-mode bypassPermissions
  #                               the analog of pi's --approve: inside the
  #                               confinement the OS floor is the boundary, so an
  #                               in-agent prompt buys nothing (DEC-208, DEC-216)
  # Deliberately unspent: --json-schema (nothing consumes a shaped hand-back) and
  # ANTHROPIC_API_KEY / --bare (forfeits the subscription billing, DEC-210).
  #   --verbose                   MANDATORY companion to `-p
  #                               --output-format stream-json`: the CLI hard-
  #                               refuses the pair without it ("When using
  #                               --print, --output-format=stream-json requires
  #                               --verbose") and spawns nothing. Found by
  #                               SL-254 PHASE-09's live fire — the claude arm
  #                               had never been run, and no test asserted this
  #                               exec line, so the arm shipped inert. Guarded
  #                               now by `claude_arm_stream_json_carries_verbose`
  #                               in `jail.rs`.
  timeout "$BACKSTOP" "${PREFIX[@]}" \
    claude -p --output-format stream-json --verbose \
    --strict-mcp-config \
    --permission-mode bypassPermissions \
    <"$PF" >"$OUT" 2>&1
  RC=$?
  [ "$RC" -eq 0 ] || echo "[spawn] claude exited $RC (124 = backstop timeout)" >&2
fi

echo "----- worker tail -----"
tail -40 "$OUT"
# The worker hands back UNCOMMITTED (design §5.2.2, DEC-213) and the fork's
# `.git` is read-only, so this tip should still be the base `$B` — printing it is
# how the orchestrator confirms that, not a report of a commit the worker made.
echo "----- fork tip (expect base; the worker does not commit) -----"
git -C "$D" log --oneline -1 2>&1
git -C "$D" rev-parse HEAD 2>&1

# Propagate the worker's exit status (SL-254 PHASE-09). Previously the script
# ended on `git rev-parse`, so a worker that never started — the `--verbose`
# refusal above exited 1 in 1.4s — still exited the SCRIPT 0. An orchestrator
# that checks the spawn's status saw success and went looking for a delta that
# was never written. The failure is reported on stderr AND in the status now.
# `pi_await_and_reap` leaves RC unset on the pi arm (it reaps and reports
# itself), so default to 0 there rather than inventing a verdict for it.
exit "${RC:-0}"
