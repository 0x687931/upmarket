# Task: Align the remaining screens with the design system

## Context

Upmarket is a macOS app (SwiftUI). We've been implementing a design system across the app, one screen at a time. Workbench (main window), Shelf, and Welcome have already been aligned. **Menu bar was deliberately skipped** — its actual implementation is a native `NSStatusItem`/`NSMenu` (in `AppDelegate.swift`), not the unused `MenuBarDropdown.swift`/`MenuBarIconView.swift` SwiftUI files, and AppKit controls the dropdown's appearance — don't revisit it.

The design system bundle lives at `/Users/am/Downloads/Upmarket Design System-2/`. Treat it as a **living contract between design and engineering — not a code generator, but a specification that evolves as both sides refine**:
- `tokens/*.css` — canonical design tokens, documented as mirroring `AppTheme.swift` enums (Spacing, Radius, Size, Colour, Font, Status). **When a token file and a JSX prototype disagree, the token file wins.**
- `components/**/*.jsx` (+ `.prompt.md` specs) — component-level visual contracts (Button, Badge, ActionIconButton, etc.) for every state: primary/secondary, sizes, disabled, hover/press.
- `ui_kits/upmarket-app/*.jsx` — full-screen, pixel-level specifications. Only **Paywall.jsx** remains unimplemented among the full UI kits (Welcome, Shelf, Workbench are done; MenuBar is native/out of scope).

## The implementation path (apply per screen)

1. **Tokens → Swift constants.** Check `AppTheme.swift` against `tokens/*.css` for anything this screen needs that's missing or wrong. Add/fix constants in `AppTheme` rather than hardcoding values inline.
2. **Components → SwiftUI views.** Cross-reference shared components (`AppButtonStyle.swift`, `AppStatusToken.swift`, `AppBadge.swift`, `AppSectionCard.swift`, `AppTextEditorStyle.swift`, `ArcRingView.swift`) against `components/**/*.jsx` for the specific variants/states this screen uses. Fix the shared component if it's wrong — don't patch around it locally in the screen.
3. **UI kit → SwiftUI screen** (Paywall only — see below). For screens with no UI kit spec (Preferences, Model Download, utility modals), do steps 1–2 thoroughly: token-level and component-level parity is the full scope for these screens, since there's no full-screen mockup to integrate against. Still audit spacing/padding/typography/color against the token files and the patterns established in already-completed screens (Workbench, Shelf, Welcome) for consistency.

## Standing instructions (do not deviate)

1. **No triage. Full implementation.** Don't categorize findings as "cosmetic," "low priority," or "nice to have," and don't defer them. Fix every deviation you find as part of this task.
2. **One screen at a time.** Work through the screens in the order listed below. Finish and verify one screen (including a build) before moving to the next. Don't make sweeping cross-screen changes to shared components without checking they don't regress an already-completed screen — if a shared component fix is needed, note which completed screens use it and sanity-check the change against their specs too.
3. **Don't build between every edit.** Make all the edits for a given screen, then build once to verify that screen, then move on.
4. **Build verification:**
   ```sh
   xcodebuild build -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
   ```
   Ignore stale SourceKit "Cannot find type X in scope" diagnostics for same-module types if the build succeeds — known indexing noise.
5. **Don't repeatedly relaunch the app** to check visuals — verify via the build command, unless a change touches window-level chrome (see item 6).
6. **Window-chrome caution.** If a screen's window controller needs `isOpaque`/`backgroundColor`/`hasShadow`/`styleMask` changes (e.g. to support rounded-card content matching `--shadow-window`), be extremely careful: a prior attempt to make a window transparent for rounded corners exposed AppKit's native traffic-light buttons as floating artifacts, and had to be reverted. If you're unsure whether a window-chrome change is safe, prefer NOT making the window transparent — clip the SwiftUI content to a rounded rect with a border, and accept that the window's own square corners may show small same-color gaps (often invisible if the window background matches the content background) rather than risk breaking native window controls. Flag this explicitly in your handoff if you skip a chrome change for this reason.

## Screens to align, in order

