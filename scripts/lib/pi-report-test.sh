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
STUBS=()
trap 'rm -f "$STREAM" "${STUBS[@]}"' EXIT

reducer() { # reducer <body>: writes a stub reducer to REDUCER
  REDUCER=$(mktemp)
  STUBS+=("$REDUCER")
  printf '#!/usr/bin/env bash\n%s\n' "$1" >"$REDUCER"
  chmod +x "$REDUCER"
}

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
# shellcheck disable=SC2016 # $1 is for the stub to expand
reducer 'echo "stub-called first=$1"'
out=$(PI_REDUCE="$REDUCER reduce" pi_report "$STREAM" "[test]" 2>&1)
contains "$out" "stub-called first=reduce" "the stub receives 'reduce' as its first argument"
missing "$out" "tail (no reducer" "does not fall back"

echo "4. a reducer with no report degrades to the tail, whatever it exits"
for body in 'exit 69' 'exit 0'; do
  reducer "$body"
  out=$(PI_REDUCE="$REDUCER" pi_report "$STREAM" "[test]" 2>&1)
  status=$?
  contains "$out" "tail (no reducer" "'$body': says why it fell back"
  contains "$out" '{"type":"tool_execution_start"' "'$body': still shows the raw stream"
  missing "$out" "[test] report" "'$body': no empty report header"
  if [ "$status" -eq 0 ]; then ok "'$body': returns 0"; else bad "'$body': returned $status"; fi
done

echo "5. a failed run with a transcript is still a report: the verdict is the caller's"
reducer 'echo "the transcript"; exit 1'
out=$(PI_REDUCE="$REDUCER" pi_report "$STREAM" "[test]" 2>&1)
contains "$out" "----- [test] report -----" "prints the report header"
contains "$out" "the transcript" "prints the reducer's output"
missing "$out" "tail (no reducer" "does not fall back"

echo "6. a reducer that reads stdin cannot hang on the caller's"
reducer 'cat >/dev/null; echo "stdin closed"'
# shellcheck disable=SC2016 # expanded by the inner shell
out=$(PI_REDUCE="$REDUCER" timeout 5 bash -c '. "$1"; pi_report "$2" "[test]"' _ \
  "$SCRIPT_DIR/pi-report.sh" "$STREAM" < <(sleep 30) 2>&1)
contains "$out" "stdin closed" "the reducer's stdin is closed"

echo
echo "pi-report: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
