#!/bin/bash
# update_dependencies.sh
# Updates all Python dependencies and resyncs to the bundled framework.
# Run this before each app release to pick up bug fixes from upstream.
#
# Usage: ./scripts/update_dependencies.sh [--check-only]

set -euo pipefail

CHECK_ONLY=false
if [[ "${1:-}" == "--check-only" ]]; then
    CHECK_ONLY=true
fi

SITE="Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages"
VENV=".venv"

echo "==> Upmarket dependency updater"
echo ""

# 1. Check current versions
echo "==> Current versions:"
$VENV/bin/pip show docling pymupdf pymupdf4llm torch 2>/dev/null | grep -E "^Name:|^Version:" | paste - - | column -t
echo ""

# 2. Check for updates
echo "==> Checking for updates..."
$VENV/bin/pip list --outdated 2>/dev/null | grep -E "docling|pymupdf|torch|transformers|huggingface" | head -20 || echo "All key packages up to date."
echo ""

if [ "$CHECK_ONLY" = true ]; then
    echo "==> Check-only mode — no changes made."
    exit 0
fi

# 3. Update packages
echo "==> Updating Python dependencies..."
$VENV/bin/pip install --upgrade \
    "docling>=2.96.0" \
    "pymupdf>=1.27.0" \
    "pymupdf4llm>=1.27.0" \
    "huggingface-hub>=1.17.0"
echo ""

# 4. Re-apply MPS float32 patch (may be overwritten by transformers update)
echo "==> Re-applying MPS compatibility patch..."
./scripts/patch_mps.sh "$VENV"
echo ""

# 5. Sync fast-path packages to bundled framework (Enhanced/AI are on-demand)
echo "==> Syncing fast-path packages to bundled framework..."
cp -r "$VENV/lib/python3.12/site-packages/pymupdf" "$SITE/"
cp -r "$VENV/lib/python3.12/site-packages/pymupdf4llm" "$SITE/"

# Strip debug symbols from native libs to reduce bundle size
echo "==> Stripping debug symbols..."
find "$SITE" -name "*.so" -exec strip -x {} \; 2>/dev/null || true
cp -r "$VENV/lib/python3.12/site-packages/transformers" "$SITE/"
cp -r "$VENV/lib/python3.12/site-packages/huggingface_hub" "$SITE/"

# Always sync our own Python bridge files
cp UpmarketPython/docling_bridge/*.py "$SITE/docling_bridge/"
cp UpmarketPython/models/*.py "$SITE/upmarket_models/"

# Re-apply MPS patch to bundled framework
./scripts/patch_mps.sh "$SITE"

echo ""
echo "==> Done. Rebuild the app in Xcode to include updated packages."
echo "    Remember to test conversion before releasing."
echo ""

# 6. Show new versions
echo "==> Updated versions:"
$VENV/bin/pip show docling pymupdf pymupdf4llm torch 2>/dev/null | grep -E "^Name:|^Version:" | paste - - | column -t
