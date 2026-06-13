# Test Matrix

This matrix defines the minimum validation surface. Add focused tests when a change touches a new interface, data contract, entitlement, package, or conversion pathway.

| Area | Scope | Command Or Evidence | Frequency | Blocks Release |
| --- | --- | --- | --- | --- |
| Xcode toolchain | Xcode 26+ selected; GitHub build/archive lanes use `macos-26` and `DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer` | `scripts/ci/verify_xcode_project.sh`; workflow `Show Xcode version` step | Every PR and release candidate | Yes |
| Fast PR gate | Policy checks, unsigned build, effective plist, and unit tests | `scripts/ci/gate.sh quick` | Every PR | Yes |
| Build runtime preparation | Ignored `Python.xcframework` exists so the Xcode target can compile; CI rebuilds only when cache is missing or stale | `scripts/ci/ensure_python_runtime.sh` | Every PR in CI; local only when missing | Yes |
| Xcode project | Project opens, targets resolve, helper target is wired | `scripts/ci/verify_xcode_project.sh` | Every PR through quick gate | Yes |
| Architecture boundaries | Minimal monolith, Python behind helper, no restored legacy service, no hidden launch window workarounds | `scripts/ci/validate_architecture_boundaries.py` | Every PR through quick gate | Yes |
| Philosophy remediation | Primary conversion surface, rejected input visibility, supported type parity, queue-owned UI state, model setup states, support redaction/context, and programmatic authorization stay covered | `scripts/ci/validate_release_regression_guards.py`; `UpmarketUITests/UpmarketUITests.swift`; `UpmarketTests/ConversionQueueTests.swift`; `UpmarketTests/StorageAccessTests.swift`; `UpmarketTests/ModelManagerTests.swift`; `UpmarketTests/SupportReporterTests.swift` | Every PR through quick gate | Yes |
| User-facing copy | No internal toolkit/package names in normal UI copy | `scripts/ci/validate_user_facing_copy.py` | Every PR through quick gate | Yes |
| Generated docs | Source map and automation docs are current | `scripts/docs/generate_repo_docs.py --check` | Every PR through quick gate | Yes |
| Source entitlements | App/helper entitlement policy matches App Store intent | `scripts/ci/verify_entitlements.sh` | Every PR through quick gate | Yes |
| Signed entitlements | Signed archive has embedded app/helper entitlements | `UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS=1 scripts/ci/verify_entitlements.sh /path/to/Upmarket.app` | Release candidate | Yes |
| Build | App, Quick Action, runtime helper compile | `scripts/ci/gate.sh quick` or `xcodebuild build ... CODE_SIGNING_ALLOWED=NO` | Every PR | Yes |
| Unit tests | Domain, services, StoreKit accounting, diagnostics, helper, native extraction | `scripts/ci/gate.sh quick` or `xcodebuild test ... -only-testing:UpmarketTests` | Every PR | Yes |
| UI tests | Apple XCTest/XCUIAutomation coverage for launch, shelf, paywall, preferences, appearance-sensitive flows, and release-facing workflows | `scripts/ci/gate.sh ui`; `scripts/ci/gate.sh major`; `.github/workflows/ui-automation.yml`; `.github/workflows/release-candidate.yml` | UI-sensitive PRs, manual runs, major/release candidates, and explicit UI changes | Yes |
| Swift Testing adoption | New pure Swift unit/integration tests may use Swift Testing; existing XCTest files migrate only when touched for meaningful behavior changes | Same `xcodebuild test ... -only-testing:UpmarketTests` path; do not mix Swift Testing and XCTest APIs in one file | New focused service/domain tests | Yes when touched |
| Runtime package | Embedded runtime imports first-party bridge, exact installed dependency pins, native extension ABI tags, `pip check` | `scripts/ci/gate.sh runtime`; `scripts/ci/validate_installed_pins.py` | Runtime/dependency/package changes and release candidates | Yes |
| Apple bundle preflight | Foundation `Bundle.preflight()` can load-check embedded executable bundles before runtime import smoke | `scripts/ci/verify_release_app.sh /path/to/Upmarket.app` | Runtime/package changes and RC | Yes |
| Python bridge security | First-party bridge rejects unsafe archives, extension/content mismatches, pathological images/PDFs, subprocess launch, and conversion-time network access | `scripts/ci/verify_release_app.sh /path/to/Upmarket.app`; direct form: `PYTHONPATH=<bundled site-packages> python3.12 scripts/ci/test_archive_security.py` | Python bridge, runtime, dependency, package changes and RC | Yes |
| App package | Effective plist, entitlements, Apple bundle preflight, runtime imports, helper, offline smoke | `scripts/ci/gate.sh runtime` or `scripts/ci/verify_release_app.sh /path/to/Upmarket.app` | Runtime/package changes and RC | Yes |
| First-party model downloads | Staged model asset manifests match the app catalog and TestFlight/App Store archives point at Apple-hosted HTTPS model manifests | `scripts/build/stage_first_party_model_assets.py`; `UPMARKET_REQUIRE_MODEL_MANIFEST_BASE_URL=1 scripts/ci/verify_release_app.sh /path/to/Upmarket.app` | Model/runtime changes and RC | Yes |
| Model states | Missing, partial, corrupt, stale, and unexpected model dirs fail safely; release gate repair mode manifests pinned legacy caches and quarantines unusable local caches | `scripts/ci/gate.sh minor`; `scripts/ci/validate_models.py`; `scripts/ci/test_model_faults.py` | Model/runtime changes and RC | Yes |
| Corpus manifest | Corpus files and ground truth are present and well formed | `scripts/ci/gate.sh minor` or `scripts/ci/validate_corpus.py` | Conversion/corpus changes and RC | Yes |
| Corpus baseline | Current benchmark output does not regress stored baseline | `scripts/ci/validate_corpus_baseline.py --results <json>` | Release candidate and conversion changes | Yes |
| Pathway baseline | Each valid pathway is covered and compared per document | `scripts/ci/validate_corpus_pathways.py --results <json>` | Release candidate and pathway changes | Yes |
| Benchmark comparison | Human-readable file x pathway score table | `scripts/ci/summarize_corpus_pathway_reports.py reports/corpus-*.json` | Release candidate | Yes |
| Concurrency benchmark | Serial vs parallel accuracy, failures, wall time, load evidence | `scripts/benchmark_concurrency.py --pathway <id>` | Queue/concurrency changes | Yes for concurrency changes |
| Storage access | iCloud/local/security-scoped file behavior | `docs/release/STORAGE_VALIDATION.md` evidence and focused tests | Storage changes and RC | Yes |
| Diagnostics | Redacted bug report, OSLog, crash/support runbook | `UpmarketTests/DiagnosticsTests.swift`; `UpmarketTests/SupportReporterTests.swift` | Every PR touching diagnostics | Yes |
| StoreKit | Product loading, purchases, pack ledger, restore, pending transaction | StoreKit sandbox/manual evidence plus unit tests | Store changes and RC | Yes |
| TestFlight internal beta | Signed archive uploaded to App Store Connect, internal group assigned, What to Test populated, feedback/crash triage checked | App Store Connect TestFlight build page, tester feedback, and Xcode Organizer evidence | Every internal beta candidate | Yes for beta |
| TestFlight external beta | Internal beta issues resolved, external group ready, TestFlight App Review information complete, sandbox IAP exercised | App Store Connect external group approval plus sandbox purchase evidence | External beta candidate | Yes for external beta |
| App Store metadata | Privacy, licenses, support, screenshots, listing, age rating | App Store Connect review checklist | Release candidate | Yes |

