# Build, Ship, And Deploy

This is the operational path for building Upmarket, validating it, uploading it to TestFlight, and shipping it through the App Store.

Apple references:

- Distributing apps for beta testing and releases: https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
- TestFlight overview: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- Upload builds in App Store Connect: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/

## Source Of Truth

Use these documents together:

- `docs/BUILD_SHIP_DEPLOY.md`: end-to-end build, ship, and deploy path.
- `docs/release/RELEASE_CHECKLIST.md`: candidate checklist.
- `docs/release/RELEASE_PIPELINE.md`: CI and automation details.
- `docs/release/TEST_MATRIX.md`: required validation surface.
- `docs/release/UI_AUTOMATION.md`: Apple XCTest UI automation policy.
- `docs/IMPLEMENTATION_PLAN.md`: open release blockers.

## Prerequisites

- Xcode 26 or newer selected with `xcodebuild -version`.
- Apple Developer Program membership and App Store Connect access.
- The Upmarket app target has the release team configured in the Xcode project.
- Python 3.12 is available for runtime verification.
- `Upmarket/Python/Python.xcframework` exists locally. If missing, run `scripts/ci/ensure_python_runtime.sh`.
- App Store Connect records exist for the app, in-app purchases, privacy answers, support links, and TestFlight tester groups.

## Release Lanes

| Lane | Audience | Command Or Evidence | When |
| --- | --- | --- | --- |
| Local development | Owner machine | `scripts/dev/run_app.sh` | Daily iteration |
| Fast PR gate | CI and local | `scripts/ci/gate.sh quick` | Every PR |
| UI automation | CI and local | `scripts/ci/gate.sh ui`; `.github/workflows/ui-automation.yml` | UI-sensitive PRs, manual runs |
| Runtime package | CI and local | `scripts/ci/gate.sh runtime` | Python, dependency, entitlement, package changes |
| Minor candidate | Release owner | `scripts/ci/gate.sh minor` | Internal beta candidate |
| Major candidate | Release owner | `scripts/ci/gate.sh major` | Major release or explicit UI changes |
| TestFlight internal | Internal testers | App Store Connect TestFlight build page | First beta distribution |
| TestFlight external | External testers | TestFlight App Review approval | After internal pass |
| App Store release | Customers | App Store submission and owner approval | Final approved candidate |

## Local Build

Run the app locally:

```sh
scripts/dev/run_app.sh
```

Run the normal PR gate:

```sh
scripts/ci/gate.sh quick
```

Run Apple XCTest UI automation:

```sh
scripts/ci/gate.sh ui
```

For explicit UI changes or a major candidate, run:

```sh
scripts/ci/gate.sh major
```

## Runtime And Package Verification

Use the runtime gate when a change touches Python, packaged dependencies, entitlements, model handling, corpus conversion, app package structure, or release automation:

```sh
scripts/ci/gate.sh runtime
```

The package verifier checks effective plist values, entitlements, Apple bundle preflight, bundled Python imports, Python bridge security preflight, runtime helper boundaries, MCP smoke, and offline conversion smoke:

```sh
scripts/ci/verify_release_app.sh /path/to/Upmarket.app
```

For signed release verification, require embedded signed entitlements:

```sh
UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS=1 scripts/ci/verify_entitlements.sh /path/to/Upmarket.app
```

## Model Asset Hosting

### Debug / development (GitHub CDN)

Debug builds download models from GitHub Releases. Manifests are small JSON files committed to the repo; archives are `.tar.gz` files attached to a GitHub Release. Downloads are resumable — if interrupted, the next attempt picks up from where it stopped.

**One-time setup** (repeat when models change):

```sh
# 1. Stage archives and manifests.
#    python_runtime is sourced from the bundled xcframework — no prior download needed.
#    layout and upmarket_ai require a developer-intake download first (see below).
scripts/build/stage_github_model_assets.py \
  --release-url https://github.com/OWNER/REPO/releases/download/models-v1

# 2. Create the GitHub Release and upload archives.
gh release create models-v1 --title "Model Assets v1"
gh release upload models-v1 build/github-model-assets/archives/*.tar.gz

# 3. Commit manifests to the repo.
cp build/github-model-assets/manifests/*.json resources/model-manifests/
git add resources/model-manifests/ && git commit -m "Add GitHub CDN model manifests v1"

# 4. Enable in Xcode: open the Upmarket scheme → Run → Environment Variables.
#    Set UPMARKET_MODEL_MANIFEST_BASE_URL (enable the row):
#      https://raw.githubusercontent.com/OWNER/REPO/main/resources/model-manifests/
```

**Developer-intake download** (to stage layout / upmarket_ai):

```sh
# Launch the app with developer intake enabled, then trigger download from Preferences → Models.
UPMARKET_ENABLE_DEVELOPER_MODEL_INTAKE=1 scripts/dev/run_app.sh
```

### Production / TestFlight (Apple CDN)

Production and TestFlight model downloads must be first-party. Stage model assets from a manifest-validated local cache, upload the staged directory to the Apple-hosted model location, and build the app with that base URL:

```sh
scripts/build/stage_first_party_model_assets.py --output build/first-party-model-assets

xcodebuild archive \
  -project Upmarket/Upmarket.xcodeproj \
  -scheme Upmarket \
  -destination "generic/platform=macOS" \
  -archivePath build/Upmarket.xcarchive \
  -derivedDataPath build/DerivedData \
  INFOPLIST_KEY_UpmarketModelManifestBaseURL="https://<apple-hosted-model-base>/" \
  -allowProvisioningUpdates
```

