#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LOG="${TMPDIR:-/tmp}/upmarket-python-runtime-check.log"
PLIST="Upmarket/Python/Python.xcframework/Info.plist"

if [[ -f "$PLIST" ]] && plutil -lint "$PLIST" >/dev/null 2>&1 && scripts/ci/verify_python_bundle.sh >"$LOG" 2>&1; then
  echo "ok: bundled Python runtime is present and current"
  exit 0
fi

echo "warning: bundled Python runtime is missing or stale; rebuilding"
if [[ -f "$PLIST" ]] && ! plutil -lint "$PLIST" >/dev/null 2>&1; then
  echo "warning: bundled Python.xcframework Info.plist is invalid; rebuilding from source"
fi
if [[ -s "$LOG" ]]; then
  cat "$LOG"
fi
scripts/build_python_env.sh