## Touched-Code Rule

Do not run every expensive test for every backend-only change. Run the narrowest reliable gate for the touched interface, then broaden to the full release-candidate matrix before shipping.

## Expected Blocked Results

A corpus document that needs missing user input, such as a password-protected PDF without a supplied password, is `expected_blocked`, not `failed`. It still appears in benchmark output, but it must not reduce quality averages or count against failed-document limits.

## Automation Boundary

UI automation runs in the dedicated `.github/workflows/ui-automation.yml` lane for UI-sensitive changes and in release-candidate CI. It stays out of the normal fast PR gate so backend-only changes keep quick feedback. Unit, package, copy, corpus, and model checks should remain safe for normal PR/local runs.

## Apple Test Framework Policy

Use Swift Testing for new pure Swift unit and integration coverage where its assertions, async support, and parameterized tests make the test smaller or clearer. Keep XCTest for UI automation, performance measurement, and existing test files that are not otherwise being changed. Apple supports Swift Testing and XCTest in the same test bundle, but individual files should use one framework at a time.

Upmarket's preflight policy has two layers. Runtime input preflight stays in app code and uses native Apple APIs where practical before heavyweight conversion. Release-package preflight belongs in CI and uses Foundation bundle preflight before Python/runtime import smoke so load/link failures are caught before a candidate reaches TestFlight.

## Python Test Policy

Yes, Upmarket needs Python tests where Python is part of the shipped conversion boundary. Keep them focused on first-party bridge behavior, package integrity, sandbox behavior, model state faults, dependency pins, and offline conversion smoke. Do not run or edit the vendored upstream Docling pytest suite as Upmarket's normal Python test surface; those files are corpus/reference material unless the task is explicitly about upstream corpus validation.

Run Python bridge tests with the bundled Python minor version and bundled `site-packages`, not whichever `python3` happens to be on the machine. `scripts/ci/verify_release_app.sh` owns that package-level test path so release candidates exercise the same bridge files and native wheels that TestFlight users receive.

## TestFlight Policy

Use TestFlight as a release-candidate validation lane, not a substitute for local gates. A build is eligible for beta only after `scripts/ci/gate.sh minor` passes, signed entitlements are verified on the archived app, and StoreKit/App Store Connect metadata needed for beta review is complete.

Start with one internal group for owner/dev validation. Move to external testing only after internal feedback, Xcode Organizer crash diagnostics, and sandbox purchase paths have been reviewed. External groups require TestFlight App Review, so every external beta issue should have an owner, reproduction note, and release decision before widening distribution.
