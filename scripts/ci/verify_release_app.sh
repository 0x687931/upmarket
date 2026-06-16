#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: scripts/ci/verify_release_app.sh /path/to/Upmarket.app}"

# Conversion is native-only — the app embeds no Python runtime at all. The shipped app must
# therefore NOT embed a Python framework; everything else is verified through Apple's own
# bundle/entitlement checks plus the bundled CLI/MCP tools.

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
  # Debug builds ship a "<name>.debug.dylib" launcher indirection (ENABLE_DEBUG_DYLIB) that
  # Bundle.preflight() rejects as "not loadable". That is not a shippable artifact, so skip
  # the check for Debug builds; it still runs on the signed Release archive.
  if compgen -G "$bundle_path/Contents/MacOS/*.debug.dylib" >/dev/null; then
    echo "ok: skipping bundle preflight for Debug build (not a release artifact)"
    return 0
  fi
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
scripts/ci/validate_mcp_server.py "$APP"

echo "ok: release app package gates passed"
