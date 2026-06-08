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

if [[ "${UPMARKET_REQUIRE_MODEL_MANIFEST_BASE_URL:-0}" == "1" ]]; then
  require_key "UpmarketModelManifestBaseURL"
  model_manifest_base_url=$(/usr/libexec/PlistBuddy -c "Print :UpmarketModelManifestBaseURL" "$INFO")
  if [[ -z "$model_manifest_base_url" ]]; then
    echo "error: UpmarketModelManifestBaseURL must not be empty for release model downloads"
    exit 1
  fi
  model_manifest_host=$(python3 - "$model_manifest_base_url" <<'PY'
from urllib.parse import urlparse
import sys
url = urlparse(sys.argv[1])
if url.scheme != "https" or not url.hostname:
    raise SystemExit(1)
print(url.hostname.lower())
PY
  ) || {
    echo "error: UpmarketModelManifestBaseURL must be an https URL"
    exit 1
  }
  IFS=',' read -r -a allowed_hosts <<< "${UPMARKET_MODEL_MANIFEST_ALLOWED_HOSTS:-icloud.com,icloud-content.com,apple.com}"
  allowed=0
  for suffix in "${allowed_hosts[@]}"; do
    suffix="${suffix#.}"
    if [[ "$model_manifest_host" == "$suffix" || "$model_manifest_host" == *".$suffix" ]]; then
      allowed=1
      break
    fi
  done
  if [[ "$allowed" != "1" ]]; then
    echo "error: UpmarketModelManifestBaseURL host must be Apple-hosted; got $model_manifest_host"
    echo "       Override with UPMARKET_MODEL_MANIFEST_ALLOWED_HOSTS only for reviewed first-party hosting."
    exit 1
  fi
fi

bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO")
if [[ "$bundle_id" != "com.upmarket.app" ]]; then
  echo "error: expected bundle id com.upmarket.app, got $bundle_id"
  exit 1
fi

echo "ok: effective Info.plist contains required release keys"
