# Platform Support Strategy

Upmarket targets macOS 13.3+ (Ventura) as the minimum deployment target. This document explains the macOS version requirements for specific features.

## Minimum Deployment Target: macOS 13.3 (Ventura)

All shipping code must remain compatible with macOS 13.3. This is enforced in `Upmarket.xcodeproj` under `MACOSX_DEPLOYMENT_TARGET`.

## Feature-Specific Version Requirements

### Writing Tools Refinement (macOS 15.1+)

**Status:** Implemented with sentence-merging and text cleanup.

`WritingToolsRefiner` refines extracted Markdown by merging broken sentences and cleaning up whitespace. This addresses the most common PDF extraction artifact: sentences split across line breaks during OCR or layout extraction.

**What It Does:**
1. **Merge broken sentences** — Detects when a sentence was split across lines and merges them back together.
2. **Preserve structure** — Respects paragraph boundaries (double newlines), headings, lists, and code blocks.
3. **Clean whitespace** — Removes excessive blank lines and normalizes spacing.
4. **Detect improvements** — Sets `wasRefined = true` only if actual changes were made.

**Implementation Details:**
- Uses heuristic-based sentence detection (looks for sentence terminators: `.`, `!`, `?`, `:`)
- Runs synchronously on background thread (via Task.detached)
- Operates on paragraph chunks for memory efficiency
- Does not depend on NSWritingToolsCoordinator (which requires a view context)

**Example:**
```
Input:
This sentence was broken
across two lines in the PDF. And this is another sentence.

Output:
This sentence was broken across two lines in the PDF. And this is another sentence.
```

**Future Enhancement:**
On macOS 15.1+, the implementation could be extended to optionally use `NSWritingToolsCoordinator` if a user-facing editor surface is added. Currently, this background refinement provides solid baseline improvement without requiring view context.

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
