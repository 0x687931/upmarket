#!/usr/bin/env bash
# ensure_models.sh — download pinned model weights into resources/models/ for LFS commit.
#
# Run this once to populate the repo's LFS-tracked model directories from Hugging Face.
# After that, `git lfs pull` is all that's needed on a fresh clone.
#
# Usage:
#   scripts/ci/ensure_models.sh              # download all missing models
#   scripts/ci/ensure_models.sh --force      # re-download even if already present
#
# Requirements: git-lfs, python3, huggingface_hub (pip install huggingface_hub)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODELS_DIR="$REPO_ROOT/resources/models"
FORCE=0

for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=1
done

# ---------------------------------------------------------------------------
# Pinned revisions — must match UpmarketPython/models/model_manager.py
# ---------------------------------------------------------------------------
LAYOUT_REPO="ds4sd/docling-models"
LAYOUT_REVISION="72661864b9c29fb7cced011822786bed346811ea"

AI_REPO="ibm-granite/granite-docling-258M-mlx"
AI_REVISION="e9939db25d2f296c8678d0491c4609a8c596c50a"

# ---------------------------------------------------------------------------

find_python() {
  # Prefer a venv with huggingface_hub; fall back to creating a temporary one via uv.
  for candidate in python3 python3.13 python3.12 python3.11; do
    if command -v "$candidate" &>/dev/null && "$candidate" -c "import huggingface_hub" 2>/dev/null; then
      echo "$candidate"; return
    fi
  done
  # Try uv
  if command -v uv &>/dev/null; then
    local venv="/tmp/upmarket-hf-venv"
    uv venv "$venv" -q 2>/dev/null || true
    uv pip install --python "$venv" huggingface_hub -q 2>/dev/null
    echo "$venv/bin/python3"; return
  fi
  echo "error: cannot find Python with huggingface_hub. Install it: pip install huggingface_hub" >&2
  exit 1
}

check_hf_hub() {
  PYTHON="$(find_python)"
}

download_model() {
  local repo="$1"
  local revision="$2"
  local dest="$3"
  local name="$4"

  if [[ $FORCE -eq 0 && -f "$dest/config.json" ]]; then
    echo "  $name already present — skipping (use --force to re-download)"
    return
  fi

  echo "  Downloading $name from $repo @ ${revision:0:12}…"
  "$PYTHON" - <<PYEOF
import sys
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="$repo",
    revision="$revision",
    local_dir="$dest",
    local_dir_use_symlinks=False,
    ignore_patterns=["*.md", ".gitattributes"],
)
print("  Done.")
PYEOF
}

echo "==> Ensuring model weights in resources/models/"
check_hf_hub

mkdir -p "$MODELS_DIR/layout" "$MODELS_DIR/upmarket_ai"

echo ""
echo "--- layout (ds4sd/docling-models, ~172 MB) ---"
download_model "$LAYOUT_REPO" "$LAYOUT_REVISION" "$MODELS_DIR/layout" "layout"

echo ""
echo "--- upmarket_ai (granite-docling-258M-mlx, ~631 MB) ---"
download_model "$AI_REPO" "$AI_REVISION" "$MODELS_DIR/upmarket_ai" "upmarket_ai"

echo ""
echo "==> Done. Next steps if this is your first time:"
echo "    git add resources/models/"
echo "    git commit -m 'Add pinned model weights via LFS'"
echo "    git push  (uploads LFS objects to remote)"
