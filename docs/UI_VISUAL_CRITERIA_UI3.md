# UI-3 Visual Acceptance Criteria

**Gate:** UI-3 — Menu Bar Dropdown Redesign  
**Status:** Implemented — awaiting visual QA  
**File changed:** `Upmarket/Views/MenuBarDropdown.swift`

---

## Structure overview

The dropdown is now 280pt wide (up from 220pt) and composed of named sections
separated by hairline dividers and uppercase section labels.

```
┌────────────────────────────────────────────────────┐
│  HEADER BANNER (48pt idle / 68pt converting)       │
│  gradient indigo→purple, icon + name + badge + dot │
│  [progress bar — converting only]                  │
├────────────────────────────────────────────────────┤
│  NOW                                               │  ← section label
│  Convert Document…                          ⌘N    │  ← 44pt primary row
├────────────────────────────────────────────────────┤
│  WORKSPACE                                         │
│  Show Shelf                              (n)       │  ← job-count badge
│  History                        Coming soon        │  ← disabled
├────────────────────────────────────────────────────┤
│  APP                                               │
│  Preferences…                                      │
├────────────────────────────────────────────────────┤
│  v1.0                                       Quit  │
└────────────────────────────────────────────────────┘
```

---

## 1. Width and chrome

| Property | Value |
|---|---|
| Total width | Exactly 280pt |
| Outer frame | No horizontal padding — sections touch edges |
| Dividers | Full-width `Divider()` between every section |
| Section labels | See §3 |
| Background | System popover background (set by `NSPopover` host — no override) |

---

## 2. Header banner

### Geometry

| State | Height |
|---|---|
| Idle (not converting) | 48pt |
| Converting | 68pt (extra 20pt for progress bar) |

Height animates with `.easeInOut(duration: 0.25)` when `isConverting` changes.
The banner `.clipped()` so no content escapes during the height transition.

### Gradient

```
startPoint: .topLeading  →  endPoint: .bottomTrailing
Color(hue: 0.67, saturation: 0.70, brightness: 0.75)   // indigo
Color(hue: 0.75, saturation: 0.65, brightness: 0.70)   // purple
```

**In both light and dark mode:** the gradient renders identically — it is not
system-adaptive. The fixed HSB values produce a strong indigo-to-purple sweep
that reads well against both light and dark popover backgrounds.

**Must NOT have rounded corners.** The banner's top-left and top-right corners
must be visually square, flush with the popover border (`.clipped()`, no
`cornerRadius`).

### Icon

- SF Symbol: `number.square.fill`
- Size: `.system(size: 18, weight: .medium)`
- Colour: `.white.opacity(0.9)`
- Position: leading, 14pt from left edge, 12pt from top

### App name

- "Upmarket" in `.subheadline .semibold`
- Colour: `.white`
- 8pt gap after icon

### Entitlement badge (trailing, same row as icon+name)

Three states — verified against `StoreManager.entitlement`:

**`.none` with free conversions remaining:**
```
Label:      "{N} free"   (e.g. "3 free", "1 free")
Foreground: .white.opacity(0.85)
Background: Capsule, .white.opacity(0.15)
Font:       .system(size: 10, weight: .semibold)
Padding:    7pt horizontal, 3pt vertical
```

**`.none` with zero remaining:**
```
Label:      "Trial ended"
Foreground: .white.opacity(0.85)
Background: Capsule, .white.opacity(0.15)
```

**`.basic`:**
```
Label:      "Upmarket"
Foreground: .white
Background: Capsule, .white.opacity(0.2)
```

**`.pro`:**
```
Label:      "Upmarket + AI"
Foreground: .white
Background: Capsule with animated shimmer gradient (see §2.1)
```

#### 2.1 — Pro badge shimmer

The shimmer is a `LinearGradient` whose `startPoint.x` and `endPoint.x` animate
from `(-1, 0)` to `(1, 2)` over **2.5 seconds**, looping forever (`.repeatForever(autoreverses: false)`).

Gradient colours:
```
Color(hue: 0.67, saturation: 0.50, brightness: 1.0)   // bright indigo
Color(hue: 0.75, saturation: 0.60, brightness: 0.9)   // purple
Color(hue: 0.67, saturation: 0.50, brightness: 1.0)   // bright indigo (repeat)
```

Visual effect: a lighter highlight sweeps left-to-right across the badge
continuously, creating a sheen. At any moment one third of the badge appears
lighter than the other two thirds.

