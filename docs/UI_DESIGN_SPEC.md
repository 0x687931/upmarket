# Upmarket — UI/UX Design Specification

**Status:** Proposed — not yet implemented  
**Relates to:** `USER_FLOW.md` (functional flows), `IMPLEMENTATION_PLAN.md` (phases)  
**Scope:** Menu bar dropdown, shelf widget, onboarding tour, micro-interactions

---

## Design Philosophy

Upmarket lives at the edge of perception — invisible when idle, present when needed.
Every interaction should feel like it belongs in the OS itself: fluid, purposeful, never
decorative for its own sake.

Three principles govern every surface:

1. **Motion is meaning.** Animations carry information (progress, state change, invitation
   to act). Nothing moves without a reason.
2. **Craft at the moment of contact.** The drop, the tap, the first launch — these are
   the moments users remember. Invest disproportionately in them.
3. **Trust the user.** Don't hide actions behind hover. Don't bury the primary action
   in a uniform list. Make hierarchy legible at a glance.

---

## 1. Menu Bar Dropdown

### Layout

Width: **280pt** (up from 220pt). Sections separated by hairline dividers and
uppercase group labels — not a flat undifferentiated list.

```
┌────────────────────────────────────────────┐
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │ ← 48pt gradient banner
│  #  Upmarket                   [Pro ●●●]   │   indigo→purple, live pulse dot
│ ████████████████░░░░░░░░░░░░░░░░░░░░░░░░░ │ ← progress bar (converting only)
├────────────────────────────────────────────┤
│  NOW                                       │
│  ⌘N  Convert Document…               →    │ ← 44pt tall, accent hover fill
├────────────────────────────────────────────┤
│  WORKSPACE                                 │
│       Show Shelf                    (3)    │ ← live job-count badge
│       History                              │
├────────────────────────────────────────────┤
│  APP                                       │
│       Preferences…                         │
│       Check for Updates                    │
├────────────────────────────────────────────┤
│  v1.0 · ajmcardle@gmail.com         Quit  │
└────────────────────────────────────────────┘
```

### Header

- **Gradient banner:** `LinearGradient` from `Color.accentColor` to a 20°
  hue-shifted purple, fills a 48pt tall region. Always full-width.
- **App name:** `.subheadline .semibold` in white.
- **Entitlement badge:** trailing capsule, right-aligned.
  - `Free` → `.secondary` grey capsule
  - `Upmarket` → accentColor capsule
  - `Upmarket + AI` → indigo→purple gradient capsule with a slow shimmer sweep
    (a `LinearGradient` that translates left-to-right over 2.5s, looping)
- **Pulse dot:** a 6pt `Circle` in white/accentColor. `.pulse` symbolEffect when
  converting, hidden when idle.
- **Progress bar:** a `Capsule` spanning the full width of the banner, 3pt tall,
  sits below the app name row. Visible only while `ConversionQueue.isConverting`.
  Animated with `.animation(.linear)` tracking `ConversionQueue.progress` (0–1).
  On completion: fills solid green, then fades out over 0.6s.

### Section headers

```swift
Text("NOW")
    .font(.caption2)
    .fontWeight(.semibold)
    .textCase(.uppercase)
    .kerning(0.8)
    .foregroundStyle(.tertiary)
    .padding(.horizontal, 14)
    .padding(.top, 10)
    .padding(.bottom, 2)
```

### Primary action row — "Convert Document…"

- Height: **44pt** (all other rows: 36pt)
- Hover state: full-row `RoundedRectangle` fill in `accentColor.opacity(0.1)`
- Icon animates on hover: `doc.badge.plus` → `doc.badge.arrowtriangle.up.fill`
  via `.contentTransition(.symbolEffect(.replace.downUp))` (macOS 14+)
- Keyboard shortcut `⌘N` displayed as `Text("⌘N")` in `.caption .monospaced`
  trailing the row

### "Show Shelf" row

- Trailing: a small badge `Text("(\(jobCount))")` in `.caption2 .semibold
  .accentColor` visible only when `ConversionQueue.jobs.count > 0`