Verify release archives with the model URL gate enabled. By default it accepts Apple/iCloud host suffixes; override `UPMARKET_MODEL_MANIFEST_ALLOWED_HOSTS` only for reviewed first-party Apple-backed hosting.

```sh
APP=build/Upmarket.xcarchive/Products/Applications/Upmarket.app
UPMARKET_REQUIRE_MODEL_MANIFEST_BASE_URL=1 scripts/ci/verify_release_app.sh "$APP"
```

**Testing the Apple CDN path locally (before uploading to production hosting):**

The app's download runtime has no host restriction — only the release verification script does. You can exercise the exact same code path against a local HTTP server:

```sh
# 1. Stage models locally (requires models in Application Support — use developer intake first).
scripts/build/stage_first_party_model_assets.py --output build/first-party-model-assets

# 2. Serve the staged directory.
python3 -m http.server 8765 --directory build/first-party-model-assets

# 3. In Xcode scheme → Run → Environment Variables, enable and set:
#      UPMARKET_MODEL_MANIFEST_BASE_URL = http://localhost:8765/

# 4. Launch the app and trigger a download from Preferences → Models.
scripts/dev/run_app.sh --relaunch
```

This tests the full individual-file download path (manifest fetch → per-file download → checksum → atomic promote) before any files touch Apple infrastructure. The local server is HTTP; the sandbox allows it because `com.apple.security.network.client` is not restricted to HTTPS.

When you're satisfied, upload `build/first-party-model-assets/` to Apple-hosted storage and switch the URL in the production archive build.

## Archive

Unsigned local archive rehearsal:

```sh
xcodebuild archive \
  -project Upmarket/Upmarket.xcodeproj \
  -scheme Upmarket \
  -destination "generic/platform=macOS" \
  -archivePath build/Upmarket.xcarchive \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Signed release archive:

```sh
xcodebuild archive \
  -project Upmarket/Upmarket.xcodeproj \
  -scheme Upmarket \
  -destination "generic/platform=macOS" \
  -archivePath build/Upmarket.xcarchive \
  -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates
```

The signed archive may prompt for keychain access. Approve the prompt, then verify the archived app:

```sh
APP=build/Upmarket.xcarchive/Products/Applications/Upmarket.app
UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS=1 scripts/ci/verify_entitlements.sh "$APP"
UPMARKET_REQUIRE_MODEL_MANIFEST_BASE_URL=1 scripts/ci/verify_release_app.sh "$APP"
```

## Upload To App Store Connect

Preferred path:

1. Open Xcode Organizer.
2. Select the archive.
3. Choose `Distribute App`.
4. Choose `TestFlight & App Store` unless the build will never be used outside internal TestFlight.
5. Upload symbols so Xcode Organizer can show symbolicated crash logs.
6. Use automatic signing unless a release task explicitly requires manual signing.
7. Upload and record the build number, commit SHA, archive path, and upload time in the release issue.

Do not choose `TestFlight Internal Only` for a candidate that may later go to external testers or App Store submission.

## TestFlight

Internal beta comes first:

- Create or update beta app description, What to Test, feedback email, support contact, and review notes.
- Assign the uploaded build to the internal tester group.
- Record tester list, build number, upload time, and 90-day beta expiry in the release issue.
- Install from TestFlight and run launch, conversion smoke, diagnostic bundle, StoreKit sandbox purchase/restore, and preferences checks.
- Review TestFlight feedback, sessions, crashes, and Xcode Organizer diagnostics before widening.

External beta follows only after internal issues have an owner decision:

- Create a small external tester group or constrained public link.
- Submit the build for TestFlight App Review when required.
- Keep distribution limited until sandbox purchase and restore paths are proven.
- Record known issues and decide fix now, document, or reject candidate.

## App Store Submission

Before submitting:

- `scripts/ci/gate.sh major` passes for major candidates or explicit UI changes.
- `scripts/ci/gate.sh minor` passes for release candidates.
- Signed archive verification passes with required entitlements.
- StoreKit products, pack accounting, pending transaction, failed purchase, and restore paths pass sandbox review.
- App Privacy answers, privacy policy, support URL, licenses, screenshots, category, age rating, and app listing copy are complete.
- CloudKit feature flags needed for release are deployed to production.
- Xcode Organizer shows no unresolved crash pattern for the candidate build.

The owner approves the candidate, then the App Store submission can proceed.

## Deployment Evidence

Attach this evidence to the release issue:

- commit SHA and branch;
- Xcode and macOS versions;
- CI run links;
- `gate.sh quick`, `runtime`, `minor`, `major` or `ui` result;
- UI `.xcresult` bundle artifact for UI/release candidates;
- archive path and signing evidence;
- TestFlight build number and tester group;
- corpus benchmark reports;
- known issues and release decision.

## Rollback And Rejection

If a candidate fails a release gate, reject it. Do not reuse the failed build for wider TestFlight or App Store distribution.

For a failed TestFlight candidate:

1. Remove or stop distribution to affected tester groups where appropriate.
2. Create or update the issue with reproduction steps and owner decision.
3. Fix in a new commit.
4. Rebuild, re-archive, re-upload, and rerun the relevant release lane.
