#!/usr/bin/env bash
set -euo pipefail

PROJECT="Upmarket/Upmarket.xcodeproj"
SCHEME="Upmarket"
SCHEME_FILE="$PROJECT/xcshareddata/xcschemes/$SCHEME.xcscheme"

if [[ ! -d "$PROJECT" ]]; then
  echo "error: Xcode project not found at $PROJECT"
  exit 1
fi

if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  echo "error: project.pbxproj missing from $PROJECT"
  exit 1
fi

if [[ ! -f "$SCHEME_FILE" ]]; then
  echo "error: shared scheme missing: $SCHEME_FILE"
  exit 1
fi

echo "ok: Xcode project and scheme are valid"
