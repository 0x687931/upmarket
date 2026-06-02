#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LOG="${TMPDIR:-/tmp}/upmarket-python-runtime-check.log"

if scripts/ci/verify_python_bundle.sh >"$LOG" 2>&1; then
  echo "ok: bundled Python runtime is present and current"
  exit 0
fi

echo "warning: bundled Python runtime is missing or stale; rebuilding"
cat "$LOG"
scripts/build_python_env.sh