**Criteria:**
- [ ] Shimmer is visible and moves continuously
- [ ] Movement is left-to-right only (no reverse)
- [ ] Period is approximately 2.5s per cycle
- [ ] Shimmer does not flash or pause between cycles

### Pulse dot (trailing, right of badge, converting only)

- A 6pt white `Circle`
- Visible only while `conversion.isConverting == true`
- Opacity animates: `1.0 ↔ 0.35`, `.easeInOut(duration: 0.7)`, repeating with `autoreverses: true`
- Appears when converting starts; disappears (`.onDisappear`) when converting stops
- Must not be visible when idle — no ghost dot after conversion ends

### Progress bar (converting only, beneath icon row)

- Appears with `.transition(.opacity.combined(with: .move(edge: .top)))`
- 14pt horizontal padding from banner edges
- 10pt bottom padding
- Height: 3pt

**Track:** Full-width `Capsule`, `Color.white.opacity(0.2)`

**Fill:** `Capsule`, width = `geo.size.width * conversion.overallProgress`

| State | Fill colour |
|---|---|
| Converting | `Color.white.opacity(0.85)` |
| Just finished (≤ 0.8s after `isConverting` goes false) | `Color.green` |
| After 0.8s | Bar has already disappeared (banner shrunk back) |

Fill width animates with `.linear(duration: 0.3)` on `overallProgress` changes.

**Progress values driven by `ConversionQueue.overallProgress` (from UI-1):**

| Active stage | overallProgress | Bar fill fraction |
|---|---|---|
| Copying | 0.08 | ~8% |
| Extracting | 0.20 | 20% |
| Python | 0.55 | 55% |
| PostProcessing | 0.88 | 88% |
| Complete | 1.0 | 100% |

**Criteria:**
- [ ] Progress bar not visible when idle
- [ ] Progress bar appears immediately when conversion starts
- [ ] Bar grows smoothly left-to-right as job progresses
- [ ] Bar fills green briefly after job completes
- [ ] Bar and extra 20pt banner height both disappear 0.8s after completion
- [ ] Banner height animates smoothly (no snap)

---

## 3. Section labels

```
Font:       .system(size: 9, weight: .semibold)
Tracking:   0.8pt letter-spacing
Case:       .uppercase (SwiftUI .textCase modifier)
Colour:     .tertiary
Padding:    14pt horizontal, 8pt top, 1pt bottom
```

Section labels render for: "NOW", "WORKSPACE", "APP".

**Criteria:**
- [ ] Labels are uppercase
- [ ] Labels are visibly spaced out (letter-spacing)
- [ ] Labels are `.tertiary` — less prominent than row labels
- [ ] 8pt gap between the divider above and the label text

---

## 4. Primary action row — "Convert Document…"

### Height

44pt tall. All other action rows are 36pt (7pt vertical padding × 2 = 14pt + ~13pt text ≈ ~36pt effective).

The height difference must be visible — "Convert Document…" is noticeably taller than "Show Shelf".

### Icon

- Idle: `doc.badge.plus`
- Hovered: `doc.badge.arrowtriangle.up.fill`
- Transition (macOS 14+): `.contentTransition(.symbolEffect(.replace.downUp))` — icon rebuilds downward to upward on hover
- macOS 13: static `doc.badge.plus`, no transition
- Size: `.system(size: 14)`
- Colour: `Color.accentColor`
- Frame: 20pt wide (icon centred within)

### Background on hover

