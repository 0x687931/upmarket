# Test Matrix

This matrix defines the minimum validation surface. Add focused tests when a change touches a new interface, data contract, entitlement, package, or conversion pathway.

| Area | Scope | Command Or Evidence | Frequency | Blocks Release |
| --- | --- | --- | --- | --- |
| Xcode project | Project opens, targets resolve, helper target is wired | `scripts/ci/verify_xcode_project.sh` | Every PR | Yes |
| Architecture boundaries | Minimal monolith, Python behind helper, no restored legacy service, no hidden launch window workarounds | `scripts/ci/validate_architecture_boundaries.py` | Every PR | Yes |
| Philosophy remediation | Primary conversion surface, rejected input visibility, supported type parity, queue-owned UI state, model setup states, support redaction/context, and programmatic authorization stay covered | `scripts/ci/validate_release_regression_guards.py`; `UpmarketUITests/UpmarketUITests.swift`; `UpmarketTests/ConversionQueueTests.swift`; `UpmarketTests/StorageAccessTests.swift`; `UpmarketTests/ModelManagerTests.swift`; `UpmarketTests/SupportReporterTests.swift`; `UpmarketTests/ProgrammaticConversionAuthorizationTests.swift` | Every PR | Yes |
| User-facing copy | No internal toolkit/package names in normal UI copy | `scripts/ci/validate_user_facing_copy.py` | Every PR | Yes |
| Generated docs | Source map and automation docs are current | `scripts/docs/generate_repo_docs.py --check` | Every PR | Yes |
| Source entitlements | App/helper entitlement policy matches App Store intent | `scripts/ci/verify_entitlements.sh` | Every PR | Yes |
| Signed entitlements | Signed archive has embedded app/helper entitlements | `UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS=1 scripts/ci/verify_entitlements.sh /path/to/Upmarket.app` | Release candidate | Yes |
| Build | App, Quick Action, runtime helper compile | `xcodebuild build ... CODE_SIGNING_ALLOWED=NO` | Every PR | Yes |
| Unit tests | Domain, services, StoreKit accounting, diagnostics, helper, native extraction | `xcodebuild test ... -only-testing:UpmarketTests` | Every PR | Yes |
| UI tests | Launch, shelf, paywall, preferences, appearance-sensitive flows | `xcodebuild test ... -only-testing:UpmarketUITests` | Release candidate only | Yes |
| Runtime package | Embedded runtime imports first-party bridge, pinned deps, `pip check` | `scripts/ci/verify_python_bundle.sh` | Every PR | Yes |
| App package | Effective plist, entitlements, runtime imports, helper, offline smoke | `scripts/ci/verify_release_app.sh /path/to/Upmarket.app` | Every PR and RC | Yes |
| Model states | Missing, partial, corrupt, stale, and unexpected model dirs fail safely | `scripts/ci/validate_models.py`; `scripts/ci/test_model_faults.py` | Every PR | Yes |
| Corpus manifest | Corpus files and ground truth are present and well formed | `scripts/ci/validate_corpus.py` | Every PR | Yes |
| Corpus baseline | Current benchmark output does not regress stored baseline | `scripts/ci/validate_corpus_baseline.py --results <json>` | Release candidate and conversion changes | Yes |
| Pathway baseline | Each valid pathway is covered and compared per document | `scripts/ci/validate_corpus_pathways.py --results <json>` | Release candidate and pathway changes | Yes |
| Benchmark comparison | Human-readable file x pathway score table | `scripts/ci/summarize_corpus_pathway_reports.py reports/corpus-*.json` | Release candidate | Yes |
| Concurrency benchmark | Serial vs parallel accuracy, failures, wall time, load evidence | `scripts/benchmark_concurrency.py --pathway <id>` | Queue/concurrency changes | Yes for concurrency changes |
| Storage access | iCloud/local/security-scoped file behavior | `docs/release/STORAGE_VALIDATION.md` evidence and focused tests | Storage changes and RC | Yes |
| Diagnostics | Redacted bug report, OSLog, crash/support runbook | `UpmarketTests/DiagnosticsTests.swift`; `UpmarketTests/SupportReporterTests.swift` | Every PR touching diagnostics | Yes |
| StoreKit | Product loading, purchases, pack ledger, restore, pending transaction | StoreKit sandbox/manual evidence plus unit tests | Store changes and RC | Yes |
| App Store metadata | Privacy, licenses, support, screenshots, listing, age rating | App Store Connect review checklist | Release candidate | Yes |

## Touched-Code Rule

Do not run every expensive test for every backend-only change. Run the narrowest reliable gate for the touched interface, then broaden to the full release-candidate matrix before shipping.

## Expected Blocked Results

A corpus document that needs missing user input, such as a password-protected PDF without a supplied password, is `expected_blocked`, not `failed`. It still appears in benchmark output, but it must not reduce quality averages or count against failed-document limits.

## Automation Boundary

UI automation is intentionally release-candidate scoped because it can alter the user's system appearance. Unit, package, copy, corpus, and model checks should remain safe for normal PR/local runs.
