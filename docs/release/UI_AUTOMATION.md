# UI Automation

Upmarket uses Apple's XCTest UI testing framework for end-to-end UI coverage. The test target is `UpmarketUITests`, and all UI automation runs through the same Xcode scheme as the app.

Apple references:

- XCTest framework: https://developer.apple.com/documentation/XCTest
- Xcode distribution and release testing: https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases

## Entry Points

Local focused run:

```sh
scripts/ci/gate.sh ui
```

Major or release-candidate run:

```sh
scripts/ci/gate.sh major
```

Direct Xcode form:

```sh
xcodebuild test \
  -project Upmarket/Upmarket.xcodeproj \
  -scheme Upmarket \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath build/DerivedData \
  -only-testing:UpmarketUITests \
  CODE_SIGNING_ALLOWED=NO
```

The `gate.sh ui` path writes an `.xcresult` bundle under `build/TestResults/` by default. Override it with `UPMARKET_UI_RESULT_BUNDLE_PATH=/path/to/result.xcresult` when a fixed path is needed.

The script path is preferred over the direct Xcode form. It builds for testing unsigned, ad-hoc signs the built `Upmarket.app` and `UpmarketUITests-Runner.app`, then runs `xcodebuild test-without-building`. This avoids requiring provisioning profiles while preventing macOS from rejecting the UI-test runner as damaged or corrupt. Override the signing identity with `UPMARKET_UI_CODE_SIGN_IDENTITY`; the default is `-`.

## Automated CI Lanes

`.github/workflows/ui-automation.yml` runs automatically for pull requests and pushes that touch UI-sensitive files, the Xcode project, UI tests, app launch code, or the UI gate script. It also supports manual `workflow_dispatch`.

`.github/workflows/release-candidate.yml` runs UI automation for every release-candidate branch or manual release-candidate workflow. Release candidates upload the UI `.xcresult` bundle as an artifact.

`scripts/ci/gate.sh quick` intentionally does not run UI automation for every backend-only PR. The separate UI workflow keeps normal PR feedback fast while still running Apple's UI test framework automatically when UI behavior is likely to change.

## Current Coverage

The current UI tests cover:

- primary conversion window mount;
- stable access to the choose-document control;
- GUI quit and relaunch cleanup for app-owned workspaces;
- launch screenshot capture for result-bundle triage.

Add a UI test when a change affects a visible flow that a user repeats or that can regress without a compiler error: launch, shelf, file selection, conversion status, paywall, preferences, diagnostics, feedback, menu bar, or release-facing onboarding.

## Test Design Rules

- Use XCTest and XCUIAutomation for UI tests. Swift Testing is allowed for pure Swift unit/integration tests, not for UI automation.
- Use stable `accessibilityIdentifier` values for controls that tests need to find.
- Prefer `launchEnvironment` and temporary files for deterministic setup.
- Keep UI tests offline and privacy-safe. Do not use private documents, cloud state, or network-dependent fixtures.
- Avoid sleeps. Use `waitForExistence(timeout:)` or explicit polling for app-owned files/state.
- Clean up any temporary files created by the test.
- Keep UI tests focused on user-visible contracts, not implementation details hidden behind services.

## Local macOS Notes

The first local UI test run may require approving Xcode/Xcode Helper automation or accessibility prompts. CI runners handle this through the GitHub-hosted macOS environment, but local failures caused by permissions should be resolved before treating a UI failure as an app regression.

## Triage

For a UI failure:

1. Open the uploaded `.xcresult` bundle in Xcode.
2. Check screenshots, accessibility hierarchy, logs, and failure line.
3. Re-run `scripts/ci/gate.sh ui` locally before changing production code.
4. If the test is flaky, fix the wait/setup logic rather than weakening the assertion.
5. If the UI changed intentionally, update the test and record the release gate in the PR.
