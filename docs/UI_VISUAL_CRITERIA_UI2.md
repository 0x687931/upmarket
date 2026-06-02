# UI-2 Visual Acceptance Criteria

**Gate:** UI-2 — Shelf: Drop Zone + Card Actions  
**Status:** Implemented — awaiting visual QA  
**File changed:** `Upmarket/Views/ShelfView.swift`

---

## Scope of changes

Four concrete changes, each testable in isolation:

| Sub-task | What changed |
|---|---|
| 2.1 | Shelf inhales on drag-enter; glow ring pulses; empty-state text and icon react |
| 2.2 | Active shelf cards show an arc progress ring around the file icon |
| 2.3 | Completed/failed cards show permanent action buttons (no hover required) |
| 2.4 | Stage label crossfades instead of hard-cutting between values |

---

## 2.1 — Drop zone inhale / exhale

### Setup
Drag any file over the shelf without releasing. Watch the shelf widget itself (not the file picker or any other surface).

### Inhale (file enters drag region)

| Property | Required value | How to verify |
|---|---|---|
| Scale | `1.05` | Shelf visibly enlarges; all 4 edges move outward equally |
| Scale spring | `.spring(duration: 0.3, bounce: 0.2)` | Slight overshoot to ~1.06, settles at 1.05 |
| Scale origin | Centre of shelf | No edge anchoring; all corners move symmetrically |
| Glow ring | Visible, expanding | `PulseRingView` stroke extends 8pt beyond shelf edge at scale 1.0 |
| Glow ring colour | `Color.accentColor` | Matches system accent (blue by default) |
| Glow ring stroke | 2pt | Thin — not a thick border |
| Glow ring motion | Continuous outward pulse | Scale 1.0→1.25, opacity 0.6→0, 1.4s easeOut, loops without pause |
| Accent border | Visible, 1.5pt, `accentColor` at opacity 0.5 | Sits on the shelf edge (separate from the expanding glow ring) |
| Empty panel text | "Release to convert" | Crossfades from "Drop documents here" |
| Empty panel text weight | `.semibold` | Heavier than idle state (`.regular`) |
| Empty panel text colour | `Color.accentColor` | Not `.secondary` |
| Empty panel icon | `arrow.down.circle.fill` | Filled variant |
| Empty panel icon colour | `Color.accentColor` | |
| Icon bounce (macOS 14+) | Single bounce animation fires on transition | `.symbolEffect(.bounce, value: isTargeted)` |

### Exhale (file exits drag region or is released)

| Property | Required value |
|---|---|
| Scale | Springs back to exactly `1.0` |
| Spring | `.spring(duration: 0.3, bounce: 0.2)` — same spring, symmetric return |
| Glow ring | Stops animating; fades to invisible (`animating = false`) |
| Glow ring stop | No ghost ring visible after `isTargeted` becomes false |
| Accent border | Fades to opacity 0 over 0.15s easeInOut |
| Empty panel text | Crossfades back to "Drop documents here" (`.regular`, secondary colour) |
| Empty panel icon | Reverts to `arrow.down.circle` (outline variant) |

### Expanded state during drag

When the shelf is already expanded and a drag enters:
- Same inhale applies (scale, glow ring, accent border)
- Card icons and text are not affected by the scale — they scale with the shelf
- No additional state changes to existing cards

### Glow ring placement

The `PulseRingView` sits in a `.overlay` with `.padding(-8)`. This means:
- At rest (scale 1.0): ring strokes begin 8pt outside the shelf edge
- At peak expansion (scale 1.25): the outermost point of the ring extends
  `8 + 0.25 × (shelf_half_dimension)` beyond the edge
- The ring must **not clip** — verify `.allowsHitTesting(false)` is set
  and the ring renders beyond the visible shelf boundary without being cut

---

## 2.2 — Arc progress ring on active cards

### Setup
Start a conversion. Observe the shelf item card for the converting file.

### Arc ring geometry

| Property | Value |
|---|---|
| Outer frame | 46 × 46 pt |
| Track ring | Full circle, `Color.primary.opacity(0.1)`, 3pt stroke |
| Progress arc | Partial arc, `Color.accentColor`, 3pt stroke, `lineCap: .round` |
| Start position | Exactly 12 o'clock (top-centre) |
| Direction | Clockwise |
| File icon frame | 32 × 32 pt (shrinks from 36pt when ring is active) |
| State badge | Positioned at the outer bottom-right of the 46pt frame |

### Arc appearance per stage

