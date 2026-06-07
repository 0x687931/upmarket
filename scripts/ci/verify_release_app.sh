#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: scripts/ci/verify_release_app.sh /path/to/Upmarket.app}"
PYTHON_FRAMEWORK="$APP/Contents/Frameworks/Python.framework"
SITE="$APP/Contents/Frameworks/Python.framework/Versions/3.12/lib/python3.12/site-packages"
SITE_PYTHON_VERSION="$(printf '%s\n' "$SITE" | sed -nE 's#.*lib/python([0-9]+[.][0-9]+)/site-packages$#\1#p')"
PYTHON_CHECK_BIN="${PYTHON_CHECK_BIN:-python$SITE_PYTHON_VERSION}"

if [[ ! -d "$APP" ]]; then
  echo "error: app bundle missing: $APP"
  exit 1
fi

run_bundle_preflight() {
  local bundle_path="$1"
  local module_cache="${UPMARKET_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/upmarket-swift-module-cache}"
  mkdir -p "$module_cache"
  xcrun swift -module-cache-path "$module_cache" -e '
import Darwin
import Foundation

let path = CommandLine.arguments[1]
guard FileManager.default.fileExists(atPath: path) else {
    fputs("error: bundle preflight path missing: \(path)\n", stderr)
    exit(1)
}
guard let bundle = Bundle(path: path) else {
    fputs("error: unable to create Foundation bundle for preflight: \(path)\n", stderr)
    exit(1)
}
do {
    try bundle.preflight()
    print("ok: Apple bundle preflight passed for \(path)")
} catch {
    fputs("error: Apple bundle preflight failed for \(path): \(error)\n", stderr)
    exit(1)
}
' "$bundle_path"
}

scripts/ci/verify_effective_plist.sh "$APP"
scripts/ci/verify_entitlements.sh "$APP"
run_bundle_preflight "$PYTHON_FRAMEWORK"
scripts/ci/verify_python_bundle.sh "$SITE"
PYTHONPATH="$SITE" "$PYTHON_CHECK_BIN" scripts/ci/test_archive_security.py
scripts/ci/validate_runtime_helper.py "$APP"
scripts/ci/validate_mcp_server.py "$APP"
scripts/ci/smoke_convert_offline.sh "$APP"

echo "ok: release app package gates passed"
