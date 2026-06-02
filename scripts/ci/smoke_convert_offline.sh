#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
if [[ -n "$APP_PATH" ]]; then
  SITE="$APP_PATH/Contents/Frameworks/Python.framework/Versions/3.12/lib/python3.12/site-packages"
else
  SITE="Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages"
fi
TMP_DIR="/tmp/upmarket-ci-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -d "$SITE" ]]; then
  echo "error: bundled Python site-packages not found at $SITE"
  exit 1
fi

MODELS_DIR="$TMP_DIR/models"
INPUT="$TMP_DIR/smoke.md"
cat > "$INPUT" <<'MD'
# Smoke Test

This is a local offline conversion smoke test.
MD

PYTHONPATH="$SITE" HF_HUB_CACHE="$MODELS_DIR" UPMARKET_MODELS_DIR="$MODELS_DIR" UPMARKET_ALLOWED_INPUT_ROOTS="$TMP_DIR" TMPDIR="$TMP_DIR" HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python3 - "$INPUT" <<'PY'
import sys
from docling_bridge.converter import check_pipelines, convert
from upmarket_models.model_manager import check_models

path = sys.argv[1]
pipelines = check_pipelines()
if pipelines.get("enhanced") or pipelines.get("ai"):
    raise SystemExit(f"offline smoke expected no validated models, got: {pipelines}")

models = check_models()
unexpected = [key for key, value in models.items() if value.get("downloaded")]
if unexpected:
    raise SystemExit(f"offline smoke expected no downloaded models, got: {unexpected}")

result = convert(path, {"use_ai": True, "ocr": False})
if result.get("success"):
    raise SystemExit("offline smoke expected AI conversion to fail without a validated model")

message = result.get("error") or ""
if "not downloaded or failed validation" not in message:
    raise SystemExit(f"offline smoke did not return a clear model-missing error: {message}")

print("ok: offline model-missing smoke passed")
PY
