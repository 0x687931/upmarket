# Release Policy

Upmarket releases are gated by stability, privacy, App Store readiness, and conversion quality. A release candidate is not shippable until every P0 gate in `docs/IMPLEMENTATION_PLAN.md` is complete or explicitly deferred with owner approval and a documented non-release rationale.

## Release Types

| Type | Purpose | Allowed Audience | Required Gates |
| --- | --- | --- | --- |
| Local dev build | Developer iteration only | Owner machine | Build, focused unit tests for touched code |
| Internal beta | End-to-end release rehearsal | Owner/TestFlight internal testers | PR CI, release-candidate CI, diagnostics, StoreKit sandbox |
| External beta | Usability and crash validation | Selected TestFlight users | Internal beta gates plus crash review and support path |
| App Store release | Public sale | App Store users | All gates, listing, privacy, licenses, signed archive |

## Ship Criteria

- App builds, archives, and passes `scripts/ci/verify_release_app.sh` on the archived app.
- Unit tests pass for `UpmarketTests`; UI automation runs only for release candidates because it can alter system appearance.
- User-facing copy does not expose internal toolkit or package names outside licenses, diagnostics, developer docs, and benchmark artifacts.
- Conversion corpus and pathway baselines do not regress beyond policy thresholds.
- Python/runtime packages are reproducible, pinned, imported from the packaged app, and offline by default.
- Models are present only after manifest validation; missing, partial, corrupt, or unexpected model states fail safely.
- StoreKit products, entitlement accounting, pack credits, and restore flows pass sandbox review.
- App privacy answers, privacy policy, licenses, support path, screenshots, and App Store metadata are ready.

## No-Ship Conditions

- Any crash in launch, conversion, StoreKit, diagnostics, model handling, or helper startup without a fix or documented non-release cause.
- Any conversion entitlement bypass, lost paid credit, or unrecorded StoreKit transaction.
- Any bundled forbidden dependency or reference-only benchmark package.
- Any network access during conversion.
- Any support report that can include document content, passwords, or full local paths.
- Any corpus downgrade without reviewed baseline correction.

## Release Authority

The owner is the only release approver. Codex may prepare commits, issues, checklists, and artifacts, but cannot promote a build to TestFlight/App Store without explicit owner approval.
