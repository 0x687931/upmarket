#!/usr/bin/env bash
set -euo pipefail

SITE="${1:-Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages}"

if [[ ! -d "$SITE" ]]; then
  echo "error: bundled Python site-packages not found at $SITE"
  exit 1
fi

mkdir -p "$SITE/docling_bridge" "$SITE/upmarket_models"

find "$SITE/docling_bridge" "$SITE/upmarket_models" \
  \( -name "__pycache__" -o -name "*.pyc" -o -name "*.pyo" \) -prune -exec rm -rf {} +

find UpmarketPython/docling_bridge -maxdepth 1 -type f -name "*.py" -print0 \
  | while IFS= read -r -d '' file; do
      install -m 0644 "$file" "$SITE/docling_bridge/$(basename "$file")"
    done

find UpmarketPython/models -maxdepth 1 -type f -name "*.py" -print0 \
  | while IFS= read -r -d '' file; do
      install -m 0644 "$file" "$SITE/upmarket_models/$(basename "$file")"
    done

echo "ok: first-party Python bridge copied into bundled runtime"