### Footer

- Left: `v1.0 · email@…` in `.caption2 .tertiary`
- Right: `Quit` in `.caption .secondary`
- Single row, 36pt tall

### State machine

| App state | Header | Pulse dot | Progress bar |
|---|---|---|---|
| Idle, free tier | Gradient, "X free conversions" status | Hidden | Hidden |
| Idle, paid | Gradient, entitlement badge | Hidden | Hidden |
| Converting | Gradient + animated progress bar | Visible, pulsing | Visible |
| Just finished | Progress bar fills green, fades | Fades out | Fades out |

---

## 2. Shelf Widget

### Anatomy

The shelf is asymmetric: a narrow **control strip** (48pt) on the left and a
**peek panel** on the right that shows live job state even when collapsed.

```
Closed (idle):
┌────────┬──────────────────────────────────┐
│  ×     │                                  │
│  +     │    Drop documents here ↓         │  ← floating arrow animation
│  ›     │    (arrow bobs up/down, 2pt, 3s) │
└────────┴──────────────────────────────────┘
  48pt        ~160pt peek panel

Closed (converting):
┌────────┬──────────────────────────────────┐
│  ×     │  [icon]  report.pdf              │
│  +     │  ◌◌◌◌◌◌◌◌◌◌◌  62%  arc         │
│  ›     │  Refining…    [stage label]      │
└────────┴──────────────────────────────────┘

Expanded:
┌────────┬──────────────────────────────────────────────────────┐
│  ×     │  [card]  [card]  [card]  [card]  [card]  [+3]        │
│  +     │   96pt    96pt    72pt    72pt    72pt               │
│  ‹     │  active  active  done    done    fail               │
└────────┴──────────────────────────────────────────────────────┘
```

### Control strip buttons

Unchanged from current behaviour (`×` hide, `+` add, `›/‹` expand/collapse)
but with updated hover treatment:
- Hover circle diameter: `buttonHeight - 12pt` (slightly smaller, breathing room)
- Colour: `×` → `.systemRed`, `+` → `.systemGreen`, `›/‹` → `.systemBlue`
- Transition: `.easeInOut(duration: 0.1)`

### Peek panel — idle state

- `Text("Drop documents here")` in `.system(size: 12) .secondary`
- Arrow icon (`arrow.down.circle`) beneath the text
- Animation: `offset(y: arrowOffset)` where `arrowOffset` oscillates between
  `-2` and `+2` on a `sin`-based `TimelineView` with period 3.0s — drives a
  gentle float. Use `TimelineView(.animation)` and compute offset from
  `context.date.timeIntervalSinceReferenceDate`.

### Peek panel — converting state

The peek panel shows the frontmost active job:
- File icon (NSWorkspace icon, 40pt × 40pt)
- Arc progress ring drawn as a custom `Shape` around the icon:
  - Track ring: `Color.primary.opacity(0.1)`, 3pt stroke
  - Progress ring: `Color.accentColor`, 3pt stroke, `.lineCap(.round)`
  - Drawn via `Path.addArc` from -90° to `(-90 + 360 * progress)°`
  - Animates with `.animation(.linear(duration: 0.4))` on progress updates
- Stage label below icon: `.system(size: 10) .secondary`
  - Text crossfades between stages: `.contentTransition(.opacity)`
  - Stage sequence: `Reading` → `Processing` → `Refining`

### Drop zone — inhale/exhale

When a file enters the drag region:
1. Shelf **inhales**: `.scaleEffect(1.05)` with `.spring(duration: 0.3, bounce: 0.2)`
2. Glow ring appears: `Circle` stroke `accentColor.opacity(0.6)`, 2pt, expanding
   outward via `.scaleEffect` from 1.0 → 1.15 + `.opacity` from 0.6 → 0, looping
   while drag is active
3. Peek panel text changes to `"Release to convert"` in `.semibold .accentColor`

When file is released or drag exits:
- **Exhale**: `.scaleEffect(1.0)` spring back, glow ring fades

