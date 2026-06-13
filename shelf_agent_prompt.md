# Task: Align ShelfView.swift with the design system spec

## Context

Upmarket is a macOS app (SwiftUI). We are implementing a design system across the app, one screen at a time. The "Shelf" is the small floating widget (`ShelfWindowController` / `ShelfView.swift`) that can be collapsed (peek) or expanded (queue) to show conversion jobs.

The design system bundle lives at `/Users/am/Downloads/Upmarket Design System-2/`. Treat it as a **living spec**, not a code generator:
- `tokens/*.css` — canonical design tokens. These files explicitly document themselves as mirroring `AppTheme.swift` enums (Spacing, Radius, Size, Colour, Font, Status). **When a token file and a JSX prototype disagree, the token file wins** (it's the source of truth for values already in AppTheme).
- `ui_kits/upmarket-app/Shelf.jsx` — the full-screen spec for this widget. Read it in full before starting.
- `components/display/Badge.jsx` and `components/buttons/ActionIconButton.jsx` — shared component specs referenced by Shelf.jsx.

The relevant Swift files:
- `Upmarket/Upmarket/Views/ShelfView.swift` (932 lines) — main work area
- `Upmarket/Upmarket/Design/AppTheme.swift` — tokens (Spacing, Radius, Size, Colour, Status)
- `Upmarket/Upmarket/Design/AppStatusToken.swift` — the check/cross badge component (currently a plain colored circle with inline-SVG check/cross glyph, no white border ring)
- `Upmarket/Upmarket/Design/AppButtonStyle.swift` — `AppActionButtonStyle` (`.regular` and `.compact` sizes)
- `Upmarket/Upmarket/Design/ArcRingView.swift` — progress ring component

## Standing instructions (do not deviate)

1. **No triage. Full implementation.** Do not categorize findings as "cosmetic," "low priority," or "nice to have," and do not defer them. If you find a deviation from the spec, fix it as part of this task. The whole point of this pass is to close every gap, however small.
2. **Methodology — work in this order:**
   - **Tokens → Swift constants.** First check `AppTheme.swift` against the relevant token CSS files (`tokens/colors.css`, `tokens/spacing.css`, etc.) for anything Shelf-specific that's missing (e.g. control-strip hover colors, badge ring width). Add/fix constants in `AppTheme` rather than hardcoding values inline in `ShelfView.swift`.
   - **Components → SwiftUI views.** Cross-reference `AppStatusToken`, `ArcRingView`, `AppActionButtonStyle` against `Badge.jsx`, `ArcRing.jsx`/`PulseRing.jsx`, and `ActionIconButton.jsx` for full visual parity (sizes, colors, borders, states). Fix the shared components, not just Shelf's usages.
   - **UI kit → SwiftUI screen.** Then go through `Shelf.jsx` top-to-bottom and reconcile `ShelfView.swift` against it: layout, spacing, colors, borders, backgrounds, states (peek/queue, idle/active, hover where applicable on macOS).
3. **Don't break the build.** Verify with:
   ```sh
   xcodebuild build -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
   ```
   Ignore stale SourceKit "Cannot find type X in scope" diagnostics for same-module types if the build above succeeds — these are known indexing noise, not real errors.
4. **Don't rebuild/run the app repeatedly** — verify via the build command above, not by relaunching the app, unless visual verification is truly necessary.
5. **Stay in scope.** Only touch Shelf-related files (`ShelfView.swift`, `ShelfWindowController.swift`, shared Design/ components used by Shelf, `AppTheme.swift`). Don't touch other screens (main window, menu bar, welcome, paywall, etc.) — those are separate passes.

## Known discrepancies already identified (fix all of these, plus anything else you find)

### Tokens / shared components

1. **`AppStatusToken` needs a "Badge" variant matching `Badge.jsx`'s status indicator used on Shelf cards**: 15×15 circle, `background: color`, **`border: 1.5px solid #fff`** (white ring), containing a 9×9 inline-SVG glyph — checkmark path `M2.5 6.2L4.9 8.6L9.5 3.6` or cross path `M3.2 3.2L8.8 8.8M8.8 3.2L3.2 8.8`, both white, stroke-width 1.9. The current `AppStatusToken` (in `Design/AppStatusToken.swift`) draws the circle + glyph but has **no white border ring** option. Add a parameter (e.g. `ringWidth: CGFloat = 0` or a `hasWhiteRing: Bool`) so Shelf can request the 1.5px white ring at size 15, while the main-window usage (size 20, no ring) is unaffected. Match stroke width to 1.9 (currently 1.8 — check both spec instances and reconcile, but don't change main-window's existing look if it was deliberately matched to FileRow.jsx's 1.8).

2. **`AppActionButtonStyle.compact` sizing is wrong.** Per `ActionIconButton.jsx`: `box = size + 10` where 10 = 2× the padding (i.e. padding = 5 on each side, regardless of icon size). Currently:
   - `.regular` → `(fontSize: 11, padding: 5)` → box = 21 ✓ (already correct, fixed in a prior pass)
   - `.compact` → `(fontSize: 9, padding: 3)` → box = 15 ✗ should be `(fontSize: 9, padding: 5)` → box = 19

   Fix `.compact`'s padding to `5` in `Design/AppButtonStyle.swift`. `ShelfItemView.actionRow` uses `AppActionButtonStyle(size: .compact)` extensively — verify the resulting larger buttons still fit the card layout (`ShelfCard` is 96px wide when running / 72px when done per spec — check the action row doesn't overflow at the new size, and adjust `ShelfItemView`'s spacing if needed to match `Shelf.jsx`'s `ShelfCard` padding `10px 8px` and gap).

### Control strip (`controlStrip` in ShelfView.swift)

