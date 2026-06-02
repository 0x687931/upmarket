#!/usr/bin/env bash
set -euo pipefail

SITE="${1:-Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages}"

if [[ ! -d "$SITE" ]]; then
  echo "error: bundled Python site-packages not found at $SITE"
  exit 1
fi

mkdir -p "$SITE/docling_bridge" "$SITE/upmarket_models"

find UpmarketPython/docling_bridge -maxdepth 1 -type f -name "*.py" -print0 \
  | while IFS= read -r -d '' file; do
      cp -f "$file" "$SITE/docling_bridge/$(basename "$file")"
      chmod 0644 "$SITE/docling_bridge/$(basename "$file")" 2>/dev/null || true
    done

find UpmarketPython/models -maxdepth 1 -type f -name "*.py" -print0 \
  | while IFS= read -r -d '' file; do
      cp -f "$file" "$SITE/upmarket_models/$(basename "$file")"
      chmod 0644 "$SITE/upmarket_models/$(basename "$file")" 2>/dev/null || true
    done

echo "ok: first-party Python bridge copied into bundled runtime"
