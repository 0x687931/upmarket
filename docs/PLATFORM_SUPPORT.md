# Platform Support Strategy

Upmarket targets macOS 13.3+ (Ventura) as the minimum deployment target. This document explains the macOS version requirements for specific features.

## Minimum Deployment Target: macOS 13.3 (Ventura)

All shipping code must remain compatible with macOS 13.3. This is enforced in `Upmarket.xcodeproj` under `MACOSX_DEPLOYMENT_TARGET`.

## Feature-Specific Version Requirements

### AI Conversion Pipeline (Advanced/VLM)

**Status:** Implemented. Routes to Docling with AI models when available.

When a user requests "AI Conversion", the app uses Docling's Vision Language Model (VLM) pipeline for improved document understanding:

1. **For PDFs:**
   - Runs Docling with VLM + layout analysis
   - Better table extraction
   - Improved text flow understanding
   - Preserves document structure

2. **For Images/TIFF:**
   - Uses VLM to understand image content natively
   - No OCR fallback needed (VLM reads directly)
   - Better diagram/chart interpretation

**Requirements:**
- Max tier (paid)
- Apple Silicon (device must support AI)
- Python runtime installed
- AI models downloaded and installed

**Graceful Degradation:**
- Missing any requirement → Falls back to basic PDFKit/Vision OCR
- No error shown to user; users get slightly lower quality output
- Console logs the fallback reason for debugging

**How It Works:**

1. User clicks "Convert with AI" (or selects Max tier pathway)
2. ConversionRunner checks: `supportsAdvancedRuntime && supportsAI && modelsReady()`
3. If all checks pass → Routes to `runQualitySelectedPDFConversion(..., useAI: true)`
4. If any check fails → Falls back to basic conversion, no interruption

This is not "feature gating" (blocking users); it's intelligent routing based on device capabilities.

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

### Foundation Models Enhancement (macOS 26+, Apple Intelligence)

**Status:** Implemented. Extracts structured metadata from documents.

`FoundationModelEnhancer` uses Apple's on-device Foundation Models (~3B parameters) to extract:

1. **Document Metadata**
   - Main title
   - Author names
   - One-sentence abstract
   - Document type (academic, business, technical, legal, general)
   - Up to 5 key topics

2. **Section Summaries** (first 5 sections)
   - Section heading
   - One-sentence summary
   - Up to 3 key points

**Requirements:**
- macOS 26+ (Sequoia)
- Apple Intelligence enabled
- Foundation Models framework available

**Graceful Degradation:**
- macOS < 26: Falls back to header-based title extraction
- Foundation Models unavailable: Header extraction only
- Model call fails (out of memory, etc): Header extraction + error logged
- Test mode: Header extraction only (for consistent test results)

**Example Output:**

For a PDF about machine learning:
```
Title: "Deep Learning with Neural Networks"
Authors: ["Jane Doe", "John Smith"]
Abstract: "A comprehensive guide to building and training deep neural networks"
Document Type: "technical"
Key Topics: ["neural networks", "deep learning", "backpropagation", "optimization", "CNNs"]
```

This enhancement only runs on Max tier with Apple Intelligence available. Basic and Pro tiers use header-based title extraction.

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