### Shelf item cards (expanded)

Two widths depending on state:
- **Active** (queued, converting): 96pt wide
- **Passive** (complete, failed, cancelled): 72pt wide

Cards animate between widths when state changes:
`.animation(.spring(duration: 0.3), value: item.stage)`

**Active card anatomy (96pt):**
```
┌──────────────────────────────┐
│     [file icon 40pt]         │
│   ╭───────────────────╮      │ ← arc ring around icon
│   │     [icon]        │      │
│   ╰───────────────────╯      │
│        report.pdf            │
│  ●●●●●●●○○○○  62%           │ ← dot row or arc label
│  Refining…                   │
│  [✕ Cancel]                  │ ← full-width button, always visible
└──────────────────────────────┘
```

**Passive card anatomy — complete (72pt):**
```
┌───────────────────────┐
│  [icon 32pt] ✓        │ ← green checkmark badge, bottom-right of icon
│  report.pdf           │
│  Done                 │
│  [⎘] [↗] [✕]          │ ← always visible: Copy, Open, Remove
└───────────────────────┘
```

**Passive card anatomy — failed (72pt):**
```
┌───────────────────────┐
│  [icon 32pt] ✕        │ ← red xmark badge
│  report.pdf           │
│  Failed               │ ← red, truncated error on hover/tooltip
│  [↻] [✕]              │ ← Retry, Remove — always visible
└───────────────────────┘
```

**Key change from current:** action buttons are **always visible** on passive
cards, not hover-only. On a 72pt card the three icons (`⎘` `↗` `✕`) at 16pt
fit comfortably in a single row with 4pt spacing.

### Card insertion / removal animation

```swift
.transition(.asymmetric(
    insertion: .push(from: .trailing).combined(with: .opacity),
    removal:   .push(from: .leading).combined(with: .opacity)
))
```

Cards feel like frames being added to or pulled from a film strip.

### Corner snapping — ghost guides

While the user drags the shelf and comes within 40pt of any screen corner:
1. Four translucent `RoundedRectangle` outlines (matching shelf dimensions)
   appear at each screen corner simultaneously — `.ultraThinMaterial` fill,
   `accentColor` stroke at 1pt, `opacity(0.25)`
2. The nearest corner's guide brightens to `opacity(0.6)` and its stroke
   goes to `accentColor` 2pt
3. On drop: shelf snaps to that corner with `.spring(duration: 0.3, bounce: 0.15)`,
   a micro-bounce overshoot of 4pt beyond target then back

Guides fade out (`.opacity(0)`, 0.2s) once the drag ends.

### Glass background — contextual tinting

Extends current `LiquidGlassBackground`:

| State | Tint overlay | Shadow |
|---|---|---|
| Idle | None | None |
| Drag hover | `accentColor.opacity(0.04)` | None |
| Converting | None | `accentColor.opacity(0.25)` bloom, 20pt radius |
| Error | `Color.red.opacity(0.03)` | None |

---

## 3. Onboarding Tour

### Structure: 4 Acts (down from 6 steps)

Each act is a distinct `NSPanel` moment. Acts replace the current uniform
callout-bubble sequence with varied presentation modes that demonstrate rather
than describe.

---

### Act 1 — Welcome (full-screen)

**Panel:** full-screen `NSPanel` at `.popUpMenu` level, `backgroundColor: .black`,
`.alphaValue` animated from 0 to 0.6 over 0.4s.

**Content (centred):**
```
              #
         Upmarket

  Convert anything. Read it anywhere.
  100% on this Mac. No cloud, no compromise.

           [ Start →  ]
```

- The `#` symbol draws itself: `TrimmedPath` animating `from: 0` to `to: 1`
  over 0.8s with `.easeInOut`, stroke 3pt, accentColor
- Tagline lines fade in sequentially: line 1 at t=0.8s, line 2 at t=1.0s,
  each `.opacity` 0→1 over 0.3s
