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

- [ ] `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' build`
- [ ] `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' test`
- [ ] Relevant CI hook/script:
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