| Stage | `progress` | Arc coverage | Visible arc length |
|---|---|---|---|
| Queued | 0.0 | Nothing drawn | No arc, only track ring |
| Copying | 0.08 | ~29° | Short stub from 12 o'clock |
| Extracting | 0.20 | 72° | Reaches approx 2 o'clock |
| Python | 0.55 | 198° | Passes 6 o'clock, reaches ~8 o'clock |
| PostProcessing | 0.88 | 317° | Near-complete circle, gap at 12 o'clock |
| Complete / Failed / Cancelled | 1.0 | 360° | Full circle — briefly visible before ring disappears |

**Queued state:** Track ring still renders (full grey circle). No progress arc. This gives visual context for where the arc will appear.

### Arc animation

- When stage advances (e.g. `.extracting` → `.python`), the arc grows smoothly
- Duration: `0.4s`, `.linear` curve — no easing
- The arc must not jump to the new value; it must sweep continuously
- The arc end cap (the leading tip) is round, not flat

### Icon size transition

When a card's job starts (`!isRunning` → `isRunning`):
- Icon shrinks from 36pt to 32pt to make room for the 3pt ring
- When job finishes (`isRunning` → `!isRunning`):
- Icon returns to 36pt
- Ring disappears (both track and arc)
- This transition should happen with the existing `.spring(duration: 0.25)` on
  `conversion.jobs.count` — no additional animation needed

### State badge placement

The `stateIndicator` is offset `(x: 13, y: 13)` within the 46pt ZStack frame.
This positions it at the bottom-right corner of the 46pt outer frame, sitting
partially over the ring. Verify:
- [ ] Badge does not cover the arc stroke (the arc occupies the ring edge; the
  badge centre sits at the corner)
- [ ] Spinning indicator (macOS 15) rotates within the badge circle without
  overlapping the file icon
- [ ] Stalled warning (yellow exclamation) renders at the same position

### When the job is NOT running

- No track ring drawn
- No progress arc drawn
- Icon is 36 × 36 pt (full size)
- State badge (checkmark, xmark) still positioned at bottom-right of the 46pt
  outer frame via offset

---

## 2.3 — Always-visible action buttons

### Layout

Persistent actions occupy a **fixed 22pt height row** at the bottom of every
card, whether running or terminal. Running cards show a `Color.clear` spacer
of the same height — this prevents the card from changing height when a job
completes.

| Card state | Row content |
|---|---|
| Running | `Color.clear` (22pt tall, invisible) |
| Complete with output | Copy (⎘) + Open (↗) + Remove (✕) |
| Complete, no output | Remove (✕) only |
| Failed | Retry (↺) + Remove (✕) |
| Cancelled | Remove (✕) only |

### Button sizes and style

All buttons use `ShelfActionButtonStyle` (existing style):
- Icon font: `.system(size: 10)` — slightly smaller than the hover-only buttons
  were (was `size: 9`, now `10` for better legibility at permanent visibility)
- `foregroundStyle(.white)`
- Background: `Color.black.opacity(0.65)` in circle, `0.85` when pressed

### Button order (left to right)

**Complete with output:**
```
[⎘ Copy]  [↗ Open]  [✕ Remove]
```

**Failed:**
```
[↺ Retry]  [✕ Remove]
```

**Cancelled / complete without output:**
```
[✕ Remove]
```

### Spacing
- `HStack(spacing: 4)` between buttons
- Row is centred horizontally within the 64pt card width

### Running card: hover cancel button

When hovering a running card, a cancel button overlays at the bottom:
- Position: `.overlay(alignment: .bottom)` with `.padding(.bottom, 6)`
- The cancel button (`stop.fill`, size 8) uses `ShelfActionButtonStyle`
- Transition: `.opacity.combined(with: .scale(scale: 0.9))`
- This sits **above** the 22pt clear spacer — the spacer does not block it

### Copy feedback

Tapping Copy on a completed card (either persistent button or single-click on icon):
- Name label changes to "Copied!" in `.semibold` `.accentColor`
- Reverts after 1.5s with `.easeInOut(duration: 0.15)` animation
- The persistent Copy button itself does **not** change state — only the name label

---

## 2.4 — Stage label crossfade

### Behaviour

The status text label crossfades between values when `item.stage` changes.
There must be no hard-cut.

| Transition | Duration | Curve |
|---|---|---|
| Any stage → any stage | 0.2s | `.easeInOut` |
| Error message appears | 0.2s | `.easeInOut` |
| "Working" → "Done" | 0.2s | `.easeInOut` |
| "Working" → "Failed" | 0.2s | `.easeInOut` |
| Stalled label appears ("No progress") | 0.2s | `.easeInOut` |

### Text content per state

