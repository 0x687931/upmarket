# Design System Audit — Outstanding Fixes

## Context for the agent picking this up

### What this is
A prioritised fix list from a full audit of the Upmarket macOS SwiftUI app against its design system spec. Previous passes have already aligned Workbench, Shelf, Welcome, Paywall, Preferences, Model Download, and utility modals. This file covers what remains — gaps found during the post-implementation audit.

### Codebase location
Working directory: `/Users/am/GitHub/upmarket`
Xcode project: `Upmarket/Upmarket.xcodeproj`, scheme `Upmarket`

### Design system bundle location
`/Users/am/Downloads/Upmarket Design System-2/`
- `tokens/colors.css`, `tokens/spacing.css`, `tokens/typography.css` — canonical token values. **When a token file and a JSX prototype disagree, the token file wins** — it explicitly documents itself as mirroring `AppTheme.swift`.
- `components/buttons/Button.jsx`, `ActionIconButton.jsx` — button component specs
- `components/display/Badge.jsx`, `Card.jsx`, `SectionHeader.jsx` — display component specs
- `components/conversion/ArcRing.jsx`, `FileRow.jsx`, `PulseRing.jsx` — conversion component specs
- `ui_kits/upmarket-app/Workbench.jsx`, `Paywall.jsx`, `Welcome.jsx`, `Shelf.jsx` — full-screen specs

### Implementation methodology (apply in this order per fix)
1. **Tokens → Swift constants.** Fix/add `AppTheme` constants first. Don't hardcode values inline in views.
2. **Components → SwiftUI views.** Fix shared components in `Design/` next. A component fix benefits every screen that uses it.
3. **Screens → use the fixed tokens and components.** Update `Views/` last.

### Code patterns already established — follow these exactly
- **Dynamic colour tokens** (light/dark adaptive): use `NSColor` dynamic provider — see the existing `textTertiary` in `AppTheme.Colour` as the template:
  ```swift
  static let textTertiary = Color(nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
          ? NSColor.white.withAlphaComponent(0.30)
          : NSColor.black.withAlphaComponent(0.26)
  })
  ```
- **Static colour tokens:** `Color(red:green:blue:)` with a comment showing the hex, e.g. `// #ff5f57`.
- **Button style `metrics()` tuples:** `(fontSize: CGFloat, verticalPadding: CGFloat, horizontalPadding: CGFloat, minHeight: CGFloat, cornerRadius: CGFloat)` — follow the exact existing tuple shape in `AppProminentButtonStyle` and `AppBorderedButtonStyle`.
- **`AppTheme.Radius`:** static `CGFloat` constants. No fractional values unless the spec is explicit.
- **`AppTheme.Colour`:** grouped by semantic role with a blank line and comment between groups — keep existing grouping style.

### Standing rules
1. **No triage.** Every item in this list must be fixed. Don't defer anything as cosmetic or low priority.
2. **Don't build between every edit.** Make all edits for a logical batch (e.g. all token additions, or all button style fixes), then build once to verify. Don't run a build after each individual file change.
3. **Work through dependency order.** Some items explicitly depend on others (noted in the fix description). Complete dependencies first: T5 before W1, T1 before P1.
4. **Don't touch screens that aren't in this list.** This is a targeted fix pass, not a full re-implementation. Stay in scope.
5. **Don't run or relaunch the app** to verify — use the build command only.
6. **Ignore stale SourceKit diagnostics** ("Cannot find type X in scope" for same-module types) if the build succeeds — known indexing noise.

