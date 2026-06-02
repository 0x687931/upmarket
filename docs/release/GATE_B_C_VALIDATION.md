# Gate B/C Validation Evidence

Last updated: 2026-06-02

## Gate B - Corpus Benchmark

The release corpus is not a new 20-document smoke set; the current benchmark manifest is the larger source of truth. `python3 scripts/ci/validate_corpus.py` validates 185 documents across PDF, DOCX, PPTX, XLSX, HTML, image, audio, CSV, XML, WebVTT, video, and AsciiDoc.

Current pathway artifacts:

| Report | Pipeline | Documents | Overall | Failed | Release status |
| --- | --- | ---: | ---: | ---: | --- |
| `reports/corpus-python-fast-pdfium.json` | fast PDF | 60 | 80.1% | 1 | Evidence only |
| `reports/corpus-python-fast-markitdown.json` | fast non-PDF | 111 | 83.8% | 0 | Evidence only |
| `reports/corpus-swift-pdfkit.json` | native PDF | 60 | 83.2% | 1 | Evidence only |
| `reports/corpus-python-enhanced-docling.json` | enhanced | 171 | 83.3% | 1 | Evidence only |
| `reports/corpus-python-ai-docling.json` | AI | 171 | 83.3% | 1 | Evidence only |

`reports/gate-b-corpus-pathway-comparison.md` compares these pathways. `scripts/ci/validate_corpus_pathways.py` accepts repeated `--results` files so split pathway reports can be validated together for coverage and release exclusions.

Gate B is not release-passing yet. Remaining release blockers are expected-status annotation, per-document pathway baselines in `docs/release/corpus_pathway_baseline.json`, batch shelf validation, physical Intel validation, temp cleanup validation, and resolving the failed/low-scoring pathway reports.

## Gate C - Stability Diagnostics

Existing Instruments trace bundles are under `reports/gate-c-stability/` for Allocations, Leaks, Time Profiler, and related captures. These are evidence only until an owner records pass/fail interpretation, notable leaks/hotspots, and any follow-up issues.

Thread Sanitizer validation covers the focused conversion, model, StoreKit accounting, and pack ledger unit flows with:

```sh
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -enableThreadSanitizer YES test -only-testing:UpmarketTests/ConversionQueueTests -only-testing:UpmarketTests/ModelManagerTests -only-testing:UpmarketTests/StoreAccountingServiceTests -only-testing:UpmarketTests/PackCreditLedgerTests
```

The first run found test-side off-main reads in `ModelManagerTests`; the polling helper now evaluates model state on the main actor. The 2026-06-02 rerun passed 34 selected tests with 0 failures and no Thread Sanitizer findings.

Xcode Organizer crash diagnostics cannot be verified locally without a TestFlight/App Store distributed build that has produced a crash report. Keep that gate open until the release owner verifies crash visibility in Organizer.