| State | Text | Colour |
|---|---|---|
| Queued | "Queued" | `.primary.opacity(0.65)` |
| Copying | "Copying" | `.primary.opacity(0.65)` |
| Extracting | "Reading" | `.primary.opacity(0.65)` |
| Python | "Processing" | `.primary.opacity(0.65)` |
| PostProcessing | "Refining" | `.primary.opacity(0.65)` |
| Complete | "Done" | `.primary.opacity(0.65)` |
| Failed | error message (truncated) | `.red` |
| Cancelled | "Cancelled" | `.primary.opacity(0.65)` |
| Stalled | "No progress" | `.yellow` |

### Frame
- `.frame(width: 56, height: 10)` — fixed; text never reflows or shifts
- `.lineLimit(1)` — long error messages truncate with `.tail`

---

## 2.5 — Card insertion / removal animation

Cards enter the `HStack` in the expanded items view with:
```
insertion: .push(from: .trailing).combined(with: .opacity)
removal:   .push(from: .leading).combined(with: .opacity)
```

| Action | Expected animation |
|---|---|
| New job added | Card slides in from right, fades in |
| Job removed (Remove button) | Card slides out to left, fades out |
| Multiple jobs added at once | Each card slides in from trailing edge sequentially (spring handles stagger) |

---

## Full visual inspection checklist

### Drop zone (2.1)
- [ ] Drag a file over the shelf — shelf scales up to ~1.05 with spring overshoot
- [ ] Glow ring is visible and continuously pulses outward while file is held over shelf
- [ ] Glow ring extends beyond shelf boundary (not clipped)
- [ ] Empty-state text reads "Release to convert" in semibold accentColor during drag
- [ ] Empty-state icon is `arrow.down.circle.fill` (filled) during drag
- [ ] Release drag — shelf scales back to 1.0 with spring
- [ ] Glow ring disappears immediately when drag exits
- [ ] No ghost ring visible 2s after drag exits
- [ ] Test in both expanded and collapsed states

### Arc ring on active cards (2.2)
- [ ] Start a conversion — arc ring appears around the file icon
- [ ] Track ring (grey, full circle) is visible under the progress arc
- [ ] Arc starts at 12 o'clock
- [ ] Arc grows clockwise as stages advance
- [ ] Arc transitions between stages smoothly (no jump)
- [ ] Arc end cap is rounded (not flat)
- [ ] File icon is visibly smaller (32pt) when ring is active
- [ ] State badge (spinner/checkmark/xmark) appears at bottom-right of card
- [ ] After job completes — arc and track ring disappear, icon returns to 36pt
- [ ] Test with a stalled job — yellow exclamation badge appears at bottom-right

### Always-visible actions (2.3)
- [ ] Completed card (with output): Copy, Open, Remove buttons visible without hovering
- [ ] Failed card: Retry, Remove buttons visible without hovering
- [ ] Cancelled card: Remove button visible without hovering
- [ ] Running card: 22pt empty space at bottom (no buttons)
- [ ] Running card on hover: Cancel button appears overlaid at bottom
- [ ] Card height is identical between running and completed state
- [ ] Tap Copy button on completed card — name changes to "Copied!" for 1.5s
- [ ] Tap Remove — card slides out with animation

### Stage label crossfade (2.4)
- [ ] Watch the status label during an active conversion — text crossfades between stages
- [ ] "Copying" → "Reading" → "Processing" → "Refining" → "Done" all crossfade
- [ ] No visible jump or flash between label values

### Regression (unchanged behaviour)
- [ ] Shelf expand / collapse animation is unchanged
- [ ] Drop zone still triggers file conversion
- [ ] Context menu (right-click) on cards still works
- [ ] Double-click on completed card still opens file in editor
- [ ] Single-click on completed card still copies Markdown
- [ ] Overflow badge (`+N`) still appears when more than 5 jobs are queued
- [ ] Paywall still shows when trial is expired and a file is dropped
- [ ] All 20 unit tests pass: `xcodebuild test -only-testing:UpmarketTests`

---

## Dark / light mode verification

All colours used are system-adaptive. Verify in both modes:

| Element | Light | Dark |
|---|---|---|
| Track ring | Near-invisible grey | Near-invisible grey |
| Progress arc | System accent colour | System accent colour |
| Glow ring | Accent colour, fades to transparent | Accent colour, fades to transparent |
| Action button background | Dark circle on light card bg | Dark circle on dark card bg |
| "Copied!" label | Accent colour | Accent colour |
| "No progress" label | Yellow | Yellow |
| Error label | Red | Red |

No hardcoded colours are used. All are derived from `Color.accentColor`,
`Color.primary`, `Color.red`, `Color.yellow`, and `Color.black.opacity(n)`.