- Button: 280pt wide, `LinearGradient` fill (accentColor → hue+20°), appears
  at t=1.3s. On hover: shimmer sweep (a white `LinearGradient` mask translating
  left-to-right over 0.8s)
- **No "Skip" on Act 1** — this is one screen, one tap to proceed

---

### Act 2 — The Shelf (side-by-side callout)

Overlay reduces to `opacity(0.2)`. Spotlight ring appears around the shelf:
a `Circle` stroke in `accentColor`, 2pt, plus an outer glow ring animating
`.scaleEffect(1.0→1.2) + .opacity(0.4→0)` looping every 1.5s.

Callout panel: **340pt wide** (wider than current 300pt), split 50/50:
- **Left half:** title + body text (same as current layout)
- **Right half:** live animated preview — simulated conversion:
  - PDF icon appears (system icon, 36pt)
  - Arc progress ring fills over 3s (no real file, `Timer`-driven)
  - Checkmark badge drops in with `.bounceDown` (macOS 15) or `scaleEffect(1.3→1.0)`
  - Loops after 1s pause

Callout pointer: `Path` drawn as a rounded-tip arrow (4pt stroke, `.round` lineCap),
not a filled triangle. Bridges cleanly to the shelf regardless of which side it
appears on.

Steps covered: shelf expand, add files, drop zone.

---

### Act 3 — Corner Placement Demo

Overlay stays at `opacity(0.2)`.

A **ghost shelf** — a semi-transparent replica of the shelf widget at 0.5 opacity —
animates autonomously:
1. Starts at current shelf position
2. Travels to top-right corner, pausing 0.4s, snapping with spring
3. Travels to top-left, pauses
4. Travels to bottom-left, pauses
5. Returns to bottom-right (original), pauses

Each travel uses `.spring(duration: 0.5, bounce: 0.1)`. The real shelf stays
in place. The ghost fades out after returning.

Callout (small, 240pt × 120pt, no split layout):
```
  ↖  It lives wherever you work.
     Drag it to any corner — it snaps in.

              [ Got it → ]
```

No "Skip" — this act auto-advances after the ghost completes its loop if the
user hasn't tapped yet, after 4s.

---

### Act 4 — Menu Bar (final act)

Spotlight ring moves to the menu bar `#` icon (requires screen-coordinate
calculation from `NSStatusItem.button?.window?.frame`).

A **ghost dropdown** — an `NSPanel` rendering a fake `MenuBarDropdown` view
at reduced opacity (0.7) — opens beneath the icon. The "Convert Document…" row
highlights with `accentColor.opacity(0.15)` fill + a simulated press (0.95
scaleEffect for 80ms then back). Ghost closes after 1.2s.

Callout (300pt × 160pt):
```
  ☰  Always one click away.
     The # icon shows status and reopens
     the shelf from any app.

              [ Done ✓ ]
```

On "Done": overlay fades fully to 0, ghost panels close, and a **toast**
appears anchored to the bottom of the shelf window:

```
┌─────────────────────────────┐
│  You're set. Drop your      │
│  first file to begin.       │
└─────────────────────────────┘
```

Toast is a `NSPanel` with `.ultraThinMaterial`, appears with `.move(edge: .bottom)`,
auto-dismisses after 3s with a fade.

---

### Progress indicator (all acts)

Replace the 6-dot row with a **track indicator**:

```
  Act 1 ────●──── Act 2 ────○──── Act 3 ────○──── Act 4
  ████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```

- Named act labels in `.caption2 .semibold`
- Active act label in `.primary`, inactive in `.tertiary`
- Progress fill bar beneath: `Capsule` fill in `accentColor`, width animates
  proportionally as acts advance

---

## 4. Menu Bar Icon

### State variants

| State | Symbol | Badge | Animation |
|---|---|---|---|
| Idle | `number.square` | None | None |
| Converting | `number.square` | 6pt accentColor dot, bottom-right | Icon: `.pulse` symbolEffect |
| Error | `number.square.fill` | 6pt red dot | None |
| Just completed | `number.square` | Momentary green dot (1.5s) | `.bounce` symbolEffect once |

