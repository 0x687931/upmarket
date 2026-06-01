#!/usr/bin/env bash
set -euo pipefail

SITE="Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages"
TMP_DIR="/tmp/upmarket-ci-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

INPUT="$TMP_DIR/smoke.md"
cat > "$INPUT" <<'MD'
# Smoke Test

This is a local offline conversion smoke test.
MD

PYTHONPATH="$SITE" HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python3 - "$INPUT" <<'PY'
import sys
from docling_bridge.converter import convert

path = sys.argv[1]
result = convert(path, {"use_enhanced": False, "use_ai": False, "ocr": False})

if not result.get("success"):
    raise SystemExit(f"offline smoke conversion failed: {result.get('error')}")

markdown = result.get("markdown", "")
if "Smoke Test" not in markdown:
    raise SystemExit("offline smoke conversion output did not contain expected text")

print("ok: offline smoke conversion passed")
PY
