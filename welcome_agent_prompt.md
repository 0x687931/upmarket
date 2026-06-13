# Task: Align WelcomeView.swift with the design system spec

## Context

Upmarket is a macOS app (SwiftUI). We are implementing a design system across the app, one screen at a time. This task covers the **Welcome / first-launch onboarding window** (`WelcomeWindowController` / `WelcomeView.swift`).

The design system bundle lives at `/Users/am/Downloads/Upmarket Design System-2/`. Treat it as a **living spec**, not a code generator:
- `tokens/*.css` — canonical design tokens. These files explicitly document themselves as mirroring `AppTheme.swift` enums (Spacing, Radius, Size, Colour, Font, Status). **When a token file and a JSX prototype disagree, the token file wins** (it's the source of truth for values already in AppTheme).
- `ui_kits/upmarket-app/Welcome.jsx` — the full-screen spec for this window. Read it in full before starting.
- `tokens/spacing.css`, `tokens/colors.css`, `tokens/typography.css` — check these for radius, shadow, and color tokens referenced below.

The relevant Swift files:
- `Upmarket/Upmarket/Views/WelcomeView.swift` — main work area (also contains `WelcomeWindowController`)
- `Upmarket/Upmarket/Design/AppTheme.swift` — tokens (Spacing, Radius, Size, Colour, Font, WindowSize)
- `Upmarket/Upmarket/Design/AppButtonStyle.swift` — `AppProminentButtonStyle` (used by "Get Started")

## Standing instructions (do not deviate)

1. **No triage. Full implementation.** Do not categorize findings as "cosmetic," "low priority," or "nice to have," and do not defer them. If you find a deviation from the spec, fix it as part of this task.
2. **Methodology — work in this order:**
   - **Tokens → Swift constants.** First check `AppTheme.swift` against the relevant token CSS files for anything Welcome-specific that's missing (e.g. a 10px radius token for feature-icon boxes, a `textTertiary` color token). Add/fix constants in `AppTheme` rather than hardcoding values inline in `WelcomeView.swift`.
   - **Components → SwiftUI views.** Cross-reference `AppProminentButtonStyle` against `Button.jsx`'s `variant="prominent" size="large"` for visual parity (this was already aligned in a prior pass — verify it still holds, don't re-derive from scratch).
   - **UI kit → SwiftUI screen.** Then go through `Welcome.jsx` top-to-bottom and reconcile `WelcomeView.swift` against it: window chrome (border/shadow/corner radius), spacing, typography, colors, icon styling.
3. **Don't break the build.** Verify with:
   ```sh
   xcodebuild build -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
   ```
   Ignore stale SourceKit "Cannot find type X in scope" diagnostics for same-module types if the build above succeeds — these are known indexing noise, not real errors.
4. **Don't rebuild/run the app repeatedly** — verify via the build command above, not by relaunching the app, unless visual verification is truly necessary.
5. **Stay in scope.** Only touch `WelcomeView.swift`, `AppTheme.swift`, and (only if a real bug is found) `AppButtonStyle.swift`. Don't touch other screens.

## Known discrepancies already identified (fix all of these, plus anything else you find)

### Window chrome

