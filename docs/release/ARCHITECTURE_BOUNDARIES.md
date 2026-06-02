# Architecture Boundaries

Upmarket is a small macOS monolith. The goal is direct code with hard ownership lines, not a framework-heavy architecture.

## Target Layout

```text
Upmarket/Upmarket/
  Views/              SwiftUI presentation, user gestures, visible state
  Domain/             ConversionJob, ConversionResult, ConversionError, Entitlement
  Services/           ConversionQueue, ConversionRunner, PythonWorker, Store, Diagnostics, FileAccess
  Infrastructure/     Process/runtime adapters when a boundary needs isolation
  UpmarketRuntimeHelper/
                      Signed helper executable for advanced/model runtime work
  Resources/          Localisation, licenses, privacy manifest, assets
  Intents/            App Intents and system integration entry points
```

Do not create folders until there is code to move. Prefer one clear service over a protocol plus one implementation.

## Boundary Rules

- Views render state, collect user intent, and call concrete services.
- Views must not import `PythonKit` or call Python modules.
- Views should not own AppKit file picker, save panel, pasteboard, or Finder logic; use `FileAccessService`.
- Conversion has one product entry point: `ConversionQueue`.
- `ConversionRunner` performs conversion work for one `ConversionJob`.
- Advanced/model runtime calls go through `PythonWorker` and the isolated runtime helper; `PythonBridge` may remain as an observable readiness facade only.
- StoreKit remains behind `StoreManager`; paywall views may display StoreKit product state but should not duplicate purchase policy.
- Diagnostics must go through a dedicated service once P0-008 starts; do not add new `print`-based diagnostics.
- Product tiering and conversion routing must follow `docs/release/TIER_AND_ROUTING_POLICY.md`: two product tiers, with capability-gated conversion paths inside Enhanced.

## Current Exceptions

These are known P0 follow-up items, not patterns to copy:

- `ModelManager` uses `PythonWorker` for model checks/downloads; P0-004 hardens offline model integrity and download validation.
- `PaywallView` imports StoreKit for `Product`; P0-007 reviews StoreKit accounting and purchase policy.
- `SavePreference` owns save-location prompts; it predates `FileAccessService` and should either stay as the save-preference coordinator or delegate picker mechanics later.

## Adding Code

Before adding a new dependency, process boundary, entitlement, release hook, or long-lived service, add an ADR under `docs/release/adr/`.

Before adding a new conversion entry point, update P0-012 instead. The app should not grow separate conversion paths for shelf, menu bar, intents, and main window.
