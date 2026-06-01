#!/usr/bin/env bash
set -euo pipefail

SITE="Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages"

if [[ ! -d "$SITE" ]]; then
  echo "error: bundled Python site-packages not found at $SITE"
  exit 1
fi

required_paths=(
  "$SITE/docling_bridge"
  "$SITE/docling_bridge/converter.py"
  "$SITE/docling_bridge/security.py"
  "$SITE/upmarket_models"
  "$SITE/upmarket_models/model_manager.py"
)

for path in "${required_paths[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "error: missing bundled Python path: $path"
    exit 1
  fi
done

PYTHONPATH="$SITE" HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python3 - <<'PY'
import importlib
import importlib.util

modules = [
    "docling_bridge.converter",
    "docling_bridge.security",
    "upmarket_models.model_manager",
]

for module in modules:
    importlib.import_module(module)

for forbidden in ("fitz", "pymupdf", "pymupdf4llm"):
    if importlib.util.find_spec(forbidden) is not None:
        raise SystemExit(f"error: forbidden AGPL/commercial package present in bundled runtime: {forbidden}")

print("ok: bundled Python bridge imports")
PY
