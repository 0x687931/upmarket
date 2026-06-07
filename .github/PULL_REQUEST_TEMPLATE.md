## Summary


## Release Gate

- [ ] P0 blocker
- [ ] Gate A - Build and Packaging
- [ ] Gate B - Conversion Reliability
- [ ] Gate C - Stability and Diagnostics
- [ ] Gate D - StoreKit and App Store
- [ ] Gate E - Legal, Privacy, and Listing
- [ ] v1.1 / post-launch

## Scope

Files/modules intentionally changed:

Files/modules intentionally not changed:

## Validation

- [ ] `scripts/ci/gate.sh quick`
- [ ] Runtime/package gate if Python, packaging, dependencies, entitlements, corpus, models, or release automation changed: `scripts/ci/gate.sh runtime`
- [ ] UI automation gate if visible UI, launch, menu bar, paywall, preferences, or UI tests changed: `scripts/ci/gate.sh ui`
- [ ] Release gate for minor candidates: `scripts/ci/gate.sh minor`
- [ ] Release gate for major candidates: `scripts/ci/gate.sh major`
- [ ] Manual check:

## Risk Review

- [ ] App Store / entitlement impact considered
- [ ] Privacy/logging impact considered
- [ ] Python/runtime impact considered
- [ ] StoreKit/monetization impact considered
- [ ] User-facing screenshots attached for UI changes

## Agent Handoff

Owner:
Validation not run:
Known risks:
Next recommended task:
