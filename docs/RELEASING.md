# Upmarket — Release Process

The canonical build, shipping, and deployment process is `docs/BUILD_SHIP_DEPLOY.md`. Use that document for release commands, UI automation, archive verification, TestFlight, App Store submission, and deployment evidence.

Conversion is native Swift end-to-end — there is no Python runtime and no Python dependency lifecycle to track. This file keeps the release-prep notes that are still useful.

## Before Every Release

### 1. Review Swift package dependencies

App dependencies are Swift packages pinned in
`Upmarket/Upmarket.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (committed). To pick up upstream updates, resolve in Xcode (File → Packages → Update to Latest Package Versions) and commit the changed `Package.resolved`, then run `scripts/ci/gate.sh quick`.

Key repos to watch:
- **mlx-swift / mlx-swift-lm**: https://github.com/ml-explore — the Granite-Docling (`UpmarketVLM`) inference stack.
- **swift-huggingface / swift-transformers**: https://github.com/huggingface — tokenizer/model loading.
- **Feature flags**: CloudKit public record `FeatureFlags/global` in `iCloud.com.upmarket.app` (language support changes; see `docs/release/FEATURE_FLAG_LANGUAGE_POLICY.md`).

### 2. Refresh license attributions

```bash
scripts/generate_licenses.sh
```

Regenerates `Upmarket/Upmarket/Resources/licenses.json` (the About screen) from `Package.resolved` + each checkout's LICENSE file. First-party vendored code (`SwiftOfficeMarkdown`, `UpmarketVLM`) is intentionally excluded. Requires a build first so the SwiftPM checkouts exist.

### 3. Stage the AI model asset

The Max-tier `upmarket_ai` asset (Granite-Docling mlx-swift weights, ~600 MB) is delivered as a flat directory (`config.json` + `*.safetensors`) via Apple Background Assets, downloaded by `BackgroundAssetsDownloadService` (`FirstPartyModelDownloadService` for local/debug). Upload the model archive to the App Store Connect Additional Resources slot registered in `UpmarketBackgroundAssetsExtension`. (A native staging helper that produces the archive from the published HF mlx repo is a follow-up.)

### 4. Test conversion quality

```bash
# Native gate: builds + runs the unit suite (367 tests) and policy checks.
scripts/ci/gate.sh quick

# Spot-check real documents through the CLI (PDF / image / text):
xcrun --sdk macosx swiftc -version >/dev/null   # ensure toolchain
build/DerivedData/Build/Products/Debug/Upmarket.app/Contents/MacOS/upmarket-cli convert path/to/test.pdf
```

Corpus pathway coverage and manifest/baseline integrity are validated by `scripts/ci/gate.sh release` (the `corpus_and_model_gate`). A native corpus quality-scoring benchmark (drive `upmarket-cli` over the corpus, score against ground truth) is a follow-up — the previous Python/Docling benchmark harness was removed with the runtime.

### 5. Build, version, archive, submit

- `scripts/ci/gate.sh quick` (or `major` for a UI-automation release candidate).
- Bump `MARKETING_VERSION` (Upmarket target → General → Version): patch for fixes (1.0.1), minor for features (1.1.0), major for breaking (2.0.0).
- Product → Archive → Distribute App → App Store Connect → Upload.

---

## Enabling New Languages for Upmarket AI

Feature flags describe Upmarket's shipped app behavior, not every upstream Granite-Docling capability claim. Use `docs/release/cloudkit_feature_flags_seed.json` as the initial beta record.

When Granite-Docling improves support for a language:

1. Confirm the upstream claim from a primary source and record it in `docs/release/FEATURE_FLAG_LANGUAGE_POLICY.md`.
2. Add or identify representative fixtures for that language.
3. Test Upmarket AI conversion quality on Apple Silicon with the pinned release model.
4. Keep the language in `ai_experimental_locales` while the evidence is upstream-explicit early support only.
5. Move the language to `ai_supported_locales` only after the shipped Upmarket path meets beta quality.
6. Bump the CloudKit record `version`.
7. Deploy the CloudKit schema/record change to production before release users need it.
8. Verify the signed release build has `com.apple.developer.icloud-container-environment=Production`.
9. No app update needed — users get AI for that language after the next feature availability check.

Note: Granite-Docling-258M is not multilingual. `NativeDocumentClassifier.recommendedEngine` gates the native Granite path to clean typed Latin and simplified-Chinese documents; everything else falls back to Apple Vision.
