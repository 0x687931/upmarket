#!/bin/bash
# build_python_env.sh
# Downloads BeeWare Python-Apple-support and builds the bundled Python environment.
# Run once before opening Xcode, and again after changing requirements.txt.
#
# Usage: ./scripts/build_python_env.sh

set -euo pipefail

PYTHON_VERSION="3.12"
BEEWARE_VERSION="3.12-b8"   # update to latest BeeWare release
DEST="Upmarket/Python"

echo "==> Upmarket Python environment builder"
echo "    Python: $PYTHON_VERSION"
echo "    BeeWare: $BEEWARE_VERSION"
echo ""

# 1. Download BeeWare Python-Apple-support
FRAMEWORK_URL="https://github.com/beeware/Python-Apple-support/releases/download/${BEEWARE_VERSION}/Python-${PYTHON_VERSION}-macOS-support.b8.tar.gz"

echo "==> Downloading Python.xcframework..."
mkdir -p "$DEST"
curl -L "$FRAMEWORK_URL" -o /tmp/python-apple-support.tar.gz
tar -xzf /tmp/python-apple-support.tar.gz -C "$DEST"
echo "    Done."

# 2. Create venv and install requirements
echo "==> Installing Python dependencies..."
PYTHON_BIN="$DEST/python-stdlib/bin/python3"

# Use system Python to create a cross-platform site-packages
python3 -m pip install \
    --target "$DEST/python-stdlib/lib/python${PYTHON_VERSION}/site-packages" \
    --no-deps \
    -r requirements.txt
echo "    Done."

# 3. Strip unnecessary stdlib modules to reduce bundle size
echo "==> Stripping unused stdlib modules..."
./scripts/strip_stdlib.sh "$DEST/python-stdlib"
echo "    Done."

echo ""
echo "==> Python environment ready at $DEST"
echo "    Add Python.xcframework and python-stdlib to your Xcode project."