### 1. Paywall (`Views/PaywallView.swift`, spec: `ui_kits/upmarket-app/Paywall.jsx`)

This is a full UI-kit screen — integrate fully against `Paywall.jsx`:
- **Window/card chrome**: 480px wide, `var(--surface)` background, `border-radius: var(--radius-md)`, `0.5px solid var(--separator)` border, `var(--shadow-window)`. Apply the window-chrome caution (item 6) if `PaywallWindowController` needs changes.
- **Header**: close button (`ph-x-circle`, `var(--text-tertiary)`, top-right, 20px) — verify `PaywallView`'s close control matches position/size/color. 64×64 app icon, `var(--radius-app-icon)`, `var(--shadow-card)`. Title: `weight-bold text-title2/1.2`. Subtitle: `text-subheadline/1.4`, `var(--text-secondary)`, 5px top margin.
- **Tier cards** (`Tier` component): `border-radius: var(--radius-md)`, padding `14px 16px`, gap 12 between cards.
  - Selected state: `background: var(--accent-06)` (check `AppTheme.Colour.accentTint06`), `2px solid var(--accent)` border.
  - Unselected state: `background: var(--surface)`, `1px solid var(--border)`.
  - Radio indicator: 18×18 circle; selected = `5px solid var(--accent)` ring (i.e. a filled accent dot via thick border) on `var(--surface)` fill; unselected = `1.5px solid var(--border)`.
  - Tier name: `weight-bold text-title3/1`. "Best" badge via `AppBadge`/`Badge variant="accent"` for the AI tier.
  - Tagline: `text-caption/1.3`, `var(--text-secondary)`, 3px top margin.
  - Price (right-aligned): `weight-bold text-title3/1`; "one-time" label: `text-caption/1`, `var(--text-secondary)`, 2px top margin.
  - Feature list: `padding-left: 28px` (aligns under the name, past the radio), gap 7, each row = checkmark icon (`ph-check-circle`, 14px, `var(--accent)` if highlighted else `var(--success)`) + label (`text-caption/1.3`, `weight-medium`+`text-primary` if highlighted else `weight-regular`+`text-secondary`).
- **CTA area**: prominent full-width button "Get {tier name} — {price}" (use `AppProminentButtonStyle`), gap 12 below it to "Restore Purchases" (plain text button, `weight-medium text-subheadline/1`, `var(--text-secondary)`).
- **Footer**: "Pay once. No subscription..." — `text-caption/1.4`, `var(--text-tertiary)` (reuse `AppTheme.Colour.textTertiary` added for Welcome), centered, padding `0 24px 18px`.
- Cross-check `AppBadge.swift` (the "Best" badge) against `Badge.jsx`'s `variant="accent"` — this was built for Shelf/main-window contexts; verify it still fits the Paywall's inline usage next to a title.

### 2. Preferences (`Views/PreferencesView.swift`, 1105 lines — no UI kit spec)

No full-screen mockup exists. Audit against tokens + components only:
- Section/card grouping — does it use `AppSectionCard` (added in a prior pass)? If sections are still hand-rolled with ad-hoc padding/backgrounds/borders, migrate them to `AppSectionCard` for consistency with other screens, unless `AppSectionCard` doesn't fit a particular layout (e.g. a settings table) — use judgment, but don't leave obviously-divergent section chrome unaddressed.
- Typography: headings/labels/captions should map to `AppTheme.Font` roles (title/body/caption/sectionLabel), not raw `.system(size:...)` or default SwiftUI text styles, unless there's a documented reason (e.g. a fixed-width table needs `.mono`).
- Colors: any hardcoded `Color.gray`/`.secondary`/hex values should map to `AppTheme.Colour` tokens (`separator` vs `border`, `textTertiary`, status colors, etc.) per the semantic distinctions established in Workbench/Shelf.
- Buttons/toggles/pickers: verify against `AppButtonStyle.swift` variants and standard `Toggle`/`Picker` — these are native controls and mostly out of scope for restyling, but any *custom* button-like controls (e.g. a "Choose Folder" row, "Reveal in Finder" link) should use `AppActionButtonStyle`/`AppPlainButtonStyle` as appropriate, matching how similar actions are styled elsewhere (e.g. `SaveLocationSettingsView`, FileRow actions).
- Spacing: section gaps, internal padding — check against `AppTheme.Spacing` scale (4/8/12/16/24/32/48), not arbitrary numbers.
- This view also hosts `MCPIntegrationSection.swift` (63 lines) — apply the same audit to it as part of this pass since it's rendered inline.