### Build verification command
```sh
xcodebuild build -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

### Deliverable
When done, for each completed item mark it `[x]` and append a one-line note of what changed. At the end, confirm `** BUILD SUCCEEDED **`.

---

## Audit findings — full findings from the post-implementation audit against:
- `tokens/*.css` → `AppTheme.swift`
- `components/**/*.jsx` → `Design/*.swift`
- `ui_kits/upmarket-app/*.jsx` → `Views/*.swift`

Status key: `[ ]` open · `[x]` done

---

## Token Layer (`AppTheme.swift`)

### T1 — `Radius.appIcon` inconsistently calibrated and unused in WelcomeView
**File:** `Design/AppTheme.swift`, `Views/WelcomeView.swift`, `Views/PaywallView.swift`
**Spec:** `--radius-app-icon: 21.5%` — a percentage of the icon's side length. Applies to both the 64px Paywall icon (21.5% × 64 ≈ 13.76 → 14pt) and the 84px Welcome icon (21.5% × 84 ≈ 18pt).
**Current:** `Radius.appIcon = 14` (calibrated for 64px only). `WelcomeView` hardcodes `cornerRadius: 18` without using the token. `PaywallView` hardcodes `cornerRadius: 14` without using the token either.
**Fix:**
- Add a second token `Radius.appIconLarge: CGFloat = 18` (for 84px+ icons, i.e. Welcome), or alternatively keep `appIcon = 14` for the 64px icon and document it, and add `appIconLarge = 18` for the 84px icon.
- Replace `cornerRadius: 14` in `PaywallView` (line 76) with `AppTheme.Radius.appIcon`.
- Replace `cornerRadius: 18` in `WelcomeView` (line 81 of the `.clipShape`) with `AppTheme.Radius.appIconLarge`.
- [x] done — added `Radius.appIconLarge = 18`; both views now use named tokens

### T2 — `--fill-track` has no named token; `ArcRingView` uses an inline expression
**File:** `Design/AppTheme.swift`, `Design/ArcRingView.swift`
**Spec:** `--fill-track: rgba(0,0,0,0.10)` (light) / `rgba(255,255,255,0.12)` (dark) — the faint background ring behind the progress arc.
**Current:** `ArcRingView` defaults `trackColor` to `Color.primary.opacity(0.1)` inline. This approximates the spec but isn't a named token and doesn't adapt to dark mode's `0.12` opacity.
**Fix:**
- Add `AppTheme.Colour.arcTrack` as a dynamic colour: light = `Color.primary.opacity(0.10)`, dark = `Color.primary.opacity(0.12)`. Use `NSColor` dynamic provider (same pattern as `textTertiary`).
- Update `ArcRingView`'s default `trackColor` parameter to `AppTheme.Colour.arcTrack`.
- [x] done — added `Colour.arcTrack` dynamic NSColor token; ArcRingView default updated

### T3 — Status banner nudge tint hardcodes a non-token opacity value
**File:** `Views/ContentView.swift` (approx. line 230)
**Spec:** `--accent-06` / `accentTint06` for non-error free-trial banners.
**Current:** `Color.accentColor.opacity(0.07)` for the nudge banner tint — 0.07 is neither `accentTint06` (0.06) nor `accentTint08` (0.08) and has no spec basis.
**Fix:** Replace `Color.accentColor.opacity(0.07)` with `AppTheme.Colour.accentTint06`.
- [x] done — ContentView nudge banner tint changed to `accentTint06`

### T4 — Workbench titlebar traffic-light colors are raw hex; should be named tokens
**File:** `Views/ContentView.swift` `workbenchTitlebar` (approx. lines 86–93), `Design/AppTheme.swift`
**Spec:** The same three colors (`#ff5f57`, `#febc2e`, `#28c840`) are already tokens for the Shelf control strip (`shelfHoverClose`, `shelfHoverAdd`, `shelfHoverToggle`), but the titlebar uses its own inline `Color(red:green:blue:)` literals.
**Current values vs spec:**
- Red: `Color(red: 1.0, green: 0.372, blue: 0.341)` = `#FF5F57` ✅
- Yellow: `Color(red: 0.996, green: 0.737, blue: 0.180)` = `#FEBC2E` ✅
- Green: `Color(red: 0.157, green: 0.784, blue: 0.251)` = `#28C840` ✅
**Fix:**
- Add three tokens to `AppTheme.Colour`:
  ```swift
  static let trafficRed    = Color(red: 1.0,   green: 0.373, blue: 0.341) // #ff5f57
  static let trafficYellow = Color(red: 0.996, green: 0.737, blue: 0.180) // #febc2e
  static let trafficGreen  = Color(red: 0.157, green: 0.784, blue: 0.251) // #28c840
  ```
- Replace the three inline `Color(red:green:blue:)` literals in `workbenchTitlebar` with these tokens.
- Note: the same colors are used in `Shelf.jsx`'s strip buttons — `shelfHoverClose/Add/Toggle` already approximate them. Check whether `shelfHoverClose` and `trafficRed` should be the same token (they are the same hex value, just different names/contexts). If so, unify them rather than adding duplicates.
- [x] done — added `trafficRed/Yellow/Green`; `shelfHoverClose/Add` now alias them; titlebar uses named tokens

### T5 — `--surface` (white card surface) has no Swift token; workbench titlebar uses wrong fill
**File:** `Design/AppTheme.swift`, `Views/ContentView.swift`
**Spec:** `--surface: #ffffff` (light) / `#282828` (dark) — the card/sheet/popover surface, distinct from `--window-bg: #ececec` (the window chrome background). The Workbench titlebar spec uses `background: var(--surface)`.
**Current:** No `surface` token in `AppTheme`. `workbenchTitlebar` uses `AppTheme.Colour.background` (`NSColor.windowBackgroundColor` ≈ `#ececec` on light) which is the window-chrome grey, not the white card surface. The titlebar therefore renders slightly too dark vs spec.
**Fix:**
- Add `AppTheme.Colour.surface = Color(nsColor: .controlBackgroundColor)` — `NSColor.controlBackgroundColor` adapts white (light) / dark (#2c2c2e dark), which is the closest system color to `--surface`.
- Use `AppTheme.Colour.surface` in `workbenchTitlebar`'s `.background(...)`.
- [x] done — added `Colour.surface = controlBackgroundColor`; titlebar background updated

---

## Component Layer

### C1 — Button font sizes wrong for mini/small/regular in both Prominent and Bordered styles
**File:** `Design/AppButtonStyle.swift`
**Spec (`Button.jsx` sizes):**
| Size | Font token | pt value |
|---|---|---|
| mini | `--text-caption` | 10pt |
| small | `--text-subheadline` | 11pt |
| regular | `--text-body` | 13pt |
| large | `--text-headline` | 13pt ✅ (correct) |

**Current `AppProminentButtonStyle`:**
| Size | Current fontSize | Should be |
|---|---|---|
| mini | 12 ❌ | 10 |
| small | 13 ❌ | 11 |
| regular | 14 ❌ | 13 |
| large | 13 ✅ | — |

**Current `AppBorderedButtonStyle`:**
| Size | Current fontSize | Should be |
|---|---|---|
| mini | 12 ❌ | 10 |
| small | 13 ❌ | 11 |
| regular | 14 ❌ | 13 |
| large | 15 ❌ | 13 |

**Fix:** Update `metrics(for:)` in both styles to use the correct sizes. Also verify `minHeight` values against the spec's implicit row heights (mini→20, small→24, regular→28, large→36) — these appear to already match.
- [x] done — Prominent: mini→10, small→11, regular→13; Bordered: same + large→13

### C2 — `AppActionButtonStyle` missing resting opacity
**File:** `Design/AppButtonStyle.swift`
**Spec (`ActionIconButton.jsx`):** `opacity: 0.82` on the whole button tile at rest; lifts to `1` on hover (`onMouseEnter`); returns to `0.82` on leave. The pressed state also gets `transform: scale(0.94)`.
**Current:** Only the foreground label gets dimmed (`.foregroundStyle(.primary.opacity(0.78))` at rest). The tile itself has no resting opacity — it appears at full opacity, making action buttons look heavier than spec.
**Fix:**
- Add `.opacity(configuration.isPressed ? 1 : 0.82)` to the tile in `makeBody`. On press, opacity goes to 1 (brightest) to reinforce the "activated" feel alongside `scaleEffect`.
- Add `.scaleEffect(configuration.isPressed ? 0.94 : 1)` (currently missing; the spec has `transform: scale(0.94)` on mousedown).
- [x] done — added resting `opacity(0.82)` and `scaleEffect(0.94)` on press to AppActionButtonStyle

### C3 — `AppBadge` font weight for `.accent` variant is too light
**File:** `Design/AppBadge.swift`
**Spec (`Badge.jsx` base):** `font: var(--weight-heavy) var(--text-caption)/1 var(--font-sans)` — `--weight-heavy: 800`.
**Current:** `.caption2.weight(.semibold)` = 600 weight. SwiftUI equivalent of 800 is `.weight(.heavy)`.
**Fix:** Change `.caption2.weight(.semibold)` to `.caption2.weight(.heavy)` for the `.accent` variant specifically. Keep `.semibold` for `.neutral` and `.count` variants (which have no weight-heavy spec requirement).
- [x] done — `.accent` badge now uses `.heavy` weight via switch on variant

### C4 — `AppSectionCard` section header uses `.secondary` instead of `textTertiary`
**File:** `Design/AppSectionCard.swift`
**Spec (`SectionHeader.jsx`):** `color: var(--text-tertiary)` — the uppercase section label is dimmer than secondary text.
**Current:** `.foregroundStyle(.secondary)` — SwiftUI's `.secondary` is `rgba(0,0,0,0.50)`, but spec's `--text-tertiary` is `rgba(0,0,0,0.26)` (much dimmer, more appropriate for a background organizational label).
**Fix:** Replace `.foregroundStyle(.secondary)` on the section title text with `.foregroundStyle(AppTheme.Colour.textTertiary)`.
- [x] done — AppSectionCard title now uses `textTertiary`

---

## Workbench Screen (`ContentView.swift` vs `Workbench.jsx`)

### W1 — Titlebar background colour is window-grey, should be white card surface
*(Blocked on T5 — implement T5 first, then this is a one-line change.)*
**File:** `Views/ContentView.swift` `workbenchTitlebar`
**Spec:** `background: var(--surface)` (#ffffff light).
**Current:** `AppTheme.Colour.background` (`NSColor.windowBackgroundColor` ≈ `#ececec`).
**Fix:** `.background(AppTheme.Colour.surface)` (after T5 adds that token).
- [x] done — titlebar background is now `AppTheme.Colour.surface`

### W2 — Empty-state queue gap is 12pt, spec says 10pt
**File:** `Views/ContentView.swift` `queueListView` empty branch
**Spec:** `gap: 10` between the tray icon and the text rows.
**Current:** `VStack(spacing: AppTheme.Spacing.md)` = 12pt.
**Fix:** `VStack(spacing: 10)` — 10 is not a standard token step (4/8/12/16…), so use the literal `10` rather than inventing a new token for a single use.
- [x] done — empty-state VStack spacing changed from `Spacing.md` (12) to literal `10`

### W3 — Empty-state caption and other `.tertiary` usages should use `textTertiary` token
**File:** `Views/ContentView.swift` (empty queue "Drop files above…" text, approx. line 188)
**Spec:** `color: var(--text-tertiary)`.
**Current:** `.foregroundStyle(.tertiary)` — SwiftUI's built-in `.tertiary` is implementation-defined and may not match `rgba(0,0,0,0.26)` exactly.
**Fix:** `.foregroundStyle(AppTheme.Colour.textTertiary)`. Audit the whole file for other `.tertiary` occurrences and apply the same fix.
- [x] done — empty-state caption now uses `textTertiary`; no other `.tertiary` in ContentView

### W4 — Status banner icon font size is too small
**File:** `Views/ContentView.swift` `bannerRow(icon:text:action:tint:iconColor:)`
**Spec (`Workbench.jsx` banner row):** `fontSize: 13` for the leading icon.
**Current:** `.font(.caption)` ≈ 10pt.
**Fix:** `.font(.system(size: 13))` on the `Image(systemName: icon)`.
- [x] done — banner icon font changed from `.caption` to `.system(size: 13)`

---

## Paywall Screen (`PaywallView.swift` vs `Paywall.jsx`)

### P1 — App icon `cornerRadius` hardcoded; should use `AppTheme.Radius.appIcon`
**File:** `Views/PaywallView.swift` (approx. line 76)
**Current:** `.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))` — 14 is correct but hardcoded.
**Fix:** `.clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.appIcon, style: .continuous))` — already equals 14, just uses the token. *(Depends on T1 keeping `appIcon = 14` for the 64px icon.)*
- [x] done — PaywallView icon clipShape uses `AppTheme.Radius.appIcon`

### P2 — Tier price font is one size too large
**File:** `Views/PaywallView.swift` `tierCard` (approx. line 155)
**Spec:** `font: var(--weight-bold) var(--text-title3)/1` = title3 (15pt), bold.
**Current:** `.font(.title2).fontWeight(.bold)` = title2 (17pt) — one semantic step larger.
**Fix:** `.font(.title3).fontWeight(.bold)`.
- [x] done — tier price font changed from `.title2` to `.title3`

### P3 — Feature row checkmark icon is too small
**File:** `Views/PaywallView.swift` `featureRow(_:isHighlight:)` (approx. line 274)
**Spec:** `fontSize: 14` for the `ph-check-circle` icon.
**Current:** `.font(.caption)` ≈ 10pt.
**Fix:** `.font(.system(size: 14))`.
- [x] done — feature row checkmark font changed from `.caption` to `.system(size: 14)`

### P4 — Restore Purchases button renders at caption size; spec wants subheadline
**File:** `Views/PaywallView.swift` `restoreButton`, `Design/AppButtonStyle.swift` `AppPlainButtonStyle`
**Spec:** `font: var(--weight-medium) var(--text-subheadline)/1` = 11pt medium.
**Current:** `AppPlainButtonStyle` uses `AppTheme.Font.caption.weight(.medium)` = 10pt. The style does not respond to `controlSize`.
**Fix:** Change `AppPlainButtonStyle.makeBody` to use `AppTheme.Font.body.weight(.medium)` (= `.subheadline.weight(.medium)`, 11pt) as the base, OR make it respect `@Environment(\.controlSize)` like the other styles. Given it's only used in a few places (Paywall restore, AISuggestion) at effectively the same context, simply lifting to `.body` (= 11pt subheadline) is cleanest.
- [x] done — AppPlainButtonStyle font changed from `caption` to `body` (11pt subheadline)

### P5 — Legal footer uses `.caption2` (too small) and `.tertiary` (wrong token)
**File:** `Views/PaywallView.swift` `legalFooter`
**Spec:** `font: var(--text-caption)/1.4` = caption (10pt); `color: var(--text-tertiary)`.
**Current:** `.font(.caption2)` ≈ smaller than caption; `.foregroundStyle(.tertiary)` instead of `textTertiary` token.
**Fix:** `.font(.caption)` and `.foregroundStyle(AppTheme.Colour.textTertiary)`.
- [x] done — legal footer font lifted to `.caption`; color changed to `textTertiary`

### P6 — Tier card vertical padding is 12pt; spec says 14pt
**File:** `Design/AppButtonStyle.swift` `AppCardStyle.makeBody` (the `.padding` call)
**Spec (`Tier` button in `Paywall.jsx`):** `padding: "14px 16px"` — 14pt vertical, 16pt horizontal.
**Current:** `AppCardStyle` uses `AppTheme.Spacing.lg` (16) horizontal and `AppTheme.Spacing.md` (12) vertical.
**Fix:** Change vertical padding in `AppCardStyle` from `AppTheme.Spacing.md` to `14` (literal — no 14pt token exists; this is a one-off spec value that doesn't warrant a new spacing token).
- [x] done — AppCardStyle vertical padding changed from `Spacing.md` (12) to literal `14`

### P7 — App icon second shadow radius and offset are slightly off
**File:** `Views/PaywallView.swift` header icon shadow (approx. lines 77–78)
**Spec:** `--shadow-card: 0 1px 3px rgba(0,0,0,0.08), 0 6px 18px rgba(0,0,0,0.08)`
**Current:**
- First shadow: `radius: 3, y: 1` ✅
- Second shadow: `radius: 12, y: 4` ❌ — should be `radius: 18, y: 6`
**Fix:** `.shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 6)` for the second shadow.
- [x] done — second shadow corrected to `radius: 18, y: 6`

---

## Cross-cutting

### X1 — Remaining `.foregroundStyle(.tertiary)` usages across all views
After fixing W3 and P5, do a final grep across all Views for `.foregroundStyle(.tertiary)` and `.foregroundStyle(Color.secondary.opacity(...)` where the intent is `--text-tertiary`, and replace with `AppTheme.Colour.textTertiary`.

```sh
grep -rn "\.tertiary" Upmarket/Upmarket/Views/
```

Each hit should be reviewed: some uses of `.tertiary` are correct (genuinely quaternary/very dim UI elements where the distinction doesn't matter); replace only where spec explicitly calls for `--text-tertiary`.
- [x] done — grep confirms zero `.tertiary` usages remain in Views/

### X2 — Build verification
After all fixes above, run once:
```sh
xcodebuild build -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```
- [x] BUILD SUCCEEDED