3. **Hover colors are incomplete.** `Shelf.jsx`'s `StripBtn` specifies three distinct hover fill colors:
   - Close/X (`✕`) → `#ff5f57` (red) — **already correct** in current code
   - Add/`+` → `#28c840` (green) — currently uses `Color(nsColor: .labelColor)` (wrong)
   - Toggle/caret → `#2f7fff` (blue) — currently uses `Color(nsColor: .labelColor)` (wrong)

   Add these as named colors in `AppTheme.Colour` (e.g. `shelfHoverClose`, `shelfHoverAdd`, `shelfHoverToggle`) rather than hardcoding hex in ShelfView, and apply them in `controlButton()`/`controlStrip`.

4. **Control strip background is missing.** `Shelf.jsx` control strip has `background: rgba(255,255,255,0.25)` over its full height — current code has no background fill for the strip. Add this (as an `AppTheme.Colour` token, e.g. `shelfControlStripFill`) and apply it to the full-height control strip container.

5. **Control strip divider doesn't match spec.** Current code draws a 1px `Color.primary.opacity(0.07)` divider at `closedHeight * 0.6` height (i.e. partial height). Spec is `borderRight: 0.5px solid var(--separator)` spanning the **full height** of the control strip. Use `AppTheme.Colour.separator` at `0.5px` width, full height.

### Peek panel (`peekJobView`, `peekIdleView`)

6. **Glyph color mismatch.** `peekGlyph` in `peekJobView` currently uses `.primary.opacity(0.6)`. Spec (`Shelf.jsx` peek panel glyph) is `#2f7fff` — same blue used for FileRow's icon glyph, already added as `AppTheme.Colour.iconGlyphTint` in a prior pass. Use that token.

7. **`peekIdleView` is richer than spec** — currently a `TimelineView`-driven floating arrow-down animation with "Drop files here"/"Release to convert" text. Spec's `Idle()` is simpler: static "Drop documents here" caption + `ph-arrow-down-circle` icon (20px) with a 3s ease-in-out infinite float animation (`upm-float`). Decide whether to simplify to match spec exactly or keep the richer state-aware version (drop vs idle) — **if you simplify, preserve the existing drag-and-drop active-state feedback** (don't regress functionality for visual parity). If the current behavior is intentionally richer than the static mockup and still visually consistent (same icon, same float animation, same caption styling), it's acceptable to keep — use your judgment but document the choice in your handoff notes.

### Expanded view — `ShelfItemView` / `ShelfCard`

8. **Card has no background/border.** Current `ShelfItemView` is a bare `VStack` with padding, relying only on the shelf's overall glass background. Spec's `ShelfCard`: `background: rgba(255,255,255,0.5)`, `border: 0.5px solid var(--separator)`, `borderRadius: 10`, `padding: "10px 8px"`. Add this card surface — use `AppTheme.Colour.separator` for the border and `AppTheme.Radius.md` (12, closest token) or check if there's a more exact radius token for `10px`; add one to `AppTheme.Radius` if needed mirroring the token files. For the `rgba(255,255,255,0.5)` fill, check `colors.css` for an existing token (e.g. something like `glassFillThin`/`glassFill` at the right opacity) before adding a new one — prefer reuse.

9. **`fileGlyph` color** in `iconWithArc` — currently `.primary.opacity(0.6)` at 16px. Spec: `#2f7fff` (16px, size matches). Use `AppTheme.Colour.iconGlyphTint`.

10. **`stateIndicator` badge** — apply the new `AppStatusToken` white-ring variant (from item 1) at size 15, anchored bottom-trailing on the 40px `iconWithArc` ring per spec (`right:-3, bottom:-3` relative to the 40px ring — current `.offset(x:11,y:11)` against a 40px ring puts the badge center near the bottom-right corner; verify the offset still looks correct once the badge gains a white ring at the same 15px size, adjust if needed).

### Overflow / Clear Done

11. **`overflowBadge` fill** — current uses `AppTheme.Colour.glassFillThin` for the stacked 38×48 cards. Spec: `rgba(255,255,255,0.55)`. Check `colors.css` for the closest matching token (may already exist as a named token at 0.55 opacity); if not present, add one to `AppTheme.Colour` and use it here (and consider whether `ShelfCard`'s 0.5-opacity fill from item 8 should share/relate to this token).

12. **`clearDoneButton`** — verify against spec's `ClearDone`: 30×30 circle, `border: 0.5px solid var(--border)` (→ `AppTheme.Colour.border`), `background: var(--glass-fill-thin)` (→ `AppTheme.Colour.glassFillThin`), `ph-broom` icon 14px, "Clear" caption below. Current implementation looked close in earlier review — confirm exact sizes/colors match and fix any small deltas.

### `stageLabel()` text mapping

13. Verify `ShelfView.swift`'s job-stage-to-label mapping matches `Shelf.jsx`'s `stageLabel()`: queued→"Queued", preparing→"Preparing…", reading→"Reading…", processing→"Processing…", refining→"Refining…", complete→"Done", failed→"Failed", cancelled→"Cancelled". Fix any wording/punctuation (note the ellipsis `…` character) mismatches.

## Deliverable

When done, provide a short handoff summary:
- List of files changed and what changed in each (token additions to `AppTheme.swift`, component changes to `AppStatusToken.swift`/`AppButtonStyle.swift`, and the `ShelfView.swift` changes).
- Confirmation the build succeeds (`xcodebuild build ...` as above, paste the final "BUILD SUCCEEDED" line).
- Any spec ambiguities you resolved via judgment calls (e.g. the peekIdleView decision in item 7), with your reasoning, so the user can review.
- Any remaining open questions you deliberately did NOT resolve (should be none, per the "no triage" rule — but flag anything truly blocked, e.g. missing asset/icon).
