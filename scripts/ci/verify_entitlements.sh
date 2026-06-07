#!/usr/bin/env bash
set -euo pipefail

APP_ENTITLEMENTS="Upmarket/Upmarket/Upmarket.entitlements"
EXT_ENTITLEMENTS="Upmarket/UpmarketQuickActionSupport/UpmarketQuickAction.entitlements"
HELPER_ENTITLEMENTS="Upmarket/UpmarketRuntimeHelper/UpmarketRuntimeHelper.entitlements"
CLI_ENTITLEMENTS="Upmarket/UpmarketCLI/UpmarketCLI.entitlements"
MCP_ENTITLEMENTS="Upmarket/UpmarketMCP/UpmarketMCP.entitlements"

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
check_file "$CLI_ENTITLEMENTS"
check_file "$MCP_ENTITLEMENTS"

require_entitlement_true() {
  local file="$1"
  local key="$2"
  local label="$3"
  local value
  value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)
  if [[ "$value" != "true" ]]; then
    echo "error: $label must be enabled in $file"
    exit 1
  fi
}

require_entitlement_true "$APP_ENTITLEMENTS" "com.apple.security.app-sandbox" "app sandbox"
require_entitlement_true "$HELPER_ENTITLEMENTS" "com.apple.security.app-sandbox" "runtime helper sandbox"
require_entitlement_true "$HELPER_ENTITLEMENTS" "com.apple.security.inherit" "runtime helper sandbox inheritance"
require_entitlement_true "$CLI_ENTITLEMENTS" "com.apple.security.app-sandbox" "command-line tool sandbox"
require_entitlement_true "$MCP_ENTITLEMENTS" "com.apple.security.app-sandbox" "MCP server sandbox"

require_entitlement_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local label="$4"
  local values
  values=$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)
  if ! printf "%s\n" "$values" | grep -q "$value"; then
    echo "error: $label must include $value in $file"
    exit 1
  fi
}

require_entitlement_value "$APP_ENTITLEMENTS" "com.apple.developer.icloud-services" "CloudKit" "app iCloud services"
require_entitlement_value "$APP_ENTITLEMENTS" "com.apple.developer.icloud-container-identifiers" "iCloud.com.upmarket.app" "app iCloud containers"
require_entitlement_value "$APP_ENTITLEMENTS" "com.apple.developer.icloud-container-environment" '$(UPMARKET_CLOUDKIT_ENVIRONMENT)' "app iCloud container environment"

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.temporary-exception.files.absolute-path.read-write" "$APP_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "error: app contains temporary absolute-path sandbox exception"
  exit 1
fi

