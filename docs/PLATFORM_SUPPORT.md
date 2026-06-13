# Platform Support Strategy

Upmarket targets macOS 13.3+ (Ventura) as the minimum deployment target. This document explains the macOS version requirements for specific features.

## Minimum Deployment Target: macOS 13.3 (Ventura)

All shipping code must remain compatible with macOS 13.3. This is enforced in `Upmarket.xcodeproj` under `MACOSX_DEPLOYMENT_TARGET`.

## Feature-Specific Version Requirements

### Writing Tools Refinement (macOS 15.1+)

**Status:** Available but not yet integrated.

`WritingToolsRefiner` is available on macOS 15.1+ (Sequoia) with Apple Silicon. The implementation is intentionally a graceful no-op because:

1. **API Limitation:** `NSWritingToolsCoordinator` requires a responder/view context (text editing surface).
2. **Architecture Mismatch:** Upmarket's conversion pipeline runs in the background without an active text view.
3. **Future Integration:** Writing Tools refinement could be wired to a post-conversion editor surface in a future release.

**Behavior:**
- macOS < 15.1: Returns input unchanged (`wasRefined = false`)
- macOS 15.1+: Returns input unchanged (`wasRefined = false`)
- Intel (any version): Returns input unchanged (`wasRefined = false`)

**Why Keep It?** The scaffolding is in place for future integration without requiring a major refactor.

### Foundation Models (macOS 26+, Apple Silicon)

**Status:** Available but returns fallback implementation.

`FoundationModelEnhancer` is available on macOS 26+ (Sequoia) with Apple Intelligence enabled. The implementation currently:

1. Falls back to title extraction from markdown headers.
2. Does not perform semantic enhancement.
3. Returns `wasEnhanced = false`.

**Why?** The Foundation Models framework is new (macOS 26) and still stabilizing. Once the API stabilizes, full semantic extraction (title, authors, abstract, key topics, section summaries) can be enabled.

### App Sandbox & Entitlements (macOS 13.3+)

The app sandbox is enforced on all supported macOS versions. Capabilities are gated by explicit entitlements:

- `com.apple.security.network.client`: Model download only (not enabled by default in sandbox)
- `com.apple.security.files.user-selected.read-write`: User-chosen file access
- `com.apple.security.application-groups`: Shared container for Quick Action extension

## Testing Across Versions

- **Unit tests** run on the current Xcode target (macOS 26, arm64).
- **Availability guards** are verified statically at build time.
- **Graceful degradation** is tested via `AppRuntime.isRunningTests` flag for controlled feature disabling.

## App Store Submission

The app is submitted from macOS 26 with Xcode 26. The minimum OS in App Store metadata is set to macOS 13.3, and users on earlier versions cannot download the app automatically. Users on unsupported versions who somehow obtain the app will see informative errors (not crashes) for unavailable features.
