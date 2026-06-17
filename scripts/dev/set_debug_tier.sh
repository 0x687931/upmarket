#!/usr/bin/env bash
# Set the local tier for ALL surfaces — app (DEBUG), CLI, and MCP — without a purchase or any
# GUI clicking. Writes the shared TierSnapshot the three already use:
#   - CLI/MCP read it directly (TierSnapshot.read) and gate themselves.
#   - The DEBUG app reads it at launch as a sticky override (StoreManager.applyDebugTierOverride),
#     so relaunch the app after changing it.
#
#   scripts/dev/set_debug_tier.sh max     # or pro | basic
set -euo pipefail

tier="${1:-}"
case "$tier" in
  basic) n=0; purchased=false ;;
  pro)   n=1; purchased=true ;;
  max)   n=2; purchased=true ;;
  *) echo "usage: $0 <basic|pro|max>" >&2; exit 2 ;;
esac

# Same location TierSnapshot.fileURL resolves to (App Group container, or its home fallback).
root="$HOME/Library/Group Containers/group.com.upmarket.app"
mkdir -p "$root"
printf '{"tier":%d,"purchased":%s}' "$n" "$purchased" > "$root/entitlement.json"
echo "tier → $tier  ($(cat "$root/entitlement.json"))"
echo "CLI/MCP: effective now. App: relaunch Upmarket to pick it up."
