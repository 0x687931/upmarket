# Repository Review

Scope: maintainability, security, and speed for the current SwiftUI macOS app
with an embedded Python conversion layer.

## Current Structure

The app is split across:

- `Upmarket/Upmarket/`: macOS app source.
- `Upmarket/Upmarket/Views/`: SwiftUI views and view-adjacent UI controllers.
- `Upmarket/Upmarket/Services/`: app services, window controllers, StoreKit,
  conversion orchestration, model management, and Python bridge setup.
- `Upmarket/Upmarket/Intents/`: App Intents.
- `Upmarket/Upmarket/Resources/`: localized strings and generated licenses.
- `Upmarket/UpmarketQuickAction/`: Finder/Quick Action extension.
- `Upmarket/UpmarketTests/`: Xcode-managed unit tests.
- `Upmarket/UpmarketUITests/`: Xcode-managed UI tests.
- `UpmarketPython/`: Python bridge modules bundled into the app.
- `tests/corpus/`: large document fixtures and upstream corpus material.
- `docs/`: project, release, corpus, and user-flow documentation.

## Maintainability

What is good:

- App, extension, Python bridge, docs, scripts, and corpus are separated.
- Xcode file-system-synchronized groups reduce project-file churn for new Swift
  files.
- Services already isolate most non-view behavior from SwiftUI presentation.
- The shelf, menu bar, purchase, and conversion flows use notifications where a
  single shared service would couple unrelated windows.

Changes made in this pass:

- Moved the substantive Swift tests from root `UpmarketTests/` into
  `Upmarket/UpmarketTests/`, which is the folder attached to the Xcode test
  target.
- Added `docs/USER_FLOW.md` as the product-flow reference.

Recommended next cleanup:

- Move `TourManager.swift` from `Views/` to `Services/` or a new
  `Onboarding/` folder. It is an AppKit orchestration service, not a SwiftUI
  view.
- Consider a small `Notifications.swift` or `AppEvents.swift` file instead of a
  broad `Extensions.swift` as the notification list grows.
- Replace placeholder template tests with behavior tests for shelf onboarding,
  paywall presentation, and entitlement edge cases.
- Keep corpus data out of normal Xcode targets; use it only from explicit tests
  or benchmark scripts.

## Security

What is good:

- App Sandbox is enabled.
- File conversion copies user-selected input to a temp URL before processing.
- StoreKit transactions are verified before entitlements or pack credits are
  granted.
- Python bridge input validation has file size, password length, text size, and
  regex input caps.

Changes made in this pass:

- Hardened Python path validation to compare resolved paths against allowed
  roots with path-relative checks instead of string-prefix checks.

Risks to keep visible:

- The app has network client entitlement for model download and feature flags.
  Runtime conversion should keep working offline after models are available.
- The temporary absolute-path entitlement is broad. Prefer sandbox-provided temp
  locations and remove this exception if conversion continues to work without it.
- Customer model downloads should go through the first-party Apple-hosted
  manifest flow. Keep the Python/Hugging Face snapshot path as developer intake
  tooling only, and ensure conversion paths do not trigger unexpected network
  fetches when models are already present.
- UserDefaults is fine for free-credit counters and UI state, but paid access
  must continue to come from verified StoreKit entitlements.

## Speed

What is good:

- First launch does not force a model download.
- Fast conversion path is available before enhanced/AI model downloads.
- Python setup is launched asynchronously from app initialization.
- Heavy conversion work is dispatched away from the main actor.
- Xcode file-synced groups reduce maintenance overhead for added source files.

Potential improvements:

- Delay Python runtime initialization until first conversion if cold launch time
  becomes a visible problem.
- Keep the first-launch tour lightweight; avoid model checks or Python imports
  in the onboarding path.
- Add a launch-performance UI test with a fixed first-run state once the shelf
  tour stabilizes.
- Split long-running corpus/quality tests from fast unit tests if they slow down
  normal edit-build-test cycles.
