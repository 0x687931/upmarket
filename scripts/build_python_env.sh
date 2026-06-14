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
BUILD_PYTHON="${PYTHON_BUILD_BIN:-}"

# The build interpreter MUST match the bundled framework's Python ($PYTHON_VERSION):
# pip installs version-tagged native wheels (cpython-3XY), and a mismatched version
# produces extensions that cannot import in the shipped runtime. Do NOT silently fall
# back to whatever python3 happens to be around.
if [[ -z "$BUILD_PYTHON" ]]; then
  if command -v "python$PYTHON_VERSION" >/dev/null 2>&1; then
    BUILD_PYTHON="python$PYTHON_VERSION"
  elif command -v uv >/dev/null 2>&1 && uv python find "$PYTHON_VERSION" >/dev/null 2>&1; then
    BUILD_PYTHON="$(uv python find "$PYTHON_VERSION")"
  else
    echo "error: need a Python $PYTHON_VERSION interpreter to match the bundled framework."
    echo "       Install one (uv python install $PYTHON_VERSION  /  brew install python@$PYTHON_VERSION)"
    echo "       or set PYTHON_BUILD_BIN to a $PYTHON_VERSION interpreter."
    exit 1
  fi
fi

BUILD_PYTHON_VERSION="$("$BUILD_PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

if [[ "$BUILD_PYTHON_VERSION" != "$PYTHON_VERSION" ]]; then
  echo "error: build interpreter is $BUILD_PYTHON_VERSION but the framework is Python $PYTHON_VERSION."
  echo "       Mismatched wheels (cpython-${BUILD_PYTHON_VERSION//./}*) cannot load. Use a"
  echo "       $PYTHON_VERSION interpreter via PYTHON_BUILD_BIN and rebuild."
  exit 1
fi

echo "==> Upmarket Python environment builder"
echo "    Python: $PYTHON_VERSION"
echo "    BeeWare: $BEEWARE_VERSION"
echo "    Build interpreter: $BUILD_PYTHON ($BUILD_PYTHON_VERSION)"
echo ""

FRAMEWORK_URL="https://github.com/beeware/Python-Apple-support/releases/download/${BEEWARE_VERSION}/Python-${PYTHON_VERSION}-macOS-support.b8.tar.gz"
XCFRAMEWORK_PLIST="$DEST/Python.xcframework/Info.plist"

if [[ -f "$XCFRAMEWORK_PLIST" ]] && ! plutil -lint "$XCFRAMEWORK_PLIST" >/dev/null 2>&1; then
  echo "==> Existing Python.xcframework Info.plist is invalid; removing stale bundle"
  rm -rf "$DEST/Python.xcframework"
fi

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

echo "==> Rebuilding bundled site-packages from requirements-basic.txt"
echo "    (Pro & Max tier dependencies download separately per tier contract)"
mkdir -p "$(dirname "$SITE")"
STAGING_SITE="$(mktemp -d "${TMPDIR:-/tmp}/upmarket-site-packages.XXXXXX")"
BUILD_VENV="$(mktemp -d "${TMPDIR:-/tmp}/upmarket-python-build.XXXXXX")"
trap 'rm -rf "$STAGING_SITE" "$BUILD_VENV"' EXIT
"$BUILD_PYTHON" -m venv "$BUILD_VENV"
"$BUILD_VENV/bin/python" -m pip install \
  --disable-pip-version-check \
  --upgrade pip
"$BUILD_VENV/bin/python" -m pip install \
  --disable-pip-version-check \
  --ignore-installed \
  --target "$STAGING_SITE" \
  --requirement requirements-basic.txt
echo ""

echo "==> Removing magika (AI file-type detector) + onnxruntime; patching markitdown"
# markitdown hard-depends on magika, which pulls onnxruntime (~66MB) and SIGTRAPs in
# the embedded runtime. Magika only guesses file type — we already know it from the
# extension — so remove it and stub markitdown's call. See markitdown#1234.
rm -rf "$STAGING_SITE"/magika "$STAGING_SITE"/magika-*.dist-info
rm -rf "$STAGING_SITE"/onnxruntime "$STAGING_SITE"/onnxruntime-*.dist-info
# The magika wheel installs a 27MB compiled Mach-O CLI at bin/magika that survives the
# package removal — pure dead weight, and an unsigned executable that would fail
# notarization. Drop it plus onnxruntime's leftover console script.
rm -f "$STAGING_SITE"/bin/magika "$STAGING_SITE"/bin/onnxruntime_test
"$BUILD_VENV/bin/python" - "$STAGING_SITE/markitdown/_markitdown.py" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
stub = (
    "# Upmarket: magika removed (AI file-type detector + onnxruntime). File types come\n"
    "# from the extension; a disabled stub keeps markitdown's code path intact.\n"
    "class _UpmarketNoMagika:\n"
    "    class _Result:\n"
    "        status = \"disabled\"\n"
    "    def identify_stream(self, *args, **kwargs):\n"
    "        return self._Result()\n"
)
assert "import magika\n" in src, "markitdown magika import not found"
src = src.replace("import magika\n", stub, 1)
assert "self._magika = magika.Magika()" in src, "markitdown magika init not found"
src = src.replace("self._magika = magika.Magika()", "self._magika = _UpmarketNoMagika()", 1)
p.write_text(src)
print("    patched markitdown to disable magika")
PYEOF
# Drop magika from markitdown's declared deps so `pip check` and the dependency graph
# stay consistent with its removal.
MD_META="$STAGING_SITE/markitdown-0.1.6.dist-info/METADATA"
if [[ -f "$MD_META" ]]; then
  grep -v '^Requires-Dist: magika' "$MD_META" > "$MD_META.tmp" && mv "$MD_META.tmp" "$MD_META"
fi
echo ""

echo "==> Copying first-party bridge packages"
scripts/ci/sync_python_bridge.sh "$STAGING_SITE"
echo ""

echo "==> Normalizing package markers that confuse Xcode bundle scanners"
for marker in \
  "$STAGING_SITE/google/protobuf/compiler/__init__.py" \
  "$STAGING_SITE/google/protobuf/pyext/__init__.py" \
  "$STAGING_SITE/google/protobuf/testdata/__init__.py" \
  "$STAGING_SITE/google/protobuf/util/__init__.py"
do
  if [[ -f "$marker" && ! -s "$marker" ]]; then
    printf '# Package marker for Xcode bundle scanning.\n' > "$marker"
  fi
done
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

echo "==> Thinning universal binaries to arm64 (dropping the Intel slice)"
# The BeeWare framework dylib + stdlib .so are universal; arm64-only is our target.
# pip-built site-packages are already arm64, so this only touches the framework/stdlib.
thinned=0
while IFS= read -r -d '' f; do
  if lipo -archs "$f" 2>/dev/null | grep -q x86_64; then
    if lipo -thin arm64 "$f" -output "$f.arm64" 2>/dev/null; then
      mv "$f.arm64" "$f"
      thinned=$((thinned + 1))
    fi
  fi
done < <(find "$FRAMEWORK_ROOT" -type f \( -name "*.so" -o -name "*.dylib" -o -name "Python" \) -print0 2>/dev/null)
echo "    Thinned $thinned universal binaries to arm64."
echo ""

echo "==> Verifying bundled Python imports and package pins"
scripts/ci/verify_python_bundle.sh

echo ""
echo "==> Python environment ready at $DEST"