for file in "$APP_ENTITLEMENTS" "$EXT_ENTITLEMENTS" "$HELPER_ENTITLEMENTS" "$CLI_ENTITLEMENTS" "$MCP_ENTITLEMENTS"; do
  if /usr/libexec/PlistBuddy -c "Print :com.apple.security.temporary-exception.mach-lookup.global-name" "$file" >/dev/null 2>&1; then
    echo "error: $file contains temporary mach lookup sandbox exception"
    exit 1
  fi
  if /usr/libexec/PlistBuddy -c "Print :com.apple.security.temporary-exception.files.absolute-path.read-only" "$file" >/dev/null 2>&1; then
    echo "error: $file contains temporary absolute-path read sandbox exception"
    exit 1
  fi
  if /usr/libexec/PlistBuddy -c "Print :com.apple.security.temporary-exception.files.absolute-path.read-write" "$file" >/dev/null 2>&1; then
    echo "error: $file contains temporary absolute-path read-write sandbox exception"
    exit 1
  fi
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
  SCRATCH_DIR="${TARGET_TEMP_DIR:-${TMPDIR:-/tmp}}"
  APP_ENTITLEMENTS_DUMP="$SCRATCH_DIR/upmarket-entitlements.plist"
  HELPER_ENTITLEMENTS_DUMP="$SCRATCH_DIR/upmarket-helper-entitlements.plist"
  CLI_ENTITLEMENTS_DUMP="$SCRATCH_DIR/upmarket-cli-entitlements.plist"
  MCP_ENTITLEMENTS_DUMP="$SCRATCH_DIR/upmarket-mcp-entitlements.plist"

  require_signed_entitlements() {
    local path="$1"
    local dump="$2"
    local label="$3"
    codesign -d --entitlements :- "$path" >"$dump" 2>/dev/null || {
      echo "error: unable to read signed $label entitlements from $path"
      exit 1
    }
    if [[ -s "$dump" ]]; then
      plutil -lint "$dump" >/dev/null
    elif [[ "${UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS:-0}" == "1" ]]; then
      echo "error: signed $label entitlements are empty for $path"
      exit 1
    else
      echo "warning: $label has no embedded entitlements; source entitlement policy was checked only"
      return 1
    fi
    return 0
  }

  if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found: $APP_PATH"
    exit 1
  fi
  if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]]; then
    echo "warning: skipping embedded entitlement read because code signing is disabled"
    echo "ok: entitlements pass policy checks"
    exit 0
  fi
  HELPER_PATH="$APP_PATH/Contents/MacOS/UpmarketRuntimeHelper"
  if [[ ! -x "$HELPER_PATH" ]]; then
    echo "error: runtime helper missing from signed app: $HELPER_PATH"
    exit 1
  fi
  CLI_PATH="$APP_PATH/Contents/MacOS/upmarket-cli"
  if [[ ! -x "$CLI_PATH" ]]; then
    echo "error: command-line tool missing from signed app: $CLI_PATH"
    exit 1
  fi
  MCP_PATH="$APP_PATH/Contents/MacOS/upmarket-mcp"
  if [[ ! -x "$MCP_PATH" ]]; then
    echo "error: MCP server missing from signed app: $MCP_PATH"
    exit 1
  fi
  if require_signed_entitlements "$APP_PATH" "$APP_ENTITLEMENTS_DUMP" "app"; then
    require_entitlement_true "$APP_ENTITLEMENTS_DUMP" "com.apple.security.app-sandbox" "signed app sandbox"
    require_entitlement_value "$APP_ENTITLEMENTS_DUMP" "com.apple.developer.icloud-services" "CloudKit" "signed app iCloud services"
    require_entitlement_value "$APP_ENTITLEMENTS_DUMP" "com.apple.developer.icloud-container-identifiers" "iCloud.com.upmarket.app" "signed app iCloud containers"
    if ! /usr/libexec/PlistBuddy -c "Print :com.apple.developer.icloud-container-environment" "$APP_ENTITLEMENTS_DUMP" 2>/dev/null | grep -Eq "^(Development|Production)$"; then
      echo "error: signed app iCloud container environment must be Development or Production"
      exit 1
    fi
  fi
  if require_signed_entitlements "$HELPER_PATH" "$HELPER_ENTITLEMENTS_DUMP" "helper"; then
    require_entitlement_true "$HELPER_ENTITLEMENTS_DUMP" "com.apple.security.app-sandbox" "signed helper sandbox"
    require_entitlement_true "$HELPER_ENTITLEMENTS_DUMP" "com.apple.security.inherit" "signed helper sandbox inheritance"
  fi
  if require_signed_entitlements "$CLI_PATH" "$CLI_ENTITLEMENTS_DUMP" "command-line tool"; then
    require_entitlement_true "$CLI_ENTITLEMENTS_DUMP" "com.apple.security.app-sandbox" "signed command-line tool sandbox"
  fi
  if require_signed_entitlements "$MCP_PATH" "$MCP_ENTITLEMENTS_DUMP" "MCP server"; then
    require_entitlement_true "$MCP_ENTITLEMENTS_DUMP" "com.apple.security.app-sandbox" "signed MCP server sandbox"
  fi
fi

echo "ok: entitlements pass policy checks"
