# Upmarket User Flow

This document describes the intended user journey for the shelf-first macOS app.
It is the reference flow for onboarding, conversion, purchase prompts, and menu
bar recovery.

## Entry Points

- First launch: the app starts as an accessory app, shows the shelf, then starts
  the guided tour if `upmarket.tourComplete` is not set.
- Menu bar: the `#` status item opens the dropdown and can reopen the shelf.
- Finder / Services / Quick Action: incoming files are routed to the shelf through
  the `upmarket://convert` handler or Services menu.
- Keyboard: `Cmd+O` opens the file picker, and `Cmd+Shift+S` toggles the shelf.

## First Launch Tour

1. App initializes services and the embedded Python bridge.
2. Shelf appears near the saved screen corner.
3. Tour panel explains the product: local document-to-Markdown conversion.
4. Tour expands the shelf and points at:
   - `>` expand shelf
   - `+` add files
   - drag-to-corner shelf positioning
   - menu bar `#` recovery/status entry point
   - `x` hide shelf
5. Finishing or skipping the tour marks `upmarket.tourComplete`.
6. The paywall/licensing window is shown after the tour.

## Conversion Flow

1. User adds a file with `+`, drag and drop, Quick Action, or Services.
2. Shelf checks `StoreManager.canConvert`.
3. If access is available:
   - a free conversion or pack credit is consumed when applicable
   - the file is copied to a sandbox-safe temp URL
   - `ConversionService` starts conversion
   - menu bar and Dock status receive conversion-start notifications
4. Conversion runs through the local Swift/Python pipeline.
5. Shelf updates the item state:
   - success: show title/result actions
   - failure: show retry/error state
6. When all queued work finishes, conversion-ended notifications stop status
   animation.

## Licensing Flow

1. Free tier starts with 3 document conversions.
2. Trial state is document-count based, not time based:
   - 3 remaining: full trial
   - 1 remaining: trial nearly over
   - 0 remaining: trial expired
3. Users can buy:
   - Basic: unlimited non-AI conversions
   - Pro: unlimited conversions plus AI features
   - Doc pack: 5 additional conversions
4. After a conversion finishes, the paywall is shown at useful milestones:
   once when 1 free conversion remains, and once when 0 remain.
5. Any conversion attempt without access opens the paywall.
6. The tour completion also opens the paywall as a standalone window.
7. Purchase completion refreshes entitlement state and closes the standalone
   paywall window.

## Menu Bar Flow

1. Idle icon adapts to light/dark menu bar appearance.
2. Converting state changes the icon rendering and animation.
3. Dropdown gives status, shelf recovery, preferences, version, and quit.
4. The menu bar remains available after the shelf is hidden.

## Persistence

- `upmarket.tourComplete`: first-launch tour state.
- `upmarket.shelfAnchor`: saved shelf corner.
- `upmarket.freeDocsRemaining`: free conversion count.
- `upmarket.packCredits`: remaining pack credits.
- `upmarket.packsEverPurchased`: upgrade nudge history.
- Model files live under `~/Library/Application Support/Upmarket/models/`.
