# Incident Runbook

Upmarket uses a privacy-first support process. Do not request source documents, extracted text, passwords, or full local file paths. Prefer Apple-native crash reports, redacted user-approved diagnostics, OSLog excerpts, and reproducible corpus cases.

## Severity

- P0: release-blocking crash spike, paid conversion loss, data exposure, StoreKit purchase/credit failure, or conversion flow unusable.
- P1: major conversion failure, model download outage, stalled helper behavior, or repeated user-visible regression.
- P2: isolated UI, accessibility, copy, or edge-case conversion issue.

## Intake

1. Capture the category: crash, Python helper crash or stall, stalled conversion, conversion failure, model download failure, StoreKit/payment issue, App Store/release regression, feature flag regression, or UI/accessibility bug.
2. Ask for the Help > Report a Problem preview text only if the user approves including diagnostics.
3. File or update a GitHub issue with severity, app version/build, macOS/hardware, correlation ID, last stage, and sanitized steps.
4. Do not attach documents unless a synthetic or public reproduction fixture can be created.

## Crash Spikes

Use Xcode Organizer for TestFlight/App Store crash reports. Treat a repeated crash in launch, conversion, purchase, model download, or support reporting as P0 until disproven. Link crash signatures to GitHub issues and block release until the crash is fixed or explicitly deferred with a reproducible non-release condition.

## Python Helper Crashes or Stalls

Map crashes, import failures, exits, and no-progress states to typed Swift errors. Confirm the failure is behind `PythonWorker`; no view or queue should import PythonKit. Reproduce with a local corpus file, then add a regression fixture before adopting upstream package changes.

## Corrupt Model Rollouts

Stop promotion of the candidate manifest. Delete staged model directories and verify the current manifest remains valid. A model issue cannot be closed until offline conversion, missing-model behavior, and manifest validation pass locally.

## Broken Feature Flags

Disable the flag remotely or fall back to local defaults. Feature flags must never enable cloud conversion, broaden file access, bypass StoreKit gating, or implicitly download models.

## StoreKit Failures

Treat failed paid credit delivery, duplicate debits, interrupted purchase loss, and refund/revocation mistakes as P0. Preserve transaction IDs, ledger state, and redacted diagnostics; never ask the user for App Store credentials or receipts in plain text.

## Release Exit

An incident is resolved when the fix is committed, the issue has validation evidence, the implementation plan is updated if scope changed, and release gates covering the affected area pass.