`RoundedRectangle(cornerRadius: 6)` filled with `Color.accentColor.opacity(0.1)`.
The rectangle has 4pt padding on each side (so it's 272pt wide, inset 4pt each side of the 280pt dropdown).

- Not visible at idle
- Appears on cursor hover
- No animation duration specified — default SwiftUI hover response

### Keyboard shortcut label

- "⌘N" in `.system(size: 10, weight: .medium).monospaced()`
- Colour: `.tertiary`
- Trailing edge, same row

### Keyboard shortcut behaviour

`.keyboardShortcut("n", modifiers: .command)` is attached to the button.
Pressing `⌘N` while the dropdown is open must trigger "Convert Document…".

**Criteria:**
- [ ] Row is 44pt tall (measure with Accessibility Inspector or UI test)
- [ ] "⌘N" label visible trailing
- [ ] Icon changes on hover (macOS 14+)
- [ ] Hover background appears and disappears with cursor
- [ ] `⌘N` triggers the action

---

## 5. Workspace rows

### "Show Shelf"

- Icon: `sidebar.right`, accentColor
- Row height: 36pt (7pt vertical padding)
- Trailing badge: `"({n})"` when `conversion.jobs.count > 0`
  - Font: `.system(size: 10, weight: .semibold)`
  - Colour: `Color.accentColor`
  - Example: "(1)", "(3)"
- Badge must disappear when queue empties

**Criteria:**
- [ ] No badge visible when queue is empty
- [ ] Badge appears with correct count when jobs are present
- [ ] Badge updates live as jobs are added/removed

### "History" (disabled placeholder)

- Icon: `clock`, `.tertiary`
- Label: "History", `.tertiary`
- Trailing: "Coming soon", `.system(size: 9)`, `.quaternary`
- Non-interactive — no hover state, no action
- Visually dimmer than active rows

**Criteria:**
- [ ] Row is visibly dimmer than "Show Shelf"
- [ ] "Coming soon" label visible trailing
- [ ] Clicking/tapping does nothing

---

## 6. App rows

### "Preferences…"

- Icon: `gearshape`, accentColor
- Tapping opens the preferences window (`openWindow(id: "preferences")`)
- Row height: 36pt

---

## 7. Footer

```
Left:   "v{version}" — .caption2, .tertiary
         DEBUG builds append " · debug"
Right:  "Quit" button — .caption, .secondary, .plain style
Height: ~36pt (8pt vertical padding)
```

**Criteria:**
- [ ] Version string visible bottom-left
- [ ] "Quit" visible bottom-right
- [ ] Clicking "Quit" terminates the app

---

## 8. Row interaction states

All active rows (not the History placeholder) use `.plain` `ButtonStyle` with no default highlight. The only hover treatment is on the primary row (§4). All other rows have no explicit hover state — they use the system's default focusable/highlight behaviour inside the popover.

**Criteria:**
- [ ] Clicking any active row triggers its action and closes the popover
- [ ] "Show Shelf" shows the shelf window
- [ ] "Preferences…" opens the preferences window
- [ ] History row does nothing when clicked

---

## 9. Full visual inspection checklist

### Banner states
- [ ] Open dropdown at idle — banner is 48pt, gradient fills top section
- [ ] `number.square.fill` icon visible at left in white
- [ ] "Upmarket" in white semibold next to icon
- [ ] Entitlement badge visible at right — correct label for current state
- [ ] Start a conversion — banner expands to 68pt, progress bar appears
- [ ] Progress bar grows as conversion advances through stages
- [ ] Pulse dot appears (white, breathing opacity) while converting
- [ ] Conversion finishes — bar flashes green, then shrinks back to 48pt
- [ ] Pulse dot disappears after conversion ends

### Pro badge (requires pro entitlement in StoreKit sandbox)
- [ ] "Upmarket + AI" badge visible
- [ ] Shimmer sweeps left-to-right continuously
- [ ] No pause or flash between shimmer cycles

### Structure
- [ ] Dropdown is 280pt wide (not 220pt)
- [ ] Section labels "NOW", "WORKSPACE", "APP" visible in uppercase small text
- [ ] Dividers present between all sections
- [ ] "Convert Document…" row is visibly taller than other rows
- [ ] "Convert Document…" row has hover background (accent, low opacity)
- [ ] Icon on "Convert Document…" changes on hover (macOS 14+)
- [ ] "⌘N" shortcut label visible
- [ ] Job count badge on "Show Shelf" when conversions are queued
- [ ] "History" row dimmed with "Coming soon" label
- [ ] Version string and Quit in footer

### Regression (unchanged behaviour)
- [ ] Opening dropdown still works from menu bar icon click
- [ ] "Show Shelf" still shows the shelf
- [ ] "Preferences…" still opens preferences
- [ ] "Quit" still terminates the app
- [ ] "Convert Document…" still opens file picker
- [ ] All 20 unit tests pass: `xcodebuild test -only-testing:UpmarketTests`

### Dark / light mode
All colours are either `.white` (always white on the gradient) or system colours
(`.tertiary`, `.secondary`, `Color.accentColor`). Verify:
- [ ] Banner gradient renders the same in light and dark mode
- [ ] Section labels, row labels, footer all adapt to mode
- [ ] Hover background on primary row visible in both modes

---

## Removed items

The following items from the old dropdown are **intentionally removed**:

| Old item | Reason |
|---|---|
| "Open Upmarket" row | Redundant with "Convert Document…" |
| Status text below app name | Replaced by entitlement badge + progress bar |
| Header icon switching between `number.circle.fill` and `number.square` | Replaced by banner + pulse dot |

Context menus and the paywall flow are not part of this dropdown and are unchanged.