The badge dot is composited in the `MenuBarIconView` using a `ZStack` — the
SF Symbol plus an absolutely-positioned `Circle` (6pt, coloured) at `offset(x: 5, y: 5)`.

### Transition animation

Idle → Converting:
```swift
.contentTransition(.symbolEffect(.replace.byLayer.downUp))
```

Completion flash (`.bounce` once on macOS 14+):
```swift
.symbolEffect(.bounce, value: completionToken)
```
where `completionToken` is an `Int` incremented each time a job completes.

---

## 5. Asset Requirements

No new SVG assets are required for the above changes. All visual elements are
achievable with:

- **SF Symbols** — all icons used are system symbols
- **SwiftUI shapes** — `Circle`, `Capsule`, `RoundedRectangle`, `Path` for
  the arc ring and pointer arrow
- **System materials** — `.ultraThinMaterial`, `.thinMaterial` for all glass surfaces
- **`LinearGradient`** — for the header banner and button fills

The one custom `Shape` needed is the **arc progress ring** — a `Path` drawing
a partial circle, parameterised by `progress: Double`. This is pure Swift/SwiftUI,
no image asset required.

```swift
struct ArcProgressRing: Shape {
    var progress: Double  // 0.0–1.0
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle.degrees(-90)
        let end   = Angle.degrees(-90 + 360 * progress)
        p.addArc(center: centre, radius: r, startAngle: start, endAngle: end, clockwise: false)
        return p
    }
}
```

Used as:
```swift
ArcProgressRing(progress: item.progress)
    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    .frame(width: 48, height: 48)
    .animation(.linear(duration: 0.4), value: item.progress)
```

---

## 6. Implementation Priority

| Change | Complexity | User impact | Suggested order |
|---|---|---|---|
| Always-visible action buttons on passive shelf cards | S | High | 1 |
| Menu bar badge dot (converting / done states) | S | High | 1 |
| Primary action row styling in dropdown | S | High | 1 |
| Entitlement badge capsule with gradient | S | Medium | 2 |
| Arc progress ring on shelf cards | M | High | 2 |
| Drop zone inhale/exhale + glow ring | M | Very high | 2 |
| Dropdown header gradient banner + progress bar | M | High | 3 |
| Peek panel with live job preview (collapsed shelf) | M | High | 3 |
| Floating arrow idle animation in peek panel | S | Medium | 3 |
| Act 1 full-screen welcome | M | High | 4 |
| Act 2 split callout with live preview | M | High | 4 |
| Act 3 ghost shelf corner demo | L | High | 4 |
| Act 4 ghost dropdown + toast | M | Medium | 4 |
| Corner snap ghost guides | M | Medium | 5 |
| Card variable widths (active 96pt / passive 72pt) | M | Medium | 5 |
| Glass background contextual tinting | S | Low | 5 |

S = small (< 2h), M = medium (2–4h), L = large (4–8h)

---

## Open Questions

1. **Ghost shelf in Act 3:** Requires rendering a `ShelfView` snapshot or a
   lightweight replica. Snapshot approach (`NSView.dataWithPDF`) is simpler;
   replica is more accurate. Decide at implementation time.

2. **Peek panel width:** 160pt proposed. Validate that the combined closed width
   (48 + 160 = 208pt) feels right at various shelf corner positions — specifically
   bottom-right on a 13" MacBook screen.

3. **Progress value source:** `ConversionQueue` currently exposes `isConverting`
   and `jobs` but not a scalar `0–1` progress. The arc ring and dropdown progress
   bar both need this. Either derive from `ConversionJob.stage` (discrete steps)
   or add a `progress: Double` field to `ConversionJob` from the Python bridge.

4. **Act 3 auto-advance:** Should the tour advance automatically after the ghost
   animation completes (4s), or only on explicit tap? Auto-advance feels slicker
   but can disorient users who look away. Recommendation: auto-advance with a
   visible countdown ring on the "Got it" button.
