#!/bin/bash
# build_python_packages.sh
#
# Builds downloadable Python packages for Pro and Max tiers per TIER_CONTRACT.md:
#   - python_runtime_pro (~350MB): Docling + office format handlers
#   - ai_libraries (~750MB): torch, mlx, transformers, onnxruntime
#
# Usage: ./scripts/build_python_packages.sh [--pro] [--ai] [--output /path]
# Default: builds both and outputs to ./build/python_packages/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

BUILD_PRO=false
BUILD_AI=false
OUTPUT_DIR="$REPO_ROOT/build/python_packages"

# Parse arguments
if [[ $# -eq 0 ]]; then
  BUILD_PRO=true
  BUILD_AI=true
else
  while [[ $# -gt 0 ]]; do
    case $1 in
      --pro) BUILD_PRO=true; shift ;;
      --ai) BUILD_AI=true; shift ;;
      --output) OUTPUT_DIR="$2"; shift 2 ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done
fi

mkdir -p "$OUTPUT_DIR"

# Determine Python version from existing bundle or default
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
BUILD_PYTHON="${PYTHON_BUILD_BIN:-python3}"

echo "==> Upmarket Python Package Builder"
echo "    Python: $PYTHON_VERSION"
echo "    Output: $OUTPUT_DIR"
echo ""

# Validate requirements files
for file in requirements-basic.txt requirements-pro.txt requirements-ai.txt; do
  if [[ ! -f "$REPO_ROOT/$file" ]]; then
    echo "❌ Missing $file"
    exit 1
  fi
done

# Function to build a tier package
build_package() {
  local package_name=$1
  local requirements_file=$2
  local output_file=$3

  echo "==> Building $package_name from $requirements_file"

  # Create temporary build environment
  local build_venv=$(mktemp -d "${TMPDIR:-/tmp}/upmarket-build-$package_name.XXXXXX")
  trap "rm -rf '$build_venv'" EXIT

  # Create staging directory for site-packages
  local staging_site="$build_venv/lib/python$PYTHON_VERSION/site-packages"
  mkdir -p "$staging_site"

  # Create and activate venv
  echo "    Creating build environment..."
  "$BUILD_PYTHON" -m venv "$build_venv" >/dev/null 2>&1

  # Upgrade pip
  "$build_venv/bin/python" -m pip install --upgrade pip >/dev/null 2>&1

  # Install requirements
  echo "    Installing packages..."
  "$build_venv/bin/python" -m pip install \
    --disable-pip-version-check \
    --target "$staging_site" \
    --requirement "$REPO_ROOT/$requirements_file" >/dev/null 2>&1

  # Create ready marker file
  mkdir -p "$build_venv"
  touch "$build_venv/lib/${package_name}_ready"

  # Package into tar.gz
  echo "    Compressing to tar.gz..."
  mkdir -p "$(dirname "$output_file")"
  tar -czf "$output_file" -C "$build_venv" lib "${package_name}_ready" 2>/dev/null

  local size=$(du -h "$output_file" | cut -f1)
  echo "    ✅ $package_name: $output_file ($size)"
  echo ""

  trap - EXIT
  rm -rf "$build_venv"
}

# Build Pro package
if [[ "$BUILD_PRO" == "true" ]]; then
  build_package "python_runtime_pro" "requirements-pro.txt" "$OUTPUT_DIR/python_runtime_pro.tar.gz"
fi

# Build AI package
if [[ "$BUILD_AI" == "true" ]]; then
  build_package "ai_libraries" "requirements-ai.txt" "$OUTPUT_DIR/ai_libraries.tar.gz"
fi

echo "==> Package build complete"
echo ""
echo "Next steps:"
echo "  1. Upload packages to GitHub Releases or CDN"
echo "  2. Register URLs in App Store Connect Background Assets"
echo "  3. Update Info.plist with UpmarketBAAssetURL_* keys for local testing"
echo ""
echo "Files created:"
ls -lh "$OUTPUT_DIR"/*.tar.gz 2>/dev/null || echo "  (no files created)"