### 3. Model Download (`Views/ModelDownloadView.swift`, 349 lines — no UI kit spec)

Audit against tokens + components:
- Progress indicators: does it use `ArcRingView` (the shared progress ring used in Shelf/FileRow) or a different/inconsistent progress visualization? If a different one, decide whether to unify on `ArcRingView` for consistency, or whether the download context genuinely needs a different presentation (e.g. a horizontal `ProgressView` for a long-running multi-GB download is more appropriate than a small ring) — use judgment but document the choice.
- Status indicators (downloading/complete/failed/queued): should map to `AppTheme.Status` (`complete`/`failed`/`processing`/`queued`) and, where a check/cross glyph is shown, `AppStatusToken` (the shared component from the Shelf/FileRow work) rather than ad-hoc SF Symbols + colors.
- Card/row chrome: same `AppSectionCard`/border/separator audit as Preferences — model rows likely resemble FileRow or Shelf cards; check for consistency with those already-completed patterns.
- Buttons (Download/Cancel/Retry/Delete): map to `AppActionButtonStyle`/`AppProminentButtonStyle`/`AppBorderedButtonStyle` per the established button-style conventions (prominent for primary download CTA, bordered/action for secondary controls).
- Typography and spacing: same `AppTheme.Font`/`AppTheme.Spacing` audit as other screens.

### 4. Utility modals — Report Problem, AI Suggestion, Save Location Settings (`Views/ReportProblemView.swift`, `Views/AISuggestionView.swift`, `Views/SaveLocationSettingsView.swift`)

These are smaller (113 / 74 / 70 lines) — audit each against tokens + components:
- `SaveLocationSettingsView` already has a `showsCardChrome` parameter referenced from prior Welcome work — verify its card chrome (border/background/radius) matches `AppSectionCard`/the modal-card conventions used elsewhere (Paywall's card chrome, once item 1 is done, is a good reference for "modal card" styling: `var(--radius-md)`, `0.5px separator border`, `var(--shadow-window)` if it's a standalone window).
- `ReportProblemView`: form fields, text areas (check `AppTextEditorStyle` — added in a prior pass — is actually used here if there's a text input), submit/cancel buttons (`AppProminentButtonStyle`/`AppBorderedButtonStyle`), spacing/typography per `AppTheme`.
- `AISuggestionView`: check icon/badge usage against `AppStatusToken`/`AppBadge` if it shows AI-suggestion states, and color usage against `AppTheme.Colour` (especially `accentTint*` tokens for any "AI" highlight tinting, consistent with the brand-gradient/accent treatment used for "+AI" elsewhere).
- Window chrome for whichever of these are standalone windows (`ReportProblemWindowController` etc., defined in `AppDelegate.swift`): apply the same window-chrome caution (item 6) — these mostly use standard `.titled` windows already and likely need no chrome changes; don't introduce transparency/rounded-window changes unless there's a clear spec reason (there isn't one for these, since no UI kit covers them — leave window chrome alone for this batch unless you find an existing token-level inconsistency, e.g. wrong `AppTheme.WindowSize.modal` corner radius usage).

## Deliverable

After each screen, and again at the end of the whole pass, provide a handoff summary:
- Files changed per screen and what changed (token additions, shared-component fixes, screen-level fixes).
- Build confirmation per screen (`** BUILD SUCCEEDED **`).
- Judgment calls made (e.g. Model Download's progress visualization choice, AppSectionCard adoption decisions) with reasoning.
- Anything explicitly deferred and why (should be rare — only for the window-chrome caution in item 6, or genuine spec gaps where no token/component precedent exists and you had to make a new one — call those out so the user can confirm the new token is named/placed sensibly).
