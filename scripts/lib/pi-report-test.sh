#!/usr/bin/env bash
# pi-report-test.sh — behavioural test for pi_report (scripts/lib/pi-report.sh).
#
# Fast and offline: a hand-written pi event stream, never a live run. The helper's
# interesting failure mode is not the rendering (the reducer owns that, and has its
# own suite) but the DEGRADED path — a spawn script that reports nothing leaves an
# orchestrator with no evidence at all, so the fallback must still show the stream.
#
# Usage: scripts/lib/pi-report-test.sh    (exit 0 = pass)
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/pi-report.sh
. "$SCRIPT_DIR/pi-report.sh"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL — $1" >&2; }
contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (no '$2' in output)" ;; esac }
missing() { case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac }

STREAM=$(mktemp)
trap 'rm -f "$STREAM"' EXIT

cat >"$STREAM" <<'JSONL'
{"type":"session","version":3,"id":"s","cwd":"/repo"}
{"type":"message_end","message":{"role":"system","content":"SYSTEM ECHO"}}
{"type":"tool_execution_start","toolCallId":"1","toolName":"bash","args":{"command":"wc -l big.txt"}}
{"type":"tool_execution_end","toolCallId":"1","toolName":"bash","result":{"content":[{"type":"text","text":"201 big.txt"}],"structuredContent":{"exit_code":0}},"isError":false}
{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"201 lines."}],"stopReason":"stop","model":"m"}}
{"type":"agent_settled"}
JSONL

echo "1. reduces a pi event stream through the default reducer (quotient reduce)"
if command -v quotient >/dev/null; then
  out=$(pi_report "$STREAM" "[test]" 2>&1)
  contains "$out" "----- [test] report -----" "prints a tagged report header"
  contains "$out" "→ bash(wc -l big.txt)" "renders the tool call"
  contains "$out" "## Result" "renders the result section"
  missing "$out" "SYSTEM ECHO" "drops context echo"
  contains "$out" "transcript=" "status line names the transcript artefact"
else
  echo "  skip — no quotient on PATH (flakes agents.quotient)"
fi

echo "2. degrades to the raw tail when the reducer is unavailable"
out=$(PI_REDUCE="/nonexistent/quotient reduce" pi_report "$STREAM" "[test]" 2>&1)
contains "$out" "tail (no reducer" "says why it fell back"
contains "$out" '{"type":"tool_execution_start"' "still shows the raw stream"

echo "3. runs PI_REDUCE as a command, passing its words through"
STUB=$(mktemp)
trap 'rm -f "$STREAM" "$STUB"' EXIT
# shellcheck disable=SC2016 # $1 is for the stub to expand
printf '#!/usr/bin/env bash\necho "stub-called first=$1"\n' >"$STUB"
chmod +x "$STUB"
out=$(PI_REDUCE="$STUB reduce" pi_report "$STREAM" "[test]" 2>&1)
contains "$out" "stub-called first=reduce" "the stub receives 'reduce' as its first argument"
missing "$out" "tail (no reducer" "does not fall back"

echo
echo "pi-report: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
