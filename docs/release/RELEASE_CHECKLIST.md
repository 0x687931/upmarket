# Release Checklist

Use this checklist for every internal beta, external beta, and App Store candidate. Record the commit SHA, archive path, Xcode version, macOS version, and benchmark report paths in the release issue.

## 1. Preflight

- Confirm working tree is clean except intended release artifacts: `git status --short`.
- Confirm P0 registry and implementation plan sync:
  ```sh
  scripts/ci/validate_task_registry.py
  scripts/ci/validate_p0_plan_sync.py
  ```
- Confirm architecture and copy boundaries:
  ```sh
  scripts/ci/validate_architecture_boundaries.py
  scripts/ci/validate_user_facing_copy.py
  ```
- Confirm no hidden launch windows, zero-size placeholder scenes, or create-then-hide AppKit window workarounds were introduced.
- Confirm generated docs are current:
  ```sh
  scripts/docs/generate_repo_docs.py --check
  ```

## 2. Build And Package

- Build the app:
  ```sh
  xcodebuild build -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
  ```
- Archive the release candidate with the release team selected in Xcode or CI.
- Verify the built or archived app:
  ```sh
  scripts/ci/verify_release_app.sh build/DerivedData/Build/Products/Debug/Upmarket.app
  ```
- For signed release verification, require embedded entitlements:
  ```sh
  UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS=1 scripts/ci/verify_entitlements.sh /path/to/Upmarket.app
  ```

## 3. Tests

- Run unit tests:
  ```sh
  xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:UpmarketTests CODE_SIGNING_ALLOWED=NO
  ```
- Run UI automation only for release candidates:
  ```sh
  xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:UpmarketUITests CODE_SIGNING_ALLOWED=NO
  ```
- Run model, corpus, and fault checks:
  ```sh
  scripts/ci/validate_models.py
  scripts/ci/test_model_faults.py
  scripts/ci/validate_corpus.py
  scripts/ci/validate_corpus_baseline.py
  scripts/ci/validate_corpus_pathways.py
  ```

## 4. Benchmarks

- Run the required pathway benchmark for touched conversion paths.
- Generate comparison artifacts with `scripts/ci/summarize_corpus_pathway_reports.py`.
- If queue concurrency is under review, run `scripts/benchmark_concurrency.py` and update `docs/release/SERIAL_PARALLEL_BENCHMARKS.md`.
- Do not update corpus baselines unless the quality change is understood and documented.

## 5. App Store Readiness

- Verify StoreKit products in sandbox: subscriptions, packs, restore, failed purchase, pending transaction, and ledger migration.
- Review crash reports in Xcode Organizer for the candidate build.
- Confirm privacy policy, support link, licenses, screenshots, app category, age rating, and App Privacy answers.
- Confirm Preferences/About links to privacy, licenses, support, and version.

## 6. Release Decision

- Attach CI run links, benchmark reports, signed archive evidence, and known issues to the release issue.
- The owner approves or rejects the candidate.
- Tag only approved candidates.
