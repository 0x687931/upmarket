#!/usr/bin/env bash
# Report the app bundle size as users experience it: App Store download (compressed)
# and install (on-disk), plus a breakdown. Uses a Release .app (test frameworks excluded,
# binaries stripped) for a realistic figure — Debug builds are ~30MB larger and not
# representative.
#
# Usage:
#   scripts/dev/app_bundle_size.sh            # build Release (unsigned) and measure
#   scripts/dev/app_bundle_size.sh <App.app>  # measure an existing .app
#
# Note: Pro/Max Python runtimes (~350MB) and AI models (~1.7GB) are POST-PURCHASE
# downloads — they are NOT part of the App Store app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

APP="${1:-}"
if [[ -z "$APP" ]]; then
  echo "==> Building Release (unsigned) for a representative measurement…"
  xcodebuild build -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO >/dev/null 2>&1 || { echo "error: Release build failed"; exit 1; }
  APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" build -name Upmarket.app -path '*Release*' 2>/dev/null | head -1)"
fi
[[ -d "$APP" ]] || { echo "error: app bundle not found: $APP"; exit 1; }

config="$( [[ "$APP" == *"/Release/"* ]] && echo Release || echo "non-Release (overestimates)" )"

# Compressed download proxy.
zip="$(mktemp -u /tmp/upmarket-bundle.XXXXXX.zip)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$zip" 2>/dev/null
download="$(du -h "$zip" | cut -f1)"; rm -f "$zip"

echo
echo "App bundle: $APP  [$config]"
echo "------------------------------------------------------------"
printf '  %-22s %s\n' "App Store download" "$download   (compressed)"
printf '  %-22s %s\n' "Install (on disk)"  "$(du -sh "$APP" | cut -f1)"
echo "------------------------------------------------------------"
echo "Breakdown:"
du -sh "$APP/Contents/Frameworks" "$APP/Contents/MacOS" "$APP/Contents/PlugIns" "$APP/Contents/Resources" 2>/dev/null \
  | sort -rh | awk -F'\t' '{n=$2; sub(/.*\/Contents\//,"",n); printf "    %-12s %s\n", $1, n}'
echo "  Frameworks detail:"
du -sh "$APP/Contents/Frameworks/"* 2>/dev/null | sort -rh | head -3 \
  | awk -F'\t' '{n=$2; sub(/.*\/Frameworks\//,"",n); printf "      %-12s %s\n", $1, n}'
echo
echo "The bundled Python runtime dominates. Pro/Max runtimes + AI models download"
echo "post-purchase and do NOT count toward the App Store app size."
echo "Authoritative numbers: Xcode 'App Thinning Size Report' or App Store Connect."
