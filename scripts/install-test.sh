#!/usr/bin/env sh
# install-test.sh — unit test for install.sh's (os, arch)→triple mapping, the
# fragile unit (design §9). Sources install.sh in lib-only mode (no network, no
# install) and asserts the mapping across macOS + Linux arches, plus unsupported
# OS and arch. Runs anywhere (pure string mapping) — exercised in-jail on Linux.
# SL-174 PHASE-03; Linux support follow-up.
set -eu

here="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=/dev/null
DOCTRINE_INSTALL_LIB_ONLY=1 . "$here/install.sh"

fail=0
check() {
  # check <uname-s> <uname-m> <expected-triple>
  got="$(triple_for "$1" "$2")" || got="<error>"
  if [ "$got" = "$3" ]; then
    echo "ok: $1/$2 -> $got"
  else
    echo "FAIL: $1/$2 -> expected '$3', got '$got'" >&2
    fail=1
  fi
}

# macOS.
check Darwin arm64 aarch64-apple-darwin
check Darwin x86_64 x86_64-apple-darwin

# Linux (static musl). `uname -m` reports aarch64 on most distros, arm64 on some.
check Linux x86_64 x86_64-unknown-linux-musl
check Linux aarch64 aarch64-unknown-linux-musl
check Linux arm64 aarch64-unknown-linux-musl

# Unsupported arch must exit non-zero.
if triple_for Linux ppc64 >/dev/null 2>&1; then
  echo "FAIL: Linux/ppc64 should be unsupported (non-zero)" >&2
  fail=1
else
  echo "ok: Linux/ppc64 rejected"
fi

# Unsupported OS must exit non-zero.
if triple_for FreeBSD x86_64 >/dev/null 2>&1; then
  echo "FAIL: FreeBSD should be unsupported (non-zero)" >&2
  fail=1
else
  echo "ok: FreeBSD rejected"
fi

if [ "$fail" -eq 0 ]; then
  echo "install-test: PASS"
else
  echo "install-test: FAIL" >&2
  exit 1
fi
