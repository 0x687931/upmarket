#!/bin/bash
# strip_stdlib.sh
# Removes unused Python stdlib modules to reduce app bundle size.
# Targets ~30-40% size reduction by removing test suites, unused encodings, etc.
#
# Usage: ./scripts/strip_stdlib.sh <stdlib-path>

set -euo pipefail

STDLIB="$1"

if [ -z "$STDLIB" ] || [ ! -d "$STDLIB" ]; then
    echo "Usage: $0 <stdlib-path>"
    exit 1
fi

echo "  Removing test suites..."
find "$STDLIB" -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
find "$STDLIB" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true

echo "  Removing unused encodings..."
# Keep text basics, IDNA for HTTPS downloads, and CP437 for ZIP metadata.
ENCODINGS="$STDLIB/lib/python*/encodings"
for enc_dir in $ENCODINGS; do
    find "$enc_dir" -name "*.py" \
        ! -name "__init__.py" \
        ! -name "utf_8*" \
        ! -name "ascii*" \
        ! -name "latin_1*" \
        ! -name "idna*" \
        ! -name "cp437*" \
        ! -name "utf_16*" \
        ! -name "utf_32*" \
        ! -name "aliases*" \
        -delete 2>/dev/null || true
done

echo "  Removing __pycache__ bytecode..."
find "$STDLIB" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

echo "  Removing .pyc files..."
find "$STDLIB" -name "*.pyc" -delete 2>/dev/null || true

echo "  Size after strip: $(du -sh "$STDLIB" | cut -f1)"
