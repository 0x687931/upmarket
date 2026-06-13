#!/bin/bash
# build_python_tiers.sh
#
# Builds three separate Python environments per the tier contract:
# 1. BASIC (bundled in app): Python 3.12 + ocrmac + minimal utilities
# 2. PRO (user download): Basic + Docling + office format handlers (~350MB)
# 3. MAX (user download): torch, mlx, transformers, onnxruntime (~750MB)
#
# See docs/TIER_CONTRACT.md for details.

set -euo pipefail

PYTHON_VERSION="3.12"
BEEWARE_VERSION="3.12-b8"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==> Upmarket Python Tier Builder"
echo "    Generates: Basic (bundled) + Pro (download) + Max (download)"
echo ""

# Validate tier contract files exist
for file in requirements.txt requirements-pro.txt requirements-ai.txt docs/TIER_CONTRACT.md; do
  if [[ ! -f "$REPO_ROOT/$file" ]]; then
    echo "❌ Missing $file"
    exit 1
  fi
done

echo "✅ Tier contract files validated"
echo ""

# Function to build a Python environment
build_tier() {
  local tier=$1
  local requirements_file=$2
  local output_dir=$3

  echo "==> Building $tier tier from $requirements_file"
  echo "    Output: $output_dir"

  mkdir -p "$output_dir"

  # Create build venv
  local build_venv=$(mktemp -d "${TMPDIR:-/tmp}/upmarket-build-$tier.XXXXXX")
  trap "rm -rf '$build_venv'" EXIT

  python3 -m venv "$build_venv"
  "$build_venv/bin/python" -m pip install --upgrade pip >/dev/null 2>&1

  # Install requirements to output dir
  "$build_venv/bin/python" -m pip install \
    --disable-pip-version-check \
    --target "$output_dir" \
    --requirement "$REPO_ROOT/$requirements_file"

  echo "    ✅ $tier tier built"
  echo ""
}

# For now, just validate the process
echo "⚠️  This script is ready but requires:"
echo "   1. Modification to existing build_python_env.sh to use requirements-basic.txt"
echo "   2. Setup for downloadable packages (Pro & Max runtimes)"
echo "   3. Integration with App Store Background Assets delivery"
echo ""
echo "Next step: Create requirements-basic.txt with only:"
echo "   - ocrmac (macOS Vision OCR)"
echo "   - pydantic, pillow, numpy (utilities)"
echo ""
echo "Then update build_python_env.sh to:"
echo "   - Bundle only requirements-basic.txt in app (~50MB)"
echo "   - Provide separate build commands for Pro and Max downloads"
