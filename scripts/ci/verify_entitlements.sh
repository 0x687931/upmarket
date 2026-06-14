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

is_codesign_text_plist() {
  local file="$1"
  [[ -f "$file" ]] && head -n 1 "$file" | grep -qx '\[Dict\]'
}

text_entitlement_has_bool_true() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    /^\t\[Key\] / {
      if (in_key) {
        exit
      }
      if (index($0, "[Key] " key) > 0) {
        in_key = 1
      }
      next
    }
    in_key && index($0, "[Bool] true") > 0 {
      found = 1
      exit
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$file"
}

text_entitlement_has_string() {
  local file="$1"
  local key="$2"
  local value="$3"
  awk -v key="$key" -v value="$value" '
    /^\t\[Key\] / {
      if (in_key) {
        exit
      }
      if (index($0, "[Key] " key) > 0) {
        in_key = 1
      }
      next
    }
    in_key && index($0, "[String] " value) > 0 {
      found = 1
      exit
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$file"
}

entitlement_value_matches() {
  local file="$1"
  local key="$2"
  local pattern="$3"
  local value
  if is_codesign_text_plist "$file"; then
    awk -v key="$key" -v pattern="$pattern" '
      /^\t\[Key\] / {
        if (in_key) {
          exit
        }
        if (index($0, "[Key] " key) > 0) {
          in_key = 1
        }
        next
      }
      in_key && index($0, "[String] ") > 0 {
        value = $0
        sub(/^.*\[String\] /, "", value)
        if (value ~ pattern) {
          found = 1
        }
        exit
      }
      END {
        exit(found ? 0 : 1)
      }
    ' "$file"
    return
  fi
  value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)
  printf "%s\n" "$value" | grep -Eq "$pattern"
}

require_entitlement_true() {
  local file="$1"
  local key="$2"
  local label="$3"
  local value
  if is_codesign_text_plist "$file"; then
    if ! text_entitlement_has_bool_true "$file" "$key"; then
      echo "error: $label must be enabled in $file"
      exit 1
    fi
    return
  fi
  value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)
  if [[ "$value" != "true" ]]; then
    echo "error: $label must be enabled in $file"
    exit 1
  fi
}

require_entitlement_true "$APP_ENTITLEMENTS" "com.apple.security.app-sandbox" "app sandbox"
require_entitlement_true "$APP_ENTITLEMENTS" "com.apple.developer.background-assets" "app Background Assets downloads"
require_entitlement_true "$HELPER_ENTITLEMENTS" "com.apple.security.app-sandbox" "runtime helper sandbox"
require_entitlement_true "$HELPER_ENTITLEMENTS" "com.apple.security.inherit" "runtime helper sandbox inheritance"
require_entitlement_true "$MCP_ENTITLEMENTS" "com.apple.security.app-sandbox" "MCP server sandbox"

require_entitlement_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local label="$4"
  local values
  if is_codesign_text_plist "$file"; then
    if ! text_entitlement_has_string "$file" "$key" "$value"; then
      echo "error: $label must include $value in $file"
      exit 1
    fi
    return
  fi
  values=$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)
  if ! printf "%s\n" "$values" | grep -Fq "$value"; then
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
    codesign -d --entitlements - "$path" >"$dump" 2>/dev/null || {
      echo "error: unable to read signed $label entitlements from $path"
      exit 1
    }
    if [[ -s "$dump" ]]; then
      if ! plutil -lint "$dump" >/dev/null 2>&1 && ! is_codesign_text_plist "$dump"; then
        echo "error: signed $label entitlements are not parseable for $path"
        exit 1
      fi
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
  if [[ "${ENABLE_USER_SCRIPT_SANDBOXING:-NO}" == "YES" && "${UPMARKET_VERIFY_SIGNED_ENTITLEMENTS_IN_BUILD:-0}" != "1" ]]; then
    echo "warning: skipping embedded entitlement read inside Xcode's user script sandbox; verify the signed archive with scripts/ci/verify_release_app.sh"
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
    if ! entitlement_value_matches "$APP_ENTITLEMENTS_DUMP" "com.apple.developer.icloud-container-environment" "^(Development|Production)$"; then
      echo "error: signed app iCloud container environment must be Development or Production"
      exit 1
    fi
  fi
  if require_signed_entitlements "$HELPER_PATH" "$HELPER_ENTITLEMENTS_DUMP" "helper"; then
    require_entitlement_true "$HELPER_ENTITLEMENTS_DUMP" "com.apple.security.app-sandbox" "signed helper sandbox"
    require_entitlement_true "$HELPER_ENTITLEMENTS_DUMP" "com.apple.security.inherit" "signed helper sandbox inheritance"
  fi
  if require_signed_entitlements "$CLI_PATH" "$CLI_ENTITLEMENTS_DUMP" "command-line tool"; then
    if /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$CLI_ENTITLEMENTS_DUMP" >/dev/null 2>&1; then
      echo "error: signed command-line tool must not be app-sandboxed"
      exit 1
    fi
  fi
  if require_signed_entitlements "$MCP_PATH" "$MCP_ENTITLEMENTS_DUMP" "MCP server"; then
    require_entitlement_true "$MCP_ENTITLEMENTS_DUMP" "com.apple.security.app-sandbox" "signed MCP server sandbox"
  fi
fi

echo "ok: entitlements pass policy checks"
