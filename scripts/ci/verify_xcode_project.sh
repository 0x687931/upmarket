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

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required to validate $PROJECT"
  exit 1
fi

XCODEBUILD_VERSION_OUTPUT="$(xcodebuild -version)"
XCODE_VERSION="$(printf '%s\n' "$XCODEBUILD_VERSION_OUTPUT" | awk '/^Xcode / { print $2; exit }')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
REQUIRED_MAJOR="${UPMARKET_REQUIRED_XCODE_MAJOR:-26}"

if [[ -z "$XCODE_VERSION" || "$XCODE_MAJOR" == "$XCODE_VERSION" ]]; then
  echo "error: unable to parse xcodebuild version"
  printf '%s\n' "$XCODEBUILD_VERSION_OUTPUT"
  exit 1
fi

if (( XCODE_MAJOR < REQUIRED_MAJOR )); then
  echo "error: Xcode $REQUIRED_MAJOR or newer is required for $PROJECT; found Xcode $XCODE_VERSION"
  echo "       CI should run on macos-26 with DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer."
  exit 1
fi

echo "ok: xcodebuild version is Xcode $XCODE_VERSION"
echo "ok: Xcode project and scheme are valid"
