# Gate B/C Validation Evidence

Last updated: 2026-06-02

## Gate B - Corpus Benchmark

The release corpus is not a new 20-document smoke set; the current benchmark manifest is the larger source of truth. `python3 scripts/ci/validate_corpus.py` validates 185 documents across PDF, DOCX, PPTX, XLSX, HTML, image, audio, CSV, XML, WebVTT, video, and AsciiDoc.

Current pathway artifacts:

| Report | Pipeline | Documents | Overall | Unexpected failed | Expected blocked | Env blocked | Release status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `reports/corpus-python-fast-pdfium.json` | fast PDF | 60 | 80.1% | 0 | 1 | 0 | Evidence only |
| `reports/corpus-python-fast-markitdown.json` | fast non-PDF | 111 | 83.8% | 0 | 0 | 0 | Evidence only |
| `reports/corpus-python-fast-markitdown-audio.json` | fast audio via packaged MarkItDown | 8 | 91.2% | 0 | 0 | 0 | Evidence only |
| `reports/corpus-swift-pdfkit.json` | native PDF | 60 | 83.2% | 0 | 1 | 0 | Evidence only |
| `reports/corpus-swift-imageio-metadata.json` | native image metadata | 15 | 65.0% | 0 | 0 | 0 | Evidence only |
| `reports/corpus-swift-avfoundation-metadata.json` | native media metadata | 6 | 85.0% | 0 | 0 | 0 | Evidence only |
| `reports/corpus-python-enhanced-docling.json` | enhanced | 171 | 83.3% | 0 | 1 | 0 | Evidence only |
| `reports/corpus-granite-docling-scanned-or-unknown.json` | Granite AI image/PDF bucket | 24 | 65.0% | 0 | 0 | 4 | Baselined, not release-passing |

`reports/gate-b-corpus-pathway-comparison.md` compares these pathways. `scripts/ci/validate_corpus_pathways.py` accepts repeated `--results` files so split pathway reports can be validated together for coverage and release exclusions. `docs/release/corpus_pathway_baseline.json` is now populated from the current report-backed pathways. Password-protected PDFs are recorded as `expected_blocked`, and Granite AI Metal/runtime availability failures are recorded as `environment_blocked`, instead of converter quality failures. The packaged MarkItDown audio report covers MP3/M4A/WAV capability separately from FLAC/video capability; the native AVFoundation metadata report covers the remaining FLAC/video fixtures. The native ImageIO report is intentionally low-scoring because metadata Markdown is not OCR/content extraction.

`scripts/ci/summarize_corpus_pathway_reports.py` normalizes older and newer report JSON before rendering the comparison artifact, so expected password blocks and environment-blocked Metal rows do not inflate the unexpected-failure count.

The current report-backed pathway baseline validates with:

```sh
python3 scripts/ci/validate_corpus_pathways.py \
  --results reports/corpus-python-fast-pdfium.json \
  --results reports/corpus-python-fast-markitdown.json \
  --results reports/corpus-python-fast-markitdown-audio.json \
  --results reports/corpus-python-enhanced-docling.json \
  --results reports/corpus-swift-pdfkit.json \
  --results reports/corpus-granite-docling-scanned-or-unknown.json \
  --results reports/corpus-swift-imageio-metadata.json \
  --results reports/corpus-swift-avfoundation-metadata.json
```

Per-document expected status is recorded in `docs/release/corpus_expected_status.json` and validates with `scripts/ci/validate_corpus_expected_status.py`. Current coverage is all 185 manifest documents: 161 success, 23 degraded output, 1 password required, and 0 unsupported.

Gate B is not fully release-passing yet. Remaining release blockers are full GUI app quit/relaunch temp cleanup validation, native Vision OCR and Speech transcription permission/runtime evidence, and a targeted GUI/Metal Granite AI validation pass. Physical Intel validation is not a v1.0 blocker; Intel-facing copy must stay limited to build compatibility/native-only positioning until actual Intel hardware evidence exists. Every corpus document now has at least one current pathway-result row.

`NativeMetadataExtractorTests.testCorpusMediaMetadataUsesNativeAVFoundation` now exercises AVFoundation metadata extraction against representative corpus audio/video fixtures: FLAC, MP4, and QuickTime/MOV. This is native media evidence, not a full audio/video pathway baseline; Speech transcription still needs app permission/runtime evidence.

### Batch Shelf Queue

Batch shelf queue behavior is now covered through Xcode by `ConversionQueueTests.testBatchShelfQueueFiveMixedInputsWithFailureCancellationAndRetry`. The test queues five accepted inputs across PDF, DOCX, HTML, PPTX, and XLSX, then verifies one success before a failure, one explicit failure, one cancellation, one later success, and one retry that creates a new successful job without overlapping the serial queue.

Current evidence:

```sh
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:UpmarketTests/ConversionQueueTests
```

The 2026-06-02 rerun passed 20 selected `ConversionQueueTests` with 0 failures.

### Workspace Cleanup

`ConversionRunner` owns app-workspace cleanup through one `defer` path after the source is copied. Xcode now covers cleanup after native success, recoverable failure, and input-copy failure:

```sh
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:UpmarketTests/ConversionQueueTests
```

The 2026-06-02 rerun passed 20 selected `ConversionQueueTests` with 0 failures. App startup stale-workspace cleanup remains covered by `DiagnosticsTests.testStaleWorkspaceCleanupRemovesStartupLeftovers`. `PythonBridgeTests.testRunnerCleansWorkspaceWhenAdvancedConversionIsCancelled` now cancels a real `ConversionRunner` task while it is inside the advanced-runtime boundary and verifies the app-owned workspace list returns to its pre-run state. `DiagnosticsTests.testAppDelegateTerminationCleansStaleWorkspaces` covers the app-termination cleanup hook. Remaining release evidence needed: cleanup after full GUI app quit/relaunch.