1. **Missing card chrome on the window content.** `Welcome.jsx` specifies the whole window as a card: `borderRadius: 12`, `background: var(--surface)`, `border: 0.5px solid var(--separator)`, `boxShadow: var(--shadow-window)` (`0 24px 64px rgba(0,0,0,0.28)`, from `tokens/spacing.css`). The current `WelcomeView.body` is just `ZStack { AppTheme.Colour.background; content }` filling the window with no rounded corners, border, or shadow — and `WelcomeWindowController` creates the window with `.titled, .closable, .fullSizeContentView` + transparent titlebar, so the content view's edges ARE the window's visible edges.
   - Fix: give the root `ZStack` (or its background) a `RoundedRectangle(cornerRadius: AppTheme.Radius.md)` clip/fill, a `0.5px` `AppTheme.Colour.separator` border (`.strokeBorder`), and a shadow matching `--shadow-window`. Note: `AppTheme.Colour.background` (`NSColor.windowBackgroundColor`) vs the spec's `--surface` (`#ffffff` light / `#282828` dark) — check `tokens/colors.css` for whether `--surface` already maps to an existing AppTheme color (it may correspond to a "card surface" token used elsewhere); if no equivalent exists, decide whether `AppTheme.Colour.background` is close enough or whether a new `AppTheme.Colour.surface` token should be added (check other screens — e.g. modals — for precedent before adding a new token).
   - Verify the shadow renders correctly given `NSWindow` is `.titled` with a transparent titlebar — you may need `window.isOpaque = false` / `window.backgroundColor = .clear` on the `NSWindow` itself for the rounded corners + shadow to be visible against the desktop (be careful: a prior attempt to make the *main* window borderless/clear broke it because the window background was changed without implementing the rounded content properly — don't repeat that mistake; test carefully, and if AppKit's window chrome makes a true rounded card impossible without regressions, document that tradeoff rather than leaving the window in a broken state).

### Header (icon + headline)

2. **App icon radius/shadow** — current code uses `clipShape(RoundedRectangle(cornerRadius: 18))` + two manual shadows (`black.opacity(0.08)`, radius 3/y1 and radius 18/y6). Verify against `tokens/spacing.css`: `--radius-app-icon: 21.5%` of `--size-app-icon: 96px` ≈ 18px (current 18 is correct for an 84px icon at ~21.5%, double check the ratio holds for the 84px size used here vs. the 96px token reference), and `--shadow-card: 0 1px 3px rgba(0,0,0,0.08), 0 6px 18px rgba(0,0,0,0.08)` — current two shadows already match these values. **This item is likely already correct** — confirm and leave as-is unless you find a real discrepancy.

3. **Headline letter-spacing.** `Welcome.jsx`: `font: var(--weight-bold) var(--text-large-title)/1.15 var(--font-rounded)`, `letterSpacing: -0.4px`. Current uses `AppTheme.Font.heroRounded` (`.largeTitle, design: .rounded, weight: .bold`) with no tracking. Add `.tracking(-0.4)` to the headline `Text`.

4. **Subtitle line-height/color** — `Welcome.jsx`: `text-title3/1.4`, color `var(--text-secondary)`. Current uses `AppTheme.Font.title3` + `.foregroundStyle(.secondary)` (color matches). Consider `.lineSpacing(...)` to approximate the 1.4 line-height if the subtitle text wraps to two lines — check visually/via reasoning whether it currently wraps at 520pt width; if it's single-line, line-height is moot and no change is needed (don't add unnecessary `.lineSpacing` to single-line text).

### Feature rows

5. **First feature icon color.** `Welcome.jsx`: `Feat color="#2f7fff"` for "PDFs, Word, PowerPoint and more". Current uses `.blue` (SwiftUI system blue, `#007AFF`-ish), which is a different blue than the `#2f7fff` used elsewhere (already added as `AppTheme.Colour.iconGlyphTint` in a prior pass for FileRow/Shelf). Change `.blue` → `AppTheme.Colour.iconGlyphTint` for consistency across the app.

6. **Feature icon box corner radius.** `Welcome.jsx`'s `Feat` icon box: `borderRadius: 10`. Current uses `AppTheme.Radius.md` (12px). `AppTheme.Radius` only defines `sm` (8) and `md` (12) — no 10px token exists. Decide: either (a) add a new `AppTheme.Radius` token (e.g. `featureIcon: CGFloat = 10`) if 10px recurs as a deliberate spec value across multiple components, or (b) treat 12 as close enough / the canonical value if `AppTheme.Radius.md`'s doc comment ("cards, sheets, shelf — the default") suggests it's meant to cover this case too. Check whether other already-completed screens (main window, Shelf) encountered the same 10-vs-12 question and what was decided (the Shelf work used `AppTheme.Radius.md` for a 10px spec value, reasoning that 12 is the documented default and no 10px token exists) — **for consistency, follow the same precedent here** unless you find a strong reason not to.

