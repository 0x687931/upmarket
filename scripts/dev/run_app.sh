#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROJECT="${UPMARKET_XCODE_PROJECT:-Upmarket/Upmarket.xcodeproj}"
SCHEME="${UPMARKET_XCODE_SCHEME:-Upmarket}"
CONFIGURATION="${UPMARKET_XCODE_CONFIGURATION:-Debug}"
DESTINATION="${UPMARKET_XCODE_DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-build/DerivedData}"
CODE_SIGNING_ALLOWED="${UPMARKET_CODE_SIGNING_ALLOWED:-NO}"
CODE_SIGNING_REQUIRED="${UPMARKET_CODE_SIGNING_REQUIRED:-NO}"
PYTHON_XCFRAMEWORK="${UPMARKET_PYTHON_XCFRAMEWORK:-Upmarket/Python/Python.xcframework}"
SIGN_FOR_LAUNCH="${UPMARKET_SIGN_FOR_LAUNCH:-YES}"
CLEAN_BEFORE_BUILD="${UPMARKET_CLEAN_BEFORE_BUILD:-YES}"

BUILD=1
RELAUNCH=0

usage() {
  cat <<'USAGE'
usage: scripts/dev/run_app.sh [--no-build] [--relaunch]

Builds Upmarket into the repo-local DerivedData path and opens that exact app:
  build/DerivedData/Build/Products/Debug/Upmarket.app

Options:
  --no-build   Open the existing app bundle without rebuilding.
  --relaunch   Ask any running Upmarket process to quit before opening this build.

Environment:
  DERIVED_DATA_DIR                  Defaults to build/DerivedData.
  UPMARKET_XCODE_CONFIGURATION      Defaults to Debug.
  UPMARKET_XCODE_DESTINATION        Defaults to platform=macOS,arch=arm64.
  UPMARKET_CODE_SIGNING_ALLOWED     Defaults to NO.
  UPMARKET_CODE_SIGNING_REQUIRED    Defaults to NO.
  UPMARKET_SIGN_FOR_LAUNCH          Defaults to YES; ad-hoc signs the local app.
  UPMARKET_CLEAN_BEFORE_BUILD       Defaults to YES; removes stale app bundle first.
USAGE
}

enabled() {
  case "${1:-}" in
    1|YES|yes|true|TRUE) return 0 ;;
    *) return 1 ;;
  esac
}

write_local_entitlements() {
  local entitlements_dir="$DERIVED_DATA_DIR/LocalRunEntitlements"
  mkdir -p "$entitlements_dir"

  cat > "$entitlements_dir/Upmarket.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
PLIST

  cat > "$entitlements_dir/UpmarketQuickAction.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
PLIST

  cat > "$entitlements_dir/Inherited.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.inherit</key>
    <true/>
</dict>
</plist>
PLIST

  cat > "$entitlements_dir/Tool.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
PLIST
}

codesign_if_present() {
  local path="$1"
  shift

  if [[ -e "$path" ]]; then
    /usr/bin/codesign --force --sign - "$@" "$path"
  fi
}

sign_for_launch() {
  local entitlements_dir="$DERIVED_DATA_DIR/LocalRunEntitlements"
  write_local_entitlements

  codesign_if_present "$APP_PATH/Contents/Frameworks/Python.framework" --deep
  codesign_if_present "$APP_PATH/Contents/MacOS/Upmarket.debug.dylib"
  codesign_if_present "$APP_PATH/Contents/MacOS/__preview.dylib"
  codesign_if_present "$APP_PATH/Contents/MacOS/UpmarketRuntimeHelper" --entitlements "$entitlements_dir/Inherited.entitlements"
  codesign_if_present "$APP_PATH/Contents/MacOS/upmarket-cli" --entitlements "$entitlements_dir/Tool.entitlements"
  codesign_if_present "$APP_PATH/Contents/MacOS/upmarket-mcp" --entitlements "$entitlements_dir/Tool.entitlements"
  codesign_if_present "$APP_PATH/Contents/PlugIns/UpmarketQuickAction.appex" --deep --entitlements "$entitlements_dir/UpmarketQuickAction.entitlements"

  /usr/bin/codesign --force --sign - --entitlements "$entitlements_dir/Upmarket.entitlements" "$APP_PATH"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      BUILD=0
      ;;
    --relaunch)
      RELAUNCH=1
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/Upmarket.app"

if [[ "$BUILD" == "1" ]]; then
  if [[ ! -d "$PYTHON_XCFRAMEWORK" ]]; then
    echo "error: build runtime missing: $PYTHON_XCFRAMEWORK"
    echo "       Run scripts/ci/ensure_python_runtime.sh to prepare the local build runtime."
    exit 1
  fi

  if enabled "$CLEAN_BEFORE_BUILD"; then
    if [[ "$APP_PATH" != *"/Build/Products/"*"/Upmarket.app" ]]; then
      echo "error: refusing to remove unexpected app path: $APP_PATH"
      exit 1
    fi
    rm -rf "$APP_PATH"
  fi

  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    CODE_SIGNING_REQUIRED="$CODE_SIGNING_REQUIRED"

  if enabled "$SIGN_FOR_LAUNCH"; then
    sign_for_launch
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: built Upmarket.app not found at $APP_PATH"
  echo "       Run scripts/dev/run_app.sh without --no-build to rebuild it."
  exit 1
fi

scripts/ci/verify_effective_plist.sh "$APP_PATH"

if [[ "$RELAUNCH" == "1" ]] && /usr/bin/pgrep -x Upmarket >/dev/null 2>&1; then
  /usr/bin/osascript -e 'tell application id "com.upmarket.app" to quit' >/dev/null 2>&1 || true

  for _ in {1..30}; do
    if ! /usr/bin/pgrep -x Upmarket >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done

  if /usr/bin/pgrep -x Upmarket >/dev/null 2>&1; then
    echo "error: Upmarket is still running. Quit it before launching this build."
    exit 1
  fi
fi

/usr/bin/open "$APP_PATH"
echo "opened: $APP_PATH"
