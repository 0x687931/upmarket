#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
  DERIVED_DATA="${DERIVED_DATA_DIR:-build/DerivedData}"
  APP_PATH=$(find "$DERIVED_DATA" -path "*/Build/Products/*/Upmarket.app" -type d 2>/dev/null | head -n 1 || true)
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "error: built Upmarket.app not found. Pass app path or build with DERIVED_DATA_DIR=build/DerivedData."
  exit 1
fi

INFO="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO" ]]; then
  echo "error: effective Info.plist missing at $INFO"
  exit 1
fi

plutil -lint "$INFO" >/dev/null

require_key() {
  local key="$1"
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$INFO" >/dev/null 2>&1; then
    echo "error: effective Info.plist missing required key: $key"
    exit 1
  fi
}

require_key "CFBundleIdentifier"
require_key "CFBundleVersion"
require_key "CFBundleShortVersionString"
require_key "NSSpeechRecognitionUsageDescription"
require_key "CFBundleURLTypes"
require_key "NSServices"

bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO")
if [[ "$bundle_id" != "com.upmarket.app" ]]; then
  echo "error: expected bundle id com.upmarket.app, got $bundle_id"
  exit 1
fi

echo "ok: effective Info.plist contains required release keys"
