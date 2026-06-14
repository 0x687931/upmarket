# Upmarket Tier Contract

**This document is non-normative.** The tier contract is **code**, not prose, so it
cannot silently drift:

- **Source of truth:** [`Upmarket/Upmarket/Domain/AppTier.swift`](../Upmarket/Upmarket/Domain/AppTier.swift)
  defines the tiers, product IDs, prices, the asset → tier mapping, and `AppTierGate`
  (the single point of truth for every capability/download gating decision).
- **Enforcement:** [`AppTierContractTests`](../Upmarket/UpmarketTests/AppTierContractTests.swift)
  fails `scripts/ci/gate.sh quick` if `Store.storekit` ever disagrees with `AppTier`
  (product IDs, prices, stray products). App Store Connect product IDs must match too.

If you need to change a tier, price, or product: **edit `AppTier.swift` first**, update
`Store.storekit` to match, and let the test confirm they agree. Do not re-describe the
tiers here — a prose copy is exactly how this repo accumulated five contradicting tier
docs. This file intentionally stays a pointer.

## Tiers (summary, for orientation only — `AppTier.swift` is authoritative)

| Tier | Price | Capabilities |
|------|-------|--------------|
| Basic | Free | Native Apple conversion (PDFKit, Vision OCR, Speech, AVFoundation) |
| Pro | $9.99 | + Enhanced (layout analysis + table extraction) |
| Max | $14.99 | + AI conversion (Granite Docling VLM) |

Downloadable assets and sizes live in `AppTier.swift` (`ModelAsset`). Routing between
capabilities is documented in `docs/release/TIER_AND_ROUTING_POLICY.md`.
