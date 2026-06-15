#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: scripts/ci/verify_release_app.sh /path/to/Upmarket.app}"

# The Basic tier is fully native; the Python runtime is a Pro Background Assets download,
# not bundled. The shipped app must therefore NOT embed a Python runtime. Runtime checks
# that need the interpreter run against the SOURCE xcframework (what the Pro asset is
# built from), since that is the canonical runtime location now.
SOURCE_SITE="Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages"
PYTHON_CHECK_BIN="${PYTHON_CHECK_BIN:-python3.12}"

if [[ ! -d "$APP" ]]; then
  echo "error: app bundle missing: $APP"
  exit 1
fi

# Re-embed guard: regressing the embed back into the app would re-bloat it by ~104 MB and
# break the "Basic ships no Python" guarantee.
EMBEDDED_FRAMEWORK="$APP/Contents/Frameworks/Python.framework"
if [[ -e "$EMBEDDED_FRAMEWORK" ]]; then
  echo "error: app bundle embeds Python.framework — Basic must ship native (Python is a Pro download)."
  echo "       Remove Python.xcframework from the Upmarket target's Frameworks/Embed phases."
  echo "       Found: $EMBEDDED_FRAMEWORK"
  exit 1
fi
echo "ok: app bundle does not embed a Python runtime"

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
run_bundle_preflight "$APP"
# Archive-security guards run against the source runtime (the Pro download's basis).
PYTHONPATH="$SOURCE_SITE" "$PYTHON_CHECK_BIN" scripts/ci/test_archive_security.py
scripts/ci/validate_runtime_helper.py "$APP"
scripts/ci/validate_mcp_server.py "$APP"
# No app path → smoke runs against the source runtime, validating the Pro download's
# offline model-missing behavior.
scripts/ci/smoke_convert_offline.sh

echo "ok: release app package gates passed"
