#!/bin/bash
# bump_version.sh
#
# Automatically bumps app version based on commit type
# Usage: bump_version.sh [patch|minor|major]
# Default: patch
#
# Looks at recent commits and bumps version accordingly:
# - "fix:" commits → patch bump (1.0.0 → 1.0.1)
# - "feat:" commits → minor bump (1.0.0 → 1.1.0)
# - "BREAKING CHANGE" in commit body → major bump (1.0.0 → 2.0.0)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECT_FILE="$REPO_ROOT/Upmarket/Upmarket.xcodeproj/project.pbxproj"

# Determine bump type
BUMP_TYPE="${1:-auto}"

if [[ "$BUMP_TYPE" == "auto" ]]; then
  # Auto-detect from recent commits
  RECENT_COMMITS=$(git log --oneline -20 2>/dev/null || echo "")

  if echo "$RECENT_COMMITS" | grep -q "BREAKING CHANGE\|^.*!:"; then
    BUMP_TYPE="major"
  elif echo "$RECENT_COMMITS" | grep -q "^.*feat:"; then
    BUMP_TYPE="minor"
  else
    BUMP_TYPE="patch"
  fi
fi

if [[ ! "$BUMP_TYPE" =~ ^(patch|minor|major)$ ]]; then
  echo "❌ Invalid bump type: $BUMP_TYPE (use patch, minor, or major)"
  exit 1
fi

# Parse current version
CURRENT_VERSION=$(grep "MARKETING_VERSION = " "$PROJECT_FILE" | head -1 | sed 's/.*= //' | tr -d ';')
echo "Current version: $CURRENT_VERSION"

# Split version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Bump version
case "$BUMP_TYPE" in
  patch)
    PATCH=$((PATCH + 1))
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "Bumping to version: $NEW_VERSION ($BUMP_TYPE bump)"

# Update version in project.pbxproj
# Note: This is a naive approach that works for our specific case
# For more complex projects, consider using xcodeproj gem
sed -i '' "s/MARKETING_VERSION = $CURRENT_VERSION/MARKETING_VERSION = $NEW_VERSION/g" "$PROJECT_FILE"

# Also update CURRENT_PROJECT_VERSION to match
# In a real scenario, you might keep CURRENT_PROJECT_VERSION as a build counter
sed -i '' "s/CURRENT_PROJECT_VERSION = 1/CURRENT_PROJECT_VERSION = 1/g" "$PROJECT_FILE"

echo "✅ Version bumped to $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff Upmarket/Upmarket.xcodeproj/project.pbxproj"
echo "  2. Commit: git commit -m 'Bump version to $NEW_VERSION'"
echo "  3. Tag: git tag v$NEW_VERSION"
echo "  4. Push: git push origin main --tags"
