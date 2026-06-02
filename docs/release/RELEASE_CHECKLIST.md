# Release Checklist

Use this checklist for every internal beta, external beta, and App Store candidate. Record the commit SHA, archive path, Xcode version, macOS version, and benchmark report paths in the release issue.

## 1. Preflight

- Confirm working tree is clean except intended release artifacts: `git status --short`.
- Confirm local Xcode is 26 or newer:
  ```sh
  xcodebuild -version
  ```
- Confirm P0 registry and implementation plan sync:
  ```sh
  scripts/ci/gate.sh policy
  ```
- Confirm no hidden launch windows, zero-size placeholder scenes, or create-then-hide AppKit window workarounds were introduced.
- Confirm the normal local/PR gate passes without a developer account:
  ```sh
  scripts/ci/gate.sh quick
  ```
- If the local runtime artifact is missing, prepare it first:
  ```sh
  scripts/ci/ensure_python_runtime.sh
  ```

## 2. Build And Package

- Rebuild and verify the runtime/app package:
  ```sh
  scripts/ci/gate.sh runtime
  ```
- For a minor release candidate, run the full release gate:
  ```sh
  scripts/ci/gate.sh minor
  ```
- For a major release candidate, include UI automation:
  ```sh
  scripts/ci/gate.sh major
  ```
- For signed release verification, require embedded entitlements:
  ```sh
  UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS=1 scripts/ci/verify_entitlements.sh /path/to/Upmarket.app
  ```
- Archive the release candidate with the release team selected in Xcode or CI. Local unsigned archives may still use `CODE_SIGNING_ALLOWED=NO`; App Store submission requires the signed release path.

## 3. Tests

- `scripts/ci/gate.sh quick` covers policy checks, build, effective plist, and unit tests.
- `scripts/ci/gate.sh runtime` covers runtime packaging, app package verification, offline smoke, and helper boundary checks.
- `scripts/ci/gate.sh minor` adds corpus, model, and fault-state checks.
- `scripts/ci/gate.sh major` adds UI automation for major candidates and explicit UI changes.

## 4. Benchmarks

- Run the required pathway benchmark for touched conversion paths.
- Generate comparison artifacts with `scripts/ci/summarize_corpus_pathway_reports.py`.
- If queue concurrency is under review, run `scripts/benchmark_concurrency.py` and update `docs/release/SERIAL_PARALLEL_BENCHMARKS.md`.
- Do not update corpus baselines unless the quality change is understood and documented.

## 5. App Store Readiness

- Verify StoreKit products in sandbox: subscriptions, packs, restore, failed purchase, pending transaction, and ledger migration.
- Review crash reports in Xcode Organizer for the candidate build.
- Confirm signed archive/export behavior once a developer account is available; local testing remains unsigned.
- Confirm privacy policy, support link, licenses, screenshots, app category, age rating, and App Privacy answers.
- Confirm Preferences/About links to privacy, licenses, support, and version.

## 6. Release Decision

- Attach CI run links, benchmark reports, signed archive evidence, and known issues to the release issue.
- The owner approves or rejects the candidate.
- Tag only approved candidates.
