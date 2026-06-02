# Upmarket Implementation Plan

## Product Goal

Upmarket converts documents to clean Markdown on macOS with a privacy-first, local-first architecture. The app should work immediately with native/fast conversion, offer optional local model downloads for harder documents, and remain understandable when conversion is slow, blocked, unsupported, or degraded.

## Release Principle

Ship v1.0 only when the core conversion path is reliable under real documents. Prefer Apple-native APIs, Xcode diagnostics, StoreKit tooling, and system privacy/security behavior over third-party services unless a native option is unavailable.

## Current Architecture

```text
SwiftUI app and shelf UI
  -> Apple-native conversion paths where available
     - PDFKit for fast digital PDF extraction on macOS 13-15
     - Vision structured extraction when available
     - Speech framework for local audio transcription where supported
  -> Signed helper process for advanced/model conversion
     - Codable request/response and heartbeat events over standard I/O
     - packaged runtime imports isolated from the main app process
     - helper crashes, bad exits, invalid responses, and stalls map to typed Swift errors
  -> StoreKit 2 for trial, paid unlocks, pack credits, restore purchases
  -> Models cached in ~/Library/Application Support/Upmarket/models/
```

Runtime conversion must not require cloud inference. Network access is limited to model download, StoreKit/App Store flows, and remote feature flags.

## P0 Audit Blockers

These items block mission-critical use, TestFlight confidence, and App Store submission. They must be resolved before v1.0 release gates can pass.

