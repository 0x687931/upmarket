#!/bin/bash
# build_python_env.sh
# Downloads BeeWare Python-Apple-support when needed and rebuilds the bundled
# Python runtime from release pins.
#
# Usage: ./scripts/build_python_env.sh

set -euo pipefail

PYTHON_VERSION="3.12"
BEEWARE_VERSION="3.12-b8"   # update to latest BeeWare release
DEST="Upmarket/Python"
FRAMEWORK_ROOT="$DEST/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/$PYTHON_VERSION"
SITE="$FRAMEWORK_ROOT/lib/python$PYTHON_VERSION/site-packages"

echo "==> Upmarket Python environment builder"
echo "    Python: $PYTHON_VERSION"
echo "    BeeWare: $BEEWARE_VERSION"
echo ""

FRAMEWORK_URL="https://github.com/beeware/Python-Apple-support/releases/download/${BEEWARE_VERSION}/Python-${PYTHON_VERSION}-macOS-support.b8.tar.gz"

echo "==> Validating exact release pins"
scripts/ci/validate_dependency_lock.py
echo ""

if [[ ! -d "$FRAMEWORK_ROOT" ]]; then
  echo "==> Downloading Python.xcframework..."
  mkdir -p "$DEST"
  curl -L "$FRAMEWORK_URL" -o /tmp/python-apple-support.tar.gz
  tar -xzf /tmp/python-apple-support.tar.gz -C "$DEST"
  echo "    Done."
else
  echo "==> Reusing existing Python.xcframework at $FRAMEWORK_ROOT"
fi
echo ""

echo "==> Rebuilding bundled site-packages from requirements.txt"
mkdir -p "$(dirname "$SITE")"
STAGING_SITE="$(mktemp -d "${TMPDIR:-/tmp}/upmarket-site-packages.XXXXXX")"
BUILD_VENV="$(mktemp -d "${TMPDIR:-/tmp}/upmarket-python-build.XXXXXX")"
trap 'rm -rf "$STAGING_SITE" "$BUILD_VENV"' EXIT
python3 -m venv "$BUILD_VENV"
"$BUILD_VENV/bin/python" -m pip install \
  --disable-pip-version-check \
  --upgrade pip
"$BUILD_VENV/bin/python" -m pip install \
  --disable-pip-version-check \
  --ignore-installed \
  --target "$STAGING_SITE" \
  --requirement requirements.txt
echo ""

echo "==> Copying first-party bridge packages"
scripts/ci/sync_python_bridge.sh "$STAGING_SITE"
echo ""

echo "==> Replacing bundled site-packages"
rm -rf "$SITE"
mv "$STAGING_SITE" "$SITE"
trap - EXIT
echo ""

echo "==> Stripping unused stdlib modules..."
./scripts/strip_stdlib.sh "$FRAMEWORK_ROOT"
echo "    Done."
echo ""

echo "==> Verifying bundled Python imports and package pins"
scripts/ci/verify_python_bundle.sh

echo ""
echo "==> Python environment ready at $DEST"