7. **Feature icon box background opacity** — `color-mix(in srgb, <color> 12%, transparent)` = `color.opacity(0.12)`. Current already uses `.opacity(0.12)`. **Already correct** — confirm and leave as-is.

8. **Feature detail text color/line-height** — `Welcome.jsx`: `text-caption/1.35`, `color: var(--text-secondary)`. Current: `AppTheme.Font.caption` + `.foregroundStyle(.secondary)` with `.fixedSize(horizontal: false, vertical: true)` (allows wrapping). Color matches. Line-height 1.35 — consider `.lineSpacing(...)` only if the detail text visibly wraps to multiple lines and the spacing looks cramped; otherwise leave as-is (don't add speculative line-spacing).

### Footer / CTA

9. **"3 free conversions" caption color.** `Welcome.jsx`: `color: var(--text-tertiary)` (`rgba(0,0,0,0.26)` light / `rgba(255,255,255,0.30)` dark, per `tokens/colors.css`). Current uses SwiftUI's built-in `.foregroundStyle(.tertiary)`. SwiftUI's `.tertiary` is a system-defined opacity tier that may not exactly equal `rgba(0,0,0,0.26)`/`rgba(255,255,255,0.30)`. Check `AppTheme.Colour` for an existing tertiary-text token (there isn't one currently); if other in-progress/completed screens have already established a `textTertiary`-equivalent token for this exact value, reuse it for consistency — otherwise add `AppTheme.Colour.textTertiary` (light: `Color.black.opacity(0.26)`, with the system handling dark mode via `Color(nsColor:...)` if a suitable dynamic NSColor exists, or a `Color` that adapts via asset catalog / `@Environment(\.colorScheme)` — keep it simple, mirror how other "secondary"/"tertiary" tokens in `AppTheme.Colour` are already implemented) and use it here.

10. **Button width 220, gap 12** — `Welcome.jsx`: `Button` width 220, footer column `gap: 12`. Current: `.frame(width: 220)` on the button label, `VStack(spacing: AppTheme.Spacing.md)` (12). **Already correct** — confirm and leave as-is.

### Overall layout

11. **Padding** — `Welcome.jsx`: `padding: "42px 44px 34px"` (top 42, sides 44, bottom 34). Current: `.padding(.top, 42).padding(.horizontal, 44).padding(.bottom, 34)`. **Already correct** — confirm and leave as-is.

12. **Vertical distribution** — `Welcome.jsx` uses `justify-content: space-between` across three sections (header / features / footer) in a fixed 520×540 container. Current uses two `Spacer()`s between the three VStack sections inside the same padded frame, which should produce equivalent distribution. Verify visually/structurally that this still holds once item 1's card chrome (border + padding from the border) is added — the effective content area may shrink slightly and could need the `Spacer()`s rebalanced, or it may be a non-issue. Don't over-adjust if it already looks right.

## Deliverable

When done, provide a short handoff summary:
- List of files changed and what changed in each (token additions to `AppTheme.swift`, the `WelcomeView.swift` changes, and `WelcomeWindowController` changes if the window-chrome fix in item 1 required NSWindow-level changes).
- Confirmation the build succeeds (`xcodebuild build ...` as above, paste the final "BUILD SUCCEEDED" line).
- Any spec ambiguities you resolved via judgment calls (e.g. items 1, 6, 9), with your reasoning, so the user can review.
- Any remaining open questions you deliberately did NOT resolve (should be none, per the "no triage" rule — but flag anything truly blocked, e.g. a window-chrome change that risks regressing the window like the prior MainWindowController incident).