### P0 - Philosophy Review Remediation
- [x] [#15](https://github.com/0x687931/upmarket/issues/15) Restore the primary conversion surface and wire the `Convert Document...` command so the running app has one visible choose/drop -> progress -> Markdown -> copy/save loop.
- [x] [#16](https://github.com/0x687931/upmarket/issues/16) Surface rejected inputs as actionable conversion failures instead of silently logging and returning.
- [x] [#18](https://github.com/0x687931/upmarket/issues/18) Bind conversion UI to queue-owned `ConversionJob` state instead of duplicate global phase/result/password state.
- [x] [#17](https://github.com/0x687931/upmarket/issues/17) Centralize supported input policy across file picker, drops, App Intents, Services, and Quick Action.
- [x] [#19](https://github.com/0x687931/upmarket/issues/19) Fix model install state, feature gating, download progress, and model validation so setup is explicit and release-gated.
- [x] [#22](https://github.com/0x687931/upmarket/issues/22) Attach failed-job context to privacy-redacted support reports and keep diagnostic/support copy neutral.
- [x] [#20](https://github.com/0x687931/upmarket/issues/20) Make programmatic conversion authorization deterministic across entitlement refresh, AI availability, and credit consumption.
- [x] [#21](https://github.com/0x687931/upmarket/issues/21) Add regression coverage and release checks for the philosophy-review remediation set.
- [x] [#24](https://github.com/0x687931/upmarket/issues/24) Align paywall timing with the value-first product loop so onboarding/tour completion does not prompt before conversion value.
- [x] [#23](https://github.com/0x687931/upmarket/issues/23) Preserve serialized conversion semantics during active-job cancellation.

### P0 - Minimalist Monolith Architecture
- [x] Adopt the project philosophy in `docs/PROJECT_VISION.md`: Linus-style minimalism plus DHH-style coherent monolith.
- [x] Define the target source layout with small hard boundaries: Views, Domain, Services, Infrastructure, Resources, and release docs.
- [x] Keep file access behind a concrete service; views must not own file picker, save panel, or pasteboard mechanics.
- [x] Remove speculative architecture, duplicate conversion entry points, and unused product surfaces that do not support conversion, monetization, diagnostics, or release safety.
- [x] Add a simplification gate that rejects hidden launch windows, zero-size placeholder scenes, and create-then-hide AppKit window workarounds.
- [x] Add a lightweight architecture decision record whenever a P0 decision adds a new dependency, new process boundary, new entitlement, or new release hook.
- [x] Complete the P0 minimalist core rewrite: `ConversionQueue`, `ConversionRunner`, `PythonWorker`, and small `Domain/` models with no TCA, no enterprise layers, no protocol forests, and no speculative abstractions.
- [x] Move remaining StoreKit accounting and diagnostics behind the P0-007 and P0-008 service boundaries.

### P0 - Minimalist Core Rewrite
- [x] Add `Domain/ConversionJob.swift`, `Domain/ConversionResult.swift`, `Domain/ConversionError.swift`, and `Domain/Entitlement.swift` or document why any file remains unnecessary.
- [x] Add `@MainActor final class ConversionQueue: ObservableObject` with `jobs`, `add(_:)`, `cancel(_:)`, and `retry(_:)`.
- [x] Add `ConversionRunner` with `run(_ job: ConversionJob) async -> ConversionResult`.
- [x] Add `PythonWorker` as the single Python conversion/model call boundary; no view, queue, runner, or model service should import `PythonKit` directly after this rewrite.
- [x] Deprecate or remove `ConversionService.shared.result` polling from shelf, intents, and views.
- [x] Keep existing UI, shelf, paywall, product IDs, and monetization behavior intact unless the task explicitly proves a change is required.
- [x] Add small tests for queue correctness, cancellation, and no-progress classification without a hard five-minute timeout; deeper Python failure injection remains under P0-002/P0-008.

### P0 - Python Runtime Isolation
- [x] Move Python conversion/model execution out of the main app process into a signed helper, preferably XPC; map helper crashes, hangs, and exits to typed Swift errors.
- [x] Gate every Python call behind `PythonWorker` or a lower-level bootstrap bridge that verifies Python readiness, serializes interpreter access, catches bridge failures, and disables conversion/model UI when unavailable.
- [x] Make the Python packaging path reproducible: copy first-party bridge packages into the embedded runtime, pin dependencies, validate the embedded dependency graph, and smoke-test imports from the packaged app.

P0-002 implementation note: `UpmarketRuntimeHelper` is a sandboxed command-line helper embedded in `Upmarket.app/Contents/MacOS` and launched per advanced/model operation by `RuntimeHelperClient`. This keeps native Apple paths in process while containing packaged runtime imports and execution outside the app process. See `docs/release/adr/0003-isolated-runtime-helper.md`.

### P0 - Conversion Job Correctness
- [x] Replace singleton `ConversionService.result` polling with `ConversionQueue` and `ConversionRunner`.
- [x] Serialize shelf/app-intent conversions through `ConversionQueue`; each queued item must own its own result, error, progress, and cancellation state.
- [x] Add per-job IDs, stage updates, progress/heartbeat signals, Cancel/Retry UI, and stuck-state classification based on missing progress rather than elapsed time alone.
- [x] Lock terminal conversion states so late progress updates cannot reopen completed, failed, or cancelled jobs.
- [x] Guarantee conversion state reset and temp cleanup on success, failure, cancellation, helper crash, app quit, and startup cleanup of stale job directories.

### P0 - Offline and Model Integrity
- [x] Default conversion runtime to offline mode: `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`, and local-files-only model loading.
- [x] Permit network only inside the explicit model download flow; AI conversion now fails locally with a clear model-missing or model-corrupt error.
- [x] Pin immutable model revisions, download to staging directories, verify expected files/checksums, write a validation manifest, and atomically promote completed downloads.
- [x] Treat partial, corrupt, stale, or unexpected model directories as unavailable.

### P0 - Native Apple Replacements and Sandbox Safety
- [x] Replace Python `exiftool` image metadata usage with ImageIO/CoreGraphics.
- [x] Replace Python `ffprobe` media metadata usage with AVFoundation.
- [x] Remove the `/private/tmp` sandbox temporary exception and force app-owned temp directories, including Python `TMPDIR`.
- [x] Restrict Python input validation to Swift-created per-job workspaces rather than broad home-directory and temp roots.
- [x] Wrap delayed document reads/writes in security-scoped access or persist security-scoped bookmarks when user interaction can delay conversion.

### P0 - Apple Storage and User-Facing Abstraction
- [x] Validate iCloud Drive, Desktop/Documents-in-iCloud, external drives, network volumes, File Provider locations, and app sandbox container behavior.
- [x] Centralize all user-selected file reads, delayed reads, saves, bookmarks, pasteboard operations, Quick Action handoff, temp workspaces, and cleanup in concrete file/storage services.
- [x] Use security-scoped access/bookmarks when conversion can be delayed or handed off; do not rely on raw paths for app, extension, or queued conversion handoff.
- [x] Detect unavailable/evicted iCloud or File Provider files before conversion and show an action-oriented message without exposing implementation internals.
- [x] Add storage fixtures/manual release checks for local file, iCloud downloaded, iCloud evicted, File Provider, external volume, read-only source, and save-location denial.
- [x] Keep user-facing copy product-level: do not mention Python, Docling, pdfium, model package names, or other implementation toolkits outside licenses and explicit diagnostic previews.
- [x] Use neutral diagnostic component codes for runtime logs and support reports, with developer-only mappings in release docs.
- [x] Add a UI copy audit to release validation for shelf stages, errors, preferences, paywall, support reports, App Store text, and onboarding.

### P0 - App Store Metadata and Entitlements
- [x] Merge URL scheme and Services registration into the effective app `Info.plist`, not a copied resource plist.
- [x] Add `NSSpeechRecognitionUsageDescription` to the effective app `Info.plist` before any Speech framework authorization call.
- [x] Fix App Group identifiers to a registered `group.com.upmarket.app` style value across app and extension.
- [x] Redesign Quick Action handoff using App Group storage plus security-scoped bookmarks or copied files; do not trust arbitrary custom-URL file paths.
- [x] Reassess consumable document packs: avoid client-authoritative `UserDefaults` balances or move consumable accounting to a verifiable App Store/server-backed model.

### P0 - Observability, CI, and Release Validation
- [x] Fix CI to build and test `Upmarket/Upmarket.xcodeproj`.
- [x] Add CI/release checks for archive, entitlements, effective `Info.plist`, embedded Python imports, offline conversion smoke tests, and model-missing behavior.
- [x] Add local validation for the embedded runtime helper target and optional built-app readiness smoke.
- [x] Replace Swift service `print` diagnostics with structured `OSLog` categories, per-job correlation IDs, and privacy-redacted diagnostic bundles.
- [x] Add fault-injection tests for Python bridge setup failure, stalled conversion, temp cleanup, and huge input rejection.
- [x] Add first release memory-pressure safeguard: reject oversized input before workspace copy with an actionable “document too large” error.
- [x] Add deeper conversion-corpus fault tests for partial model download, password PDFs, corrupt files, and Python stderr handling.
- [x] Add deeper Vision/OCR safeguards: page/pixel limits, streaming page processing, and autorelease pools.

### P0 - Crash and Bug Reporting
- [x] Define a privacy-first support policy: no automatic telemetry, no document contents, no extracted text, no passwords, and no full local file paths in reports.
- [x] Add Apple-native crash triage process using TestFlight/App Store crash reports in Xcode Organizer, including ownership, severity labels, and release-blocking criteria.
- [x] Add `Help > Report a Problem...` flow that creates a user-approved email or support package rather than silently uploading diagnostics.
- [x] Add a redacted diagnostic bundle generator with app version, build number, macOS version, hardware class, locale, entitlement/plist sanity results, model manifest status, last conversion stage, error code, and correlation ID.
- [x] Add OSLog retrieval/export for recent Upmarket subsystem logs with privacy annotations; exclude document contents, extracted Markdown, passwords, and unredacted paths.
- [x] Add user-facing controls to preview, include, or omit diagnostics before sending a bug report.
- [x] Add GitHub/support issue templates for crashes, conversion failures, model download failures, StoreKit issues, and App Store review regressions.
- [x] Add incident runbook for crash spikes, Python helper crashes, corrupt model rollouts, broken feature flags, and StoreKit product failures.

### P0 - Release Engineering and Upstream Validation
- [x] Add PR CI checks for build, unit tests, effective `Info.plist`, entitlements, Python bundle imports, and offline smoke conversion.
- [x] Add release-candidate workflow for archive validation, signing/entitlements inspection, StoreKit checks, packaged app launch/import, and corpus smoke tests.
- [x] Add nightly upstream validation for BeeWare Python, Docling, MarkItDown, pypdfium2, Hugging Face Hub, Transformers, Torch/MLX, and Xcode SDK changes.
- [x] Introduce locked Python dependency management with current, candidate, and latest-upstream validation states.
- [x] Add scheduled upstream watch automation that reports candidate dependency drift without promotion.
- [x] Add upstream issue/patch intake labels in GitHub: watch, candidate, adopted, rejected, blocked, fork.
- [x] Require upstream candidates to link issue/PR/release URL, local reproduction or corpus case, user impact, security/privacy review, and rollback plan.
- [x] Require corpus fixture or benchmark coverage before adopting upstream conversion-quality changes.
- [x] Add a stored corpus quality baseline and release gate that blocks future releases when benchmark output fails or downgrades against baseline.
- [x] Add a document x conversion-pathway baseline ledger so every corpus file can be measured against every valid Markdown pathway, including unused/internal reference pathways.
- [x] Remove PyMuPDF/pymupdf4llm from release dependency locks and block AGPL/commercial-only PDF packages from the paid-app runtime unless a commercial-license ADR is approved.
- [x] Permit PyMuPDF only as an internal benchmark/reference pathway; promotion to a shipping path requires a commercial-license ADR and packaged-runtime validation.
- [x] Add PyMuPDF, Poppler, RapidOCR, and PaddleOCR as internal/reference benchmark pathways so future uplift can be measured before any licensing or packaging decision.
- [x] Mark PaddleOCR blocked/deprecated after the 2026-06-01 M4 Pro benchmark showed external model-download requirements, multiple 45-second document timeouts, and native stability risk.
- [x] Validate `python-ai-docling` with repo-local model cache, explicit model directory wiring, warm-runtime benchmarking, and fallback to fast conversion when model-backed handlers reject otherwise-supported files.
- [x] Publish release-candidate corpus pathway comparison artifacts for owner review before shipping.
- [x] Document each conversion pathway's CPU/GPU/Apple Neural Engine behavior and whether benchmark compute mode can be explicitly controlled.
- [x] Add a native PDFKit corpus benchmark and clean-room inspection plan for improving Apple-native PDF extraction without adopting GPL/incompatible PDF engines.
- [x] Document Vision/Core ML/CoreGraphics native inspection options for OCR, document structure, image classification, page quality, and OS-managed Apple silicon acceleration.
- [x] Add an availability-gated native document classifier that can recommend PDFKit, Vision OCR, or enhanced conversion without failing when Vision/Core ML are unavailable.
- [x] Add local Vision/NaturalLanguage-style candidate quality selection for permitted PDF paths using language confidence, coverage, structure, artifact penalties, duplication penalties, and image-text agreement.
- [x] Record forensic benchmark inventory: package versions, binary versions, corpus source commits, benchmark-only OCR/model cache artifacts, and cache roots.
- [x] Add a follow-on serial-vs-parallel processing benchmark using the same corpus/pathway matrix, including accuracy, wall time, failures, and system-load evidence before changing queue concurrency.
- [x] Require ADRs for local patches to upstream behavior, including removal condition and packaged-app validation.
- [x] Require fork/cherry-pick candidates to be temporary, upstream-linked, pinned to immutable commits or packaged artifacts, covered by corpus validation, and removable once upstream releases.
- [x] Add dependency audit workflow for exact pins, `pip check`, license generation, vulnerability review where practical, and undeclared runtime tool detection.
- [x] Extend the packaged runtime dependency gate to reject native extension ABI mismatches, after the 2026-06-02 Xcode helper smoke found CPython 3.13-tagged extensions inside the embedded Python 3.12 framework.
- [x] Add release docs: release policy, release checklist, and test matrix.
- [x] Add CI helper scripts for Xcode project validation, effective plist checks, entitlement checks, Python bundle validation, offline conversion, model validation, and corpus validation.

### P0 - Agent Task Tracking and Pipeline Hooks
- [x] Use `docs/release/AGENT_TASK_ORCHESTRATION.md` as the required workflow for multi-agent tasks.
- [x] Track implementation work with a validated P0 registry using objective, owner, scope, non-goals, acceptance criteria, release gate, and risk area.
- [x] Use `.github/ISSUE_TEMPLATE/agent-task.yml` for agent-owned work and `.github/ISSUE_TEMPLATE/crash-bug-report.yml` for failure reports.
- [x] Use `.github/PULL_REQUEST_TEMPLATE.md` for every PR, including release gate, validation, risk review, and agent handoff.
- [x] Define local hook scripts before wiring GitHub Actions: plist, entitlements, Python bundle, offline conversion, model validation, corpus validation, and archive checks.
- [x] Make every release hook runnable locally, nonzero on failure, and explicit about whether network is permitted.
- [x] Add GitHub label and issue sync automation for P0 task registry items.
- [x] Add generated repository/source/process documentation with a CI stale-docs gate.
- [x] Require the main Codex session to integrate multi-agent outputs and update the implementation plan when P0 scope changes.

## Verified Complete

### Core App
- [x] SwiftUI app shell, menu bar extra, shelf UI, and preferences window
- [x] File drop/open/save/copy/new flows
- [x] App phase state for idle, analysing, converting, result, and error
- [x] Password-protected PDF prompt path
- [x] Sandbox-friendly file copy to temp before Python conversion

### Conversion
- [x] Swift `ConversionRunner` routing by format and capability
- [x] Apple-native PDFKit fast path
- [x] Vision document extraction availability gate
- [x] Speech transcription service using Speech framework
- [x] Python bridge for Docling, markitdown, pdfium, image/media fallbacks
- [x] NaturalLanguage post-processing and metadata extraction
- [x] Writing Tools / Foundation Models adapters with graceful availability checks

### Monetisation
- [x] StoreKit 2 product loading, purchase, restore, and transaction listener
- [x] Three free conversions, Basic, Pro, and 5-doc pack product IDs
- [x] Pack credit tracking and upgrade nudges
- [x] StoreKit configuration wired into the shared Xcode scheme

### Models and Feature Gating
- [x] ModelManager download/check/delete/offload flow
- [x] On-demand model prompts instead of first-launch downloads
- [x] Device capability checks for Apple Silicon and OS features
- [x] Remote feature flags at `docs/public/flags.json`
- [x] Language quality warnings and AI gating

### App Store Technical
- [x] Bundle ID set to `com.upmarket.app`
- [x] `Upmarket.entitlements` wired via `CODE_SIGN_ENTITLEMENTS`
- [x] Privacy manifest present
- [x] App icon assets present through 1024 px
- [x] Open source license resource present

## Release Gates

### Gate A - Build and Packaging
- [x] Build cleanly with `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' build`
- [x] Build the x86_64 macOS slice on Apple Silicon with `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS,arch=x86_64' CODE_SIGNING_ALLOWED=NO build`
- [ ] Archive successfully in Xcode with the release team selected
- [x] Verify sandbox entitlements in the archived app
- [x] Confirm bundled Python runtime imports required modules from inside the app bundle
- [ ] Confirm app works after deleting downloaded models
- [x] Do not block v1.0 on physical Intel hardware validation. Do not claim Intel support beyond build compatibility/native-only positioning until actual Intel hardware evidence exists.

### Gate B - Conversion Reliability
- [x] Maintain a corpus benchmark covering the release formats. Current corpus manifest validates 185 documents across PDF, DOCX, PPTX, XLSX, HTML, image, audio, CSV, XML, WebVTT, video, and AsciiDoc.
- [ ] For each corpus document, record expected status: success, unsupported, password required, or degraded output
- [x] Bootstrap `docs/release/corpus_pathway_baseline.json` with per-document scores for current report-backed pathways. `scripts/ci/validate_corpus_pathways.py` now passes across the eight current report JSON files, including the split packaged MarkItDown audio report and native ImageIO/AVFoundation metadata reports. Every corpus document now has at least one current report-backed pathway baseline row; native Vision OCR and Speech transcription still need app/Xcode permission-runtime evidence before release.
- [x] Run fast path with no downloaded models. Evidence exists in `reports/corpus-python-fast-pdfium.json`, `reports/corpus-python-fast-markitdown.json`, and `reports/corpus-swift-pdfkit.json`; the password-protected PDF is now recorded as expected-blocked in the per-document pathway baseline.
- [x] Run enhanced path after model/runtime setup where supported. Evidence exists in `reports/corpus-python-enhanced-docling.json`; the password-protected PDF is now recorded as expected-blocked in the per-document pathway baseline.
- [ ] Run AI path after model download where supported. Current valid Granite AI evidence is `reports/corpus-granite-docling-scanned-or-unknown.json`; it is baselined but not release-passing because 4 rows are environment-blocked by Metal/runtime availability in the benchmark context and need a targeted GUI/Metal validation pass before release.
- [x] Run batch conversion from the shelf queue across at least 5 mixed accepted inputs, including one failure, one cancellation, and one retry. Covered by `ConversionQueueTests.testBatchShelfQueueFiveMixedInputsWithFailureCancellationAndRetry`; the 2026-06-02 Xcode rerun passed all 20 selected `ConversionQueueTests`.
- [x] Defer physical Intel corpus validation from v1.0 release blocking. Current release positioning must keep Intel claims limited to build compatibility/native-only behavior until physical Intel evidence exists.
- [ ] Verify temp files are cleaned after success, failure, cancellation, and app quit. Xcode now covers app-owned workspace cleanup after native success, recoverable failure, input-copy failure, advanced-runtime cancellation, stale startup cleanup, and the app-termination cleanup hook; full GUI app quit/relaunch cleanup still needs release evidence.
- [ ] Verify conversion result state always resolves to result, actionable error, password prompt, or explicit in-progress state

### Gate C - Stability and Diagnostics
- [x] Replace `print` diagnostics in Swift services with `OSLog.Logger`
- [x] Add OSLog categories: conversion, pythonBridge, modelDownload, storeKit, fileAccess, featureFlags
- [x] Add signposts around conversion stages: copyToTemp, analyse, nativeExtract, pythonConvert, postProcess, saveOutput
- [x] Add conversion liveness monitor based on progress/heartbeat updates, not fixed elapsed duration
- [x] Surface stalled conversion state with "still working" vs "no progress detected" messaging
- [x] Add memory pressure handling using Apple-native process/system signals where practical
- [ ] Run Instruments: Allocations, Leaks, Time Profiler, Main Thread Checker. Owner interpretation is recorded in `docs/release/GATE_B_C_VALIDATION.md` and checked by `scripts/ci/validate_gate_c_instruments.py`; current Upmarket-targeted Allocations, Time Profiler, and Main Thread Checker launch evidence are usable, while Leaks still needs release-quality evidence.
- [x] Run Thread Sanitizer on conversion, model download, and StoreKit flows. Focused TSan run passed on 2026-06-02 for `ConversionQueueTests`, `ModelManagerTests`, `StoreAccountingServiceTests`, and `PackCreditLedgerTests`.
- [x] Define Xcode Organizer crash triage process for TestFlight/App Store diagnostics
- [ ] Verify TestFlight/App Store crash diagnostics appear in Xcode Organizer

### Gate D - StoreKit and App Store
- [ ] Register bundle ID `com.upmarket.app` in Apple Developer/App Store Connect
- [ ] Set release Team ID in Xcode signing settings
- [ ] Register App Store app record: name, category, age rating, pricing
- [ ] Create App Store Connect IAP products:
  - [ ] `com.upmarket.app.basic` - $4.99
  - [ ] `com.upmarket.app.pro` - $9.99
  - [ ] `com.upmarket.app.doc_pack` - $0.99
- [ ] Test purchases, pending purchases, restore, refunds/revocations, and interrupted network in StoreKit testing
- [ ] Test StoreKit sandbox with App Store Connect products before submission

### Gate E - Legal, Privacy, and Listing
- [x] Finalize privacy policy draft at `docs/public/privacy.md`
- [ ] Host privacy policy at the public URL
- [ ] Use Apple's standard EULA with no custom terms
- [ ] Verify App Privacy answers match actual data collection: no analytics, no document upload, local processing
- [ ] Link privacy policy and terms in Preferences/About and App Store Connect
- [ ] Finalize app description, subtitle, keywords, support URL, and marketing URL
- [ ] Capture 5 App Store screenshots at required sizes

## Stability Workstream

This is a launch requirement, not post-launch polish.

### Conversion Liveness
- [ ] Define stage enum: queued, copying, analysing, extracting, python, postProcessing, saving, complete, failed
- [ ] Emit stage updates from Swift paths and Python bridge boundaries
- [ ] Add Python progress callback or progress file for long Docling/model operations
- [x] Track last progress heartbeat and current stage in `ConversionQueue`
- [ ] If no progress is observed, keep the job running but show a recoverable stalled-state UI with cancel/retry options
- [ ] Log stage, file type, file size, pipeline, OS version, and failure class without logging file contents

### Error Taxonomy
- [ ] Unsupported format
- [ ] Password required
- [ ] File inaccessible / sandbox denied
- [x] File too large or memory pressure
- [ ] Model unavailable / download required
- [ ] Model download failed
- [ ] Python bridge import/runtime failure
- [ ] Conversion made no progress
- [ ] Conversion failed with partial output available

### Native Test Coverage
- [x] `ConversionRunner` routing and `ConversionQueue` state transitions
- [x] x86_64 selected test run on Apple Silicon passes queue and programmatic authorization coverage; `ModelManagerTests.testDownloadProgressUpdatesBeforeCompletion` currently fails under x86_64 because Pro AI download is correctly blocked when Apple Silicon support is unavailable.
- [ ] PDF password path
- [x] Python bridge success/failure parsing
- [ ] Liveness monitor state transitions
- [ ] ModelManager check/download/delete error handling
- [ ] StoreManager product loading, entitlement refresh, pack credit consumption, restore
  - [x] Pack credits are derived from a verified transaction/debit ledger instead of a `UserDefaults` balance.
- [ ] XCUITest for drop zone, conversion result, paywall, preferences, and model download prompt

## Product Workstream

### v1.0 Must-Haves
- [ ] Friendly categorized errors using the error taxonomy above
- [ ] Batch conversion queue UX through the shelf: multiple accepted inputs must enqueue visibly, run serially, show per-job progress/result/error/cancellation, and keep copy/save actions obvious for each finished job.
- [ ] Preferences model setup: users can check and download Enhanced/AI models before converting a complex document, with capability, disk, and availability status shown before any download.
- [ ] Apple-native-only extraction remains internal routing/fallback behavior for v1.0; do not expose an engine-selection mode in normal UI.
- [ ] Preferences/About links to licenses, privacy policy, support, and version
- [ ] Dark mode pass for drop zone, shelf, output, paywall, and preferences
- [ ] macOS compatibility pass on 13.3, 14.x, 15.x, and current beta where available
- [ ] GitHub Pages enabled for `/docs/public`
- [ ] Verify `https://0x687931.github.io/upmarket/flags.json`

### v1.1 Candidates
- [ ] Rendered Markdown preview toggle
- [ ] Share button using macOS share sheet
- [ ] Conversion history
- [ ] Output format options: Markdown / plain text
- [ ] OCR toggle in drop zone
- [ ] First-launch onboarding

### P2 - UX/HIG Audit Findings
- [ ] Remove automatic paywall display at tour completion; let users experience a conversion before purchase prompts.
- [ ] Make shelf control hit targets at least 44x44 pt, with 48x48 preferred for pointer and accessibility comfort.
- [ ] Improve shelf discoverability with visible labels in expanded state and accessibility labels/hints for icon-only controls.
- [ ] Surface trial state at decision points: shelf, menu bar, paywall, and conversion-complete moments.
- [ ] Adapt paywall headline and actions to context: full trial, 1 conversion remaining, trial expired, AI upgrade, or pack upsell.
- [ ] Add a low-pressure "Continue Trial" or "Not Now" action when free conversions remain.
- [ ] Replace disabled priced purchase buttons during product loading with explicit "Loading purchase options" CTAs and recoverable retry messaging.
- [ ] Expand menu bar dropdown actions to include Add Document, Upgrade/Manage License, and Open Last Result when available.
- [ ] Rewrite onboarding copy to describe actions, not symbols; use "Choose Add Files" instead of "Tap +".
- [ ] Add Preferences controls for shelf position, auto-hide behavior, and whether the shelf appears only during drag/drop workflows.
- [ ] Ensure transient onboarding/paywall panels support expected dismissal behavior, including Escape where appropriate.
- [ ] Keep the idle menu bar icon template-like and reserve accent color/animation for meaningful status changes.

### Localisation
- [x] Localized string files exist for English, German, French, Japanese, Spanish, Italian, Portuguese, Korean, and Chinese
- [ ] Audit English baseline for final v1.0 copy
- [ ] Validate translations for truncation and tone
- [ ] Translate App Store listing per launch locale

## Release Milestones

| Milestone | Exit Criteria |
|---|---|
| M0 - P0 Audit Remediation | Every P0 Audit Blocker above is resolved or explicitly removed from v1.0 scope |
| M1 - Stability Baseline | Gates A, B, and C pass on local machine |
| M2 - App Store Ready | Gates D and E pass; TestFlight build uploaded |
| M3 - v1.0 Launch | Internal beta signed off; external beta issues triaged; listing complete |
| M4 - v1.1 | Post-launch candidates prioritized from user feedback |

## Validation Commands

```bash
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' build
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' test -only-testing:UpmarketTests
./scripts/update_dependencies.sh --check-only
./scripts/generate_licenses.sh
```

Manual validation remains required for Xcode Archive, App Store Connect setup, StoreKit sandbox, privacy answers, screenshots, TestFlight, and UI automation unless the task explicitly changes UI behavior.

## Open Questions

- [ ] Domain: `upmarket.app` vs `upmarketapp.com`
- [ ] Landing page before App Store submission or after TestFlight
- [x] Intel support phrasing: do not block v1.0 on physical Intel validation; current evidence supports x86_64 build compatibility and native-only Basic positioning, while Python-backed Enhanced/AI remains Apple Silicon gated until physical Intel evidence exists.
