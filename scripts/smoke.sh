#!/usr/bin/env sh
# smoke.sh — embed-integrity gate for a built `doctrine` binary.
#
# Exits non-zero unless every embedded-asset check passes against the actual
# shipped bytes. Single source of the gate: run by `just smoke` locally and by
# the release workflow (PHASE-02) on each artifact before upload — a broken-embed
# binary never reaches a user. See SL-174 design.md §5.2.
#
# Usage: scripts/smoke.sh <path-to-doctrine-binary>
set -eu

bin="${1:-}"
if [ -z "$bin" ]; then
  echo "smoke: usage: smoke.sh <path-to-doctrine-binary>" >&2
  exit 2
fi
if [ ! -x "$bin" ]; then
  echo "smoke: not an executable: $bin" >&2
  exit 2
fi
# Absolutise: later checks run with cwd inside the scratch project, so a
# caller-relative path (release.yml passes `target/<triple>/release/doctrine`)
# would stop resolving.
bin="$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")"

# Scratch workspace + teardown. server_pid is reaped by the trap so a failed
# check never leaks the map server.
work="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

fail() {
  echo "smoke: $1 FAILED" >&2
  exit 1
}

# C1 — the binary runs at all.
"$bin" --version >/dev/null 2>&1 || fail "--version"
echo "smoke: --version ok"

# C2a — install/ embed, projection leg: lay down a fresh project and assert the
# eagerly-projected base backings are present and non-empty. Since SL-227 /
# ADR-019 install projects MINIMALLY (manifest.toml `[base] backings`) — the
# entity templates are no longer copied, so they cannot serve as the canary here.
proj="$work/proj"
mkdir -p "$proj"
"$bin" install --path "$proj" --yes >/dev/null 2>&1 || fail "install"
[ -s "$proj/.doctrine/doctrine.toml" ] || fail "install embed (doctrine.toml absent)"
[ -s "$proj/.doctrine/project-orientation.md" ] \
  || fail "install embed (project-orientation.md absent)"
echo "smoke: install embed ok"

# C2b — install/ + publication/ embeds, whole-root leg: everything install no
# longer projects is reachable on demand via the publication manifest. `publication
# validate` admits the embedded manifest and resolve+emits EVERY declared entry
# through the embedded adapter, so a stripped or partially-dropped embed root
# fails here rather than silently shipping a hollow binary.
(cd "$proj" && "$bin" publication validate >/dev/null 2>&1) || fail "publication embed"
echo "smoke: publication embed ok"

# C3 — web/map/dist embed: boot the map server on an ephemeral port, discover the
# bound URL from its startup line, GET / and require HTTP 200 with a non-empty
# body. An empty/missing dist still compiles but serves no index — this is the
# check that catches it.
log="$work/serve.log"
"$bin" map serve --port 0 >"$log" 2>&1 &
server_pid=$!

url=""
i=0
while [ "$i" -lt 50 ]; do
  url="$(sed -n 's|.*\(http://127\.0\.0\.1:[0-9]*\)/.*|\1|p' "$log" 2>/dev/null | head -n 1)"
  [ -n "$url" ] && break
  kill -0 "$server_pid" 2>/dev/null || break   # server died before announcing
  i=$((i + 1))
  sleep 0.1
done
[ -n "$url" ] || fail "map serve (no listen URL)"

body="$work/body.html"
code="$(curl -sS -o "$body" -w '%{http_code}' "$url/" 2>/dev/null || true)"
[ "$code" = "200" ] || fail "map GET / (status ${code:-none})"
[ -s "$body" ] || fail "map GET / (empty body)"
echo "smoke: map embed ok ($url)"

echo "smoke: PASS ($bin)"
