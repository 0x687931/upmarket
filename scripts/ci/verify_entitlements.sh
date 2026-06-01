#!/usr/bin/env bash
set -euo pipefail

APP_ENTITLEMENTS="Upmarket/Upmarket/Upmarket.entitlements"
EXT_ENTITLEMENTS="Upmarket/UpmarketQuickActionSupport/UpmarketQuickAction.entitlements"
HELPER_ENTITLEMENTS="Upmarket/UpmarketRuntimeHelper/UpmarketRuntimeHelper.entitlements"

check_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "error: entitlements file missing: $file"
    exit 1
  fi
  plutil -lint "$file" >/dev/null
}

check_file "$APP_ENTITLEMENTS"
check_file "$EXT_ENTITLEMENTS"
check_file "$HELPER_ENTITLEMENTS"

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$APP_ENTITLEMENTS" 2>/dev/null | grep -qv "true"; then
  echo "error: app sandbox must be enabled in $APP_ENTITLEMENTS"
  exit 1
fi

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.temporary-exception.files.absolute-path.read-write" "$APP_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "error: app contains temporary absolute-path sandbox exception"
  exit 1
fi

for file in "$APP_ENTITLEMENTS" "$EXT_ENTITLEMENTS" "$HELPER_ENTITLEMENTS"; do
  if /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups" "$file" >/dev/null 2>&1; then
    groups=$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups" "$file")
    if ! printf "%s\n" "$groups" | grep -q "group\\."; then
      echo "error: app group in $file must use group.* identifier"
      exit 1
    fi
  fi
done

if [[ $# -gt 0 ]]; then
  APP_PATH="$1"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found: $APP_PATH"
    exit 1
  fi
  codesign -d --entitlements :- "$APP_PATH" >/tmp/upmarket-entitlements.plist 2>/dev/null || {
    echo "error: unable to read signed app entitlements from $APP_PATH"
    exit 1
  }
  if [[ -s /tmp/upmarket-entitlements.plist ]]; then
    plutil -lint /tmp/upmarket-entitlements.plist >/dev/null
  elif [[ "${UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS:-0}" == "1" ]]; then
    echo "error: signed app entitlements are empty for $APP_PATH"
    exit 1
  else
    echo "warning: app has no embedded entitlements; source entitlement policy was checked only"
  fi
  HELPER_PATH="$APP_PATH/Contents/MacOS/UpmarketRuntimeHelper"
  if [[ ! -x "$HELPER_PATH" ]]; then
    echo "error: runtime helper missing from signed app: $HELPER_PATH"
    exit 1
  fi
  codesign -d --entitlements :- "$HELPER_PATH" >/tmp/upmarket-helper-entitlements.plist 2>/dev/null || {
    echo "error: unable to read signed helper entitlements from $HELPER_PATH"
    exit 1
  }
  if [[ -s /tmp/upmarket-helper-entitlements.plist ]]; then
    plutil -lint /tmp/upmarket-helper-entitlements.plist >/dev/null
  elif [[ "${UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS:-0}" == "1" ]]; then
    echo "error: signed helper entitlements are empty for $HELPER_PATH"
    exit 1
  else
    echo "warning: helper has no embedded entitlements; source entitlement policy was checked only"
  fi
fi

echo "ok: entitlements pass policy checks"
