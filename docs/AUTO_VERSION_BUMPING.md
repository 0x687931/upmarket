# Automatic Version Bumping

Upmarket now supports automatic version bumping based on commit types using semantic versioning (SemVer).

## Overview

- **Patch (1.0.0 → 1.0.1)**: Bug fixes, small improvements
- **Minor (1.0.0 → 1.1.0)**: New features, backwards-compatible changes
- **Major (1.0.0 → 2.0.0)**: Breaking changes, major rewrites

## Commit Message Format

Use standard Git commit message conventions:

```bash
# Patch (bug fixes)
git commit -m "fix: correct typo in preferences panel"

# Minor (features)
git commit -m "feat: add tier-based download architecture"

# Major (breaking changes)
git commit -m "feat!: redesign conversion API

BREAKING CHANGE: ConversionQueue interface has changed"
```

Conventional formats:
- `fix:` → patch version bump
- `feat:` → minor version bump
- `BREAKING CHANGE` or `!:` → major version bump

## Usage

### Automatic Detection (Recommended)

The script auto-detects the bump type from recent commits:

```bash
scripts/ci/bump_version.sh
```

This will:
1. Scan last 20 commits for conventional commit patterns
2. Determine appropriate bump type (major > minor > patch)
3. Update version in Xcode project
4. Display next steps

### Manual Specification

Explicitly specify bump type:

```bash
scripts/ci/bump_version.sh patch
scripts/ci/bump_version.sh minor
scripts/ci/bump_version.sh major
```

## Integration with Release Process

### Before Release

```bash
# 1. Run tests to ensure CI is clear
scripts/ci/gate.sh quick

# 2. Bump version (auto-detects from commits)
scripts/ci/bump_version.sh

# 3. Review changes
git diff Upmarket/Upmarket.xcodeproj/project.pbxproj

# 4. Commit version bump
git commit -m "Bump version to X.Y.Z"

# 5. Create release tag
git tag vX.Y.Z

# 6. Push to main
git push origin main --tags
```

### CI/CD Integration

To automatically bump versions in CI:

```bash
# In your CI script or pre-release step:
scripts/ci/bump_version.sh

# Then proceed with build and release
```

## Current Version

Check the current version:

```bash
# In Xcode
# Upmarket target → General → Version (MARKETING_VERSION)

# Or via command line:
grep "MARKETING_VERSION = " Upmarket/Upmarket.xcodeproj/project.pbxproj | head -1
```

Current version: **1.0**

## Examples

### Releasing a Bug Fix

```bash
# Make bug fix
git commit -m "fix: resolve crash in preferences panel"

# Auto-bump detects 'fix:' and bumps patch
scripts/ci/bump_version.sh
# → 1.0.1

# Continue with release
git commit -m "Bump version to 1.0.1"
git tag v1.0.1
git push origin main --tags
```

### Releasing a New Feature

```bash
# Add new feature
git commit -m "feat: implement tier-based downloads"

# Auto-bump detects 'feat:' and bumps minor
scripts/ci/bump_version.sh
# → 1.1.0

git commit -m "Bump version to 1.1.0"
git tag v1.1.0
git push origin main --tags
```

### Major Release

```bash
# Major refactor with breaking changes
git commit -m "feat!: redesign conversion architecture

BREAKING CHANGE: ConversionJob interface changed"

# Auto-bump detects breaking change and bumps major
scripts/ci/bump_version.sh
# → 2.0.0

git commit -m "Bump version to 2.0.0"
git tag v2.0.0
git push origin main --tags
```

## Troubleshooting

### Version didn't bump as expected

Check your commit messages:
```bash
git log --oneline -20 | head -10
```

Messages must start with `fix:`, `feat:`, or contain `BREAKING CHANGE` for auto-detection.

### Manual version update needed

If auto-bump logic doesn't work for your case:

1. Edit `Upmarket/Upmarket.xcodeproj/project.pbxproj` directly
2. Find `MARKETING_VERSION = X.Y.Z`
3. Update to desired version
4. Commit: `git commit -m "Bump version to X.Y.Z"`

## Related Files

- `scripts/ci/bump_version.sh` - Auto-version script
- `Upmarket/Upmarket.xcodeproj/project.pbxproj` - Version source
- `Upmarket/Upmarket/Info.plist` - Runtime version check