### Granite AI Metal Root Cause

The 4 non-scored Granite AI rows in `reports/corpus-granite-docling-scanned-or-unknown.json` are not proven document-quality failures. They are:

| Document | File | Recorded error |
| --- | --- | --- |
| `docling_ModalNet-32` | `tests/data/latex/1706.03762/Figures/ModalNet-32.png` | Upmarket AI couldn't run on this Mac. Check model download and device compatibility. |
| `docling_230927_effective_sizes` | `tests/data/latex/2310.06825/images/230927_effective_sizes.png` | Upmarket AI couldn't run on this Mac. Check model download and device compatibility. |
| `docling_llama_vs_mistral_example` | `tests/data/latex/2310.06825/images/llama_vs_mistral_example.png` | Upmarket AI couldn't run on this Mac. Check model download and device compatibility. |
| `docling_2206.01062_tiff` | `tests/data/tiff/2206.01062.tif` | Upmarket AI couldn't run on this Mac. Check model download and device compatibility. |

The current app-side availability gate was validated through Xcode on 2026-06-02:

```sh
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:UpmarketTests/DeviceCapabilityTests
```

Xcode selected the arm64 macOS destination and `DeviceCapabilityTests.testUpmarketAIAvailabilityRequiresAppleSiliconAndMetalDevice` passed. `ModelManagerTests` also passed, so the Swift gate can see Apple Silicon plus a native Metal device in the app test runtime. The remaining Granite AI release gap is therefore a full conversion pass in a GUI/Metal-capable app or benchmark context, not proof that these four documents are bad.

The 2026-06-02 packaged-helper smoke also exposed a real package-gate defect before the Metal check: the bundled Pillow native extensions were tagged for CPython 3.13 inside the embedded Python 3.12 framework. `scripts/build_python_env.sh` now refuses to build the bundled runtime with a non-3.12 interpreter, and `scripts/ci/verify_python_bundle.sh` now fails on native extension ABI mismatches under `site-packages`. The package dependency gate now passes:

```sh
scripts/ci/verify_python_bundle.sh
```

After that package fix, the targeted Xcode Granite smoke reaches the app-packaged helper and exits through the explicit `runtime.helper.runtime-unavailable` path because the current test session cannot access this Mac's graphics processor:

```sh
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:UpmarketTests/PythonBridgeTests/testGraniteAIPreviouslyBlockedCorpusFixturesRouteThroughHelperWhenModelInstalled
```

The 2026-06-02 rerun records this as 1 skipped test with 0 failures so the normal unit suite remains usable on machines or Xcode sessions without helper-visible Metal. That keeps Granite AI release validation open, but it is no longer the same packaging failure.

## Gate C - Stability Diagnostics

Existing Instruments trace bundles are under `reports/gate-c-stability/` for Allocations, Leaks, Time Profiler, and related captures. Current owner interpretation:

| Trace | Target | Duration | Interpretation |
| --- | --- | ---: | --- |
| `allocations.trace` | Upmarket | 105.140s | Usable Allocations capture; ended by time-limit SIGKILL. |
| `allocations-binary.trace` | Upmarket | 10.811s | Usable Allocations capture; ended by time-limit SIGKILL. |
| `time-profiler.trace` | Upmarket | 10.740s | Usable Time Profiler capture; ended by time-limit SIGKILL. |
| `time-profiler-all-processes.trace` | all processes | 5.696s | Usable Time Profiler inventory, but not Upmarket-targeted enough for release pass/fail. |
| `leaks.trace` | Upmarket | 10.824s | Usable Leaks capture; ended by time-limit SIGKILL. |
| `leaks-all-processes.trace` | all processes | 0.000s | Not usable release evidence. |
| `allocations-all-processes.trace` | all processes | 0.000s | Not usable release evidence. |

This interpretation is checked with:

```sh
scripts/ci/validate_gate_c_instruments.py
```

Gate C Instruments now has targeted Allocations, Leaks, and Time Profiler evidence. The Leaks capture required enabling Developer Mode, signing the actual LaunchServices-selected debug app with `get-task-allow`, and launching the exact signed executable path for `xctrace`.

Main Thread Checker launch validation covers the built app with Xcode's checker runtime injected:

```sh
scripts/ci/validate_main_thread_checker.py \
  --app-path /Users/am/Library/Developer/Xcode/DerivedData/Upmarket-ghnrfzrcpacwzsfimfknmtpxhmqj/Build/Products/Debug/Upmarket.app \
  --duration 10
```

The 2026-06-02 rerun passed with no launch-time Main Thread Checker violations. The first sandboxed attempt failed before app launch because `xctrace` could not write its Instruments cache; the accepted run was executed outside the sandbox.

Thread Sanitizer validation covers the focused conversion, model, StoreKit accounting, and pack ledger unit flows with:

```sh
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -enableThreadSanitizer YES test -only-testing:UpmarketTests/ConversionQueueTests -only-testing:UpmarketTests/ModelManagerTests -only-testing:UpmarketTests/StoreAccountingServiceTests -only-testing:UpmarketTests/PackCreditLedgerTests
```

The first run found test-side off-main reads in `ModelManagerTests`; the polling helper now evaluates model state on the main actor. The 2026-06-02 rerun passed 34 selected tests with 0 failures and no Thread Sanitizer findings.

Xcode Organizer crash diagnostics cannot be verified locally without a TestFlight/App Store distributed build that has produced a crash report. Keep that gate open until the release owner verifies crash visibility in Organizer.
