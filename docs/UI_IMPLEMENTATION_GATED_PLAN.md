# Upmarket UI — Gated Implementation Plan

**Status:** Ready for implementation  
**Depends on:** `UI_DESIGN_SPEC.md` (design intent), `IMPLEMENTATION_PLAN.md` (release gates)  
**Scope:** All UI changes from the design spec, broken into concrete, shippable gates

Each gated phase is self-contained, reviewable, and mergeable independently. Phases are
ordered by impact-to-effort ratio: the first phases ship the highest-value changes with
the least risk. Each phase has acceptance criteria that can be verified without a
TestFlight build.

---

## Gate UI-1 — Foundation: Progress Data and Shared Primitives

**Why first:** Every subsequent gate depends on `ConversionJob` exposing a scalar
`progress: Double`. Without this the arc ring, dropdown progress bar, and peek panel
are all blocked. This gate also creates the shared shape and animation primitives
that later gates compose.

**Blocks:** UI-2, UI-3, UI-4

### 1.1 — Add `progress` to `ConversionJob`

**File:** `Upmarket/Domain/ConversionJob.swift`

Add a published `progress: Double` property (0.0–1.0) derived from stage:

```swift
var progress: Double {
    switch stage {
    case .queued:         return 0.0
    case .copying:        return 0.08
    case .extracting:     return 0.20
    case .python:         return 0.55   // wide band — Python work is the longest
    case .postProcessing: return 0.88
    case .complete:       return 1.0
    case .failed:         return 1.0
    case .cancelled:      return 1.0
    }
}
```

If the Python bridge starts emitting fractional progress (0–100 heartbeat events),
replace the `.python` band with `pythonProgress: Double` interpolated between 0.20
and 0.88. Wire the Python heartbeat value into `ConversionJob` before that switch
case matters.

**Also add to `ConversionQueue`:**
```swift
var overallProgress: Double {
    let active = jobs.filter(\.isRunning)
    guard !active.isEmpty else { return jobs.isEmpty ? 0 : 1 }
    return active.map(\.progress).reduce(0, +) / Double(active.count)
}
```

### 1.2 — `ArcProgressRing` shape

**New file:** `Upmarket/Views/Shared/ArcProgressRing.swift`

```swift
import SwiftUI

struct ArcProgressRing: Shape {
    var progress: Double  // 0.0–1.0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        p.addArc(
            center: centre,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * progress),
            clockwise: false
        )
        return p
    }
}
```

Usage pattern (used in UI-2 and UI-3):
```swift
ZStack {
    // Track
    Circle()
        .stroke(Color.primary.opacity(0.1), lineWidth: 3)
    // Progress
    ArcProgressRing(progress: item.progress)
        .stroke(
            Color.accentColor,
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
        .animation(.linear(duration: 0.4), value: item.progress)
}
.frame(width: 48, height: 48)
```

### 1.3 — `PulseRingView` component

**New file:** `Upmarket/Views/Shared/PulseRingView.swift`

Reusable expanding-ring animation used in UI-2 (drop zone glow) and UI-4 (tour
spotlight). One ring expands from scale 1.0 → 1.25 while fading 0.6 → 0 over
1.4s, looping.

```swift
import SwiftUI

struct PulseRingView: View {
    var color: Color = .accentColor
    var lineWidth: CGFloat = 2
    var isActive: Bool = true

    @State private var animating = false

    var body: some View {
        Circle()
            .stroke(color.opacity(animating ? 0 : 0.6), lineWidth: lineWidth)
            .scaleEffect(animating ? 1.25 : 1.0)
            .animation(
                isActive
                    ? .easeOut(duration: 1.4).repeatForever(autoreverses: false)
                    : .default,
                value: animating
            )
            .onAppear { if isActive { animating = true } }
            .onChange(of: isActive) { active in
                animating = active
            }
    }
}
```

### Acceptance criteria

- [ ] `ConversionJob.progress` returns correct values for all 7 stages in unit tests
- [ ] `ConversionQueue.overallProgress` returns 1.0 when all jobs complete, 0.0 when
      queue is empty
- [ ] `ArcProgressRing` renders a partial arc at all progress values from 0 to 1
- [ ] `ArcProgressRing` animates smoothly when `progress` value changes
- [ ] Both new files compile without warnings on macOS 13.3+

---

## Gate UI-2 — Shelf: Drop Zone + Card Actions

**Why second:** Highest user-impact changes, lowest layout risk. Two independent
improvements to the existing `ShelfView` and `ShelfItemView`. No new windows,
no new panels, no structural changes.

**Depends on:** UI-1 (for arc ring)

### 2.1 — Drop zone inhale/exhale

**File:** `Upmarket/Views/ShelfView.swift`

Add `@State private var dragScale: CGFloat = 1.0` to `ShelfView`.

Replace the existing `.onDrop` modifier with:

```swift
.onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
.onChange(of: isTargeted) { targeted in
    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
        dragScale = targeted ? 1.05 : 1.0
    }
}
.scaleEffect(dragScale)
```

Add a `PulseRingView` overlay that is active only while `isTargeted`:

```swift
.overlay(
    PulseRingView(color: .accentColor, lineWidth: 2, isActive: isTargeted)
        .padding(-8)   // extends slightly beyond shelf bounds
)
```

Update `emptyView` to react to `isTargeted`:

```swift
private var emptyView: some View {
    VStack(spacing: 6) {
        Image(systemName: isTargeted
            ? "arrow.down.circle.fill"
            : "arrow.down.circle"
        )
        .font(.system(size: 20))
        .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.5))
        .symbolEffect(.bounce, value: isTargeted)   // macOS 14+

        Text(isTargeted ? "Release to convert" : "Drop documents here")
            .font(.system(size: 12, weight: isTargeted ? .semibold : .regular))
            .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.6))
    }
    .animation(.easeInOut(duration: 0.15), value: isTargeted)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 16)
}
```

### 2.2 — Arc progress on active shelf cards

**File:** `Upmarket/Views/ShelfView.swift` → `ShelfItemView`

Replace the current `fileIcon` + `stateIndicator` composition with a new
`iconWithArc` view that wraps the icon in an arc ring when the job is active:

```swift
@ViewBuilder private var iconWithArc: some View {
    ZStack {
        // Arc ring — only for running jobs
        if item.isRunning {
            // Track ring
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 3)
                .frame(width: 46, height: 46)
            // Progress ring
            ArcProgressRing(progress: item.progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 46, height: 46)
                .animation(.linear(duration: 0.4), value: item.progress)
        }
        // File icon inside ring
        fileIcon
            .frame(width: 32, height: 32)
        // State badge (bottom-right)
        stateIndicator
            .offset(x: 13, y: 13)
    }
    .frame(width: 46, height: 46)
}
```

Replace the existing `ZStack(alignment: .bottomTrailing)` in `ShelfItemView.body`
with `iconWithArc`.

### 2.3 — Always-visible action buttons on completed cards

**File:** `Upmarket/Views/ShelfView.swift` → `ShelfItemView`

Current behaviour: `hoverActions` is overlaid only when `showActions == true`
(hover-triggered). This is unreliable on small targets.

New behaviour: completed and failed jobs show a persistent, compact action row.
Running jobs keep the hover overlay (cancel button needs less permanence).

Replace the `hoverActions` overlay logic:

```swift
var body: some View {
    VStack(spacing: 3) {
        iconWithArc
        Text(showCopied ? "Copied!" : item.name)
            // ... unchanged
        statusText
        // Persistent actions for terminal states
        if !item.isRunning {
            persistentActions
        }
    }
    .padding(.vertical, 6)
    // Hover overlay only for running jobs (cancel button)
    .overlay(alignment: .bottom) {
        if item.isRunning && showActions {
            runningHoverActions
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
    .contentShape(Rectangle())
    .onHover { showActions = $0 }
    .onTapGesture(count: 2) { handleDoubleClick() }
    .onTapGesture(count: 1) { handleSingleClick() }
    .contextMenu { contextMenuItems }
}
```

New `persistentActions` view (always visible on complete/failed cards):

```swift
private var persistentActions: some View {
    HStack(spacing: 4) {
        if let output = item.result?.output {
            // Copy
            Button {
                FileAccessService.shared.copyMarkdown(output.markdown)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Copy Markdown")

            // Open
            Button { handleDoubleClick() } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Open in editor")
        }

        if item.result?.errorMessage != nil {
            // Retry
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Retry")
        }

        // Remove (always present on terminal jobs)
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 10))
        }
        .buttonStyle(ShelfActionButtonStyle())
        .help("Remove")
    }
    .padding(.top, 2)
}
```

`ShelfActionButtonStyle` already exists. No changes needed to it.

`runningHoverActions` retains only the cancel button, matching current
`hoverActions` for the running case:

```swift
private var runningHoverActions: some View {
    HStack(spacing: 3) {
        Button(action: onCancel) {
            Image(systemName: "stop.fill").font(.system(size: 8))
        }
        .buttonStyle(ShelfActionButtonStyle()).help("Cancel")
    }
    .padding(.bottom, 2)
}
```

### 2.4 — Stage label crossfade

**File:** `Upmarket/Views/ShelfView.swift` → `ShelfItemView.statusText`

Wrap the status label in a `.contentTransition(.opacity)` so stage changes
crossfade instead of hard-cutting:

```swift
private var statusText: some View {
    Group {
        // ... existing label logic unchanged
    }
    .contentTransition(.opacity)
    .animation(.easeInOut(duration: 0.2), value: item.stage)
}
```

### Acceptance criteria

- [ ] Dragging a file over the shelf causes a visible scale-up (1.05) and pulse ring
- [ ] Releasing the drag causes the shelf to spring back to scale 1.0
- [ ] Empty shelf text reads "Release to convert" during drag, "Drop documents here" when idle
- [ ] Active jobs show an arc ring that visually advances through stages
- [ ] Completed jobs show Copy, Open, and Remove buttons without requiring hover
- [ ] Failed jobs show Retry and Remove buttons without requiring hover
- [ ] Running jobs still show the Cancel button on hover only
- [ ] Stage label text crossfades (no hard-cut) when stage changes
- [ ] All changes work on macOS 13.3 (no `.symbolEffect` crash — guard with `#available`)

---

## Gate UI-3 — Menu Bar Dropdown Redesign

**Why third:** Visible but contained. The dropdown is a single `MenuBarDropdown.swift`
file with no structural dependencies on shelf or tour. Isolated risk.

**Depends on:** UI-1 (for `overallProgress`)

### 3.1 — Widen and restructure layout

**File:** `Upmarket/Views/MenuBarDropdown.swift`

Change `.frame(width: 220)` to `.frame(width: 280)`.

Replace the existing `body` `VStack`:

```swift
var body: some View {
    VStack(spacing: 0) {
        headerBanner        // new — gradient with progress bar
        sectionDivider
        sectionLabel("NOW")
        primaryActionRow    // new — 44pt, accent styling
        sectionDivider
        sectionLabel("WORKSPACE")
        workspaceRows       // Show Shelf (with badge), History placeholder
        sectionDivider
        sectionLabel("APP")
        appRows             // Preferences, Check for Updates
        sectionDivider
        footer
    }
    .frame(width: 280)
}
```

### 3.2 — Gradient header banner

Replace the existing `header` computed property:

```swift
private var headerBanner: some View {
    ZStack(alignment: .bottomLeading) {
        // Gradient fill
        LinearGradient(
            colors: [
                Color(hue: 0.67, saturation: 0.7, brightness: 0.75),   // indigo
                Color(hue: 0.75, saturation: 0.65, brightness: 0.70)    // purple
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack(spacing: 0) {
            // Top row: icon + name + badge
            HStack(spacing: 8) {
                appIcon
                Text("Upmarket")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
                entitlementBadge
                pulseIndicator
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, conversion.isConverting ? 8 : 12)

            // Progress bar — only while converting
            if conversion.isConverting {
                progressBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    .frame(height: conversion.isConverting ? 68 : 48)
    .animation(.easeInOut(duration: 0.25), value: conversion.isConverting)
    .clipShape(RoundedRectangle(cornerRadius: 0))   // square corners — blends with popover
}
```

`appIcon`:
```swift
private var appIcon: some View {
    Image(systemName: "number.square.fill")
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
}
```

`entitlementBadge`:
```swift
private var entitlementBadge: some View {
    Group {
        switch store.entitlement {
        case .none:
            if store.freeDocsRemaining > 0 {
                badge(
                    label: "\(store.freeDocsRemaining) free",
                    foreground: .white.opacity(0.85),
                    background: .white.opacity(0.15)
                )
            } else {
                badge(
                    label: "Trial ended",
                    foreground: .white.opacity(0.85),
                    background: .white.opacity(0.15)
                )
            }
        case .basic:
            badge(
                label: "Upmarket",
                foreground: .white,
                background: .white.opacity(0.2)
            )
        case .pro:
            // Shimmer gradient badge
            proBadge
        }
    }
}

private func badge(label: String, foreground: Color, background: Color) -> some View {
    Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
}
```

`proBadge` — shimmer animation:
```swift
private var proBadge: some View {
    Text("Upmarket + AI")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: 0.67, saturation: 0.5, brightness: 1.0),
                            Color(hue: 0.75, saturation: 0.6, brightness: 0.9),
                            Color(hue: 0.67, saturation: 0.5, brightness: 1.0)
                        ],
                        startPoint: UnitPoint(x: shimmerOffset, y: 0),
                        endPoint: UnitPoint(x: shimmerOffset + 1, y: 0)
                    )
                )
        )
        .onAppear { startShimmer() }
}

@State private var shimmerOffset: Double = -1.0

private func startShimmer() {
    withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
        shimmerOffset = 1.0
    }
}
```

`pulseIndicator`:
```swift
private var pulseIndicator: some View {
    Group {
        if conversion.isConverting {
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .opacity(pulsing ? 0.4 : 1.0)
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: pulsing
                )
                .onAppear { pulsing = true }
        }
    }
}

@State private var pulsing = false
```

`progressBar`:
```swift
private var progressBar: some View {
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            // Track
            Capsule().fill(Color.white.opacity(0.2)).frame(height: 3)
            // Fill
            Capsule()
                .fill(completedConversion
                    ? Color.green
                    : Color.white.opacity(0.85)
                )
                .frame(
                    width: geo.size.width * conversion.overallProgress,
                    height: 3
                )
                .animation(.linear(duration: 0.3), value: conversion.overallProgress)
        }
    }
    .frame(height: 3)
}

@State private var completedConversion = false
```

Wire completion flash: in `onChange(of: conversion.isConverting)`, when it
transitions from `true` to `false`, set `completedConversion = true`, then after
0.8s reset to `false`.

### 3.3 — Section labels

```swift
private func sectionLabel(_ text: String) -> some View {
    HStack {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
        Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
    .padding(.bottom, 1)
}

private var sectionDivider: some View {
    Divider().padding(.horizontal, 0)
}
```

### 3.4 — Primary action row (Convert Document…)

```swift
private var primaryActionRow: some View {
    Button(action: { openConversionWindow(pickFile: true) }) {
        HStack(spacing: 10) {
            Image(systemName: primaryActionHovered
                ? "doc.badge.arrowtriangle.up.fill"
                : "doc.badge.plus"
            )
            .font(.system(size: 14))
            .foregroundStyle(Color.accentColor)
            .frame(width: 20)
            .if(available: { // macOS 14 guard — see note below
                $0.contentTransition(.symbolEffect(.replace.downUp))
            })

            Text("Convert Document…")
                .font(.subheadline).fontWeight(.medium)

            Spacer()

            Text("⌘N")
                .font(.system(size: 10, weight: .medium).monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 0)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(primaryActionHovered ? 0.1 : 0))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { primaryActionHovered = $0 }
}

@State private var primaryActionHovered = false
```

Note: `.contentTransition(.symbolEffect(.replace.downUp))` is macOS 14+. Wrap
with `if #available(macOS 14.0, *)` or use a view extension helper:

```swift
extension View {
    @ViewBuilder func symbolReplaceTransition() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.symbolEffect(.replace.downUp))
        } else {
            self
        }
    }
}
```

### 3.5 — Workspace rows with job badge

```swift
private var workspaceRows: some View {
    VStack(spacing: 0) {
        menuItem(icon: "sidebar.right", label: "Show Shelf") {
            ShelfWindowController.shared.show()
        } trailing: {
            if conversion.jobs.count > 0 {
                Text("(\(conversion.jobs.count))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        // History row (disabled for v1.0, visible as coming soon)
        menuItemDisabled(icon: "clock", label: "History")
    }
}
```

Extend `menuItem` to accept an optional `trailing` view builder:

```swift
private func menuItem<T: View>(
    icon: String,
    label: String,
    action: @escaping () -> Void,
    @ViewBuilder trailing: () -> T = { EmptyView() }
) -> some View {
    Button(action: action) {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(label)
                .font(.subheadline)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
```

`menuItemDisabled` renders identically but at `.tertiary` opacity with no action:

```swift
private func menuItemDisabled(icon: String, label: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 13)).foregroundStyle(.tertiary).frame(width: 18)
        Text(label).font(.subheadline).foregroundStyle(.tertiary)
        Spacer()
        Text("Coming soon")
            .font(.system(size: 9)).foregroundStyle(.quaternary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 7)
}
```

### 3.6 — Footer update

```swift
private var footer: some View {
    HStack {
        Text("v\(appVersion)")
            .font(.caption2).foregroundStyle(.tertiary)
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
}
```

Unchanged from current except left-side adds `· email` only if in non-AppStore
debug builds (avoid displaying email in App Store builds):

```swift
private var versionString: String {
    #if DEBUG
    return "v\(appVersion) · \(userEmail)"
    #else
    return "v\(appVersion)"
    #endif
}
```

### Acceptance criteria

- [ ] Dropdown is 280pt wide
- [ ] Gradient banner renders with indigo→purple fill in both light and dark mode
- [ ] Entitlement badge renders correctly for `.none`/`.basic`/`.pro` states in
      Xcode Previews with mock store environments
- [ ] `Upmarket + AI` badge shimmer animates continuously without stutter
- [ ] Progress bar appears only while `ConversionQueue.isConverting == true`
- [ ] Progress bar fills to match `overallProgress` as jobs advance through stages
- [ ] Progress bar flashes green then fades when conversion finishes
- [ ] "Convert Document…" row is 44pt tall; all others are 36pt
- [ ] "Convert Document…" icon changes on hover (macOS 14+) or stays static (macOS 13)
- [ ] "Show Shelf" row shows job count badge when `jobs.count > 0`
- [ ] Section labels appear in `.caption2 .uppercase .tracking(0.8)`
- [ ] "History" row is visible but non-interactive, labelled "Coming soon"
- [ ] Dropdown opens and closes without layout jitter
- [ ] `⌘N` keyboard shortcut actually triggers "Convert Document…" (wire via
      `.keyboardShortcut("n", modifiers: .command)` on the button)

---

## Gate UI-4 — Menu Bar Icon States

**Why fourth:** Small file, isolated to `MenuBarIconView.swift`. Zero risk to other
surfaces. Immediately visible improvement.

**Depends on:** UI-1 (for `isConverting`, already available)

**File:** `Upmarket/Views/MenuBarIconView.swift`

### 4.1 — Three-state icon with badge dot

```swift
struct MenuBarIconView: View {
    @EnvironmentObject private var conversion: ConversionQueue
    @State private var completionToken = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            iconSymbol
            badgeDot
        }
        .frame(width: 22, height: 22)
    }

    private var iconSymbol: some View {
        Group {
            if #available(macOS 14.0, *) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace.byLayer.downUp))
                    .symbolEffect(.pulse, isActive: conversion.isConverting)
                    .symbolEffect(.bounce, value: completionToken)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor)
            }
        }
    }

    private var iconName: String {
        // Keep the same symbol — only the badge changes state
        "number.square"
    }

    private var iconColor: Color {
        // Template rendering in menu bar — must stay .primary for correct
        // light/dark adaptation. The badge provides the colour signal.
        .primary
    }

    @ViewBuilder private var badgeDot: some View {
        if conversion.isConverting {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .offset(x: 3, y: 3)
        } else if showCompletionDot {
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
                .offset(x: 3, y: 3)
                .transition(.opacity.combined(with: .scale))
        }
    }

    @State private var showCompletionDot = false
}
```

### 4.2 — Completion notification wiring

```swift
// In MenuBarIconView, add:
.onReceive(NotificationCenter.default.publisher(for: .upmarketConversionEnded)) { _ in
    completionToken += 1        // triggers .bounce symbolEffect
    showCompletionDot = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
        withAnimation(.easeOut(duration: 0.4)) {
            showCompletionDot = false
        }
    }
}
```

### Acceptance criteria

- [ ] Idle state: plain `number.square`, no badge
- [ ] Converting: `number.square` + accentColor 5pt badge dot at bottom-right
- [ ] Just finished: `.bounce` symbolEffect fires once, green badge dot for 1.8s,
      then fades
- [ ] Badge dot does not render outside the menu bar icon bounds (verify in macOS
      Sonoma and Sequoia menu bars)
- [ ] Icon remains template-mode compliant (renders correctly in light and dark
      menu bars)

---

## Gate UI-5 — Shelf Peek Panel (Collapsed Live Preview)

**Why fifth:** Structural change to `ShelfView` layout. Requires widening the
closed state and adding a new right-hand panel. Higher layout risk than UI-2/3/4
so comes after those are validated.

**Depends on:** UI-1 (arc ring, progress), UI-2 (completed baseline)

### 5.1 — Layout change: asymmetric closed state

**File:** `Upmarket/Views/ShelfView.swift`

Current `closedWidth` is `colWidth * 2 + 1` (two equal 64pt columns + divider).

New closed layout:
- Left column (control strip): **48pt** — slightly narrower, tighter
- Right column (peek panel): **168pt** — fixed width
- Total closed width: **217pt** (48 + 1 + 168)

Update constants:
```swift
private let controlStripWidth: CGFloat = 48
private let peekPanelWidth: CGFloat = 168
private let closedHeight: CGFloat = 132     // unchanged

private var closedWidth: CGFloat { controlStripWidth + 1 + peekPanelWidth }
```

Update `closedPanel` to use `controlStripWidth` and add `peekPanel` as the
right column:

```swift
private var closedPanel: some View {
    HStack(spacing: 0) {
        // Left: 3 stacked buttons
        controlStrip

        // Divider
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: closedHeight * 0.6)

        // Right: live peek panel
        peekPanel
            .frame(width: peekPanelWidth, height: closedHeight)
    }
}
```

Rename existing left-column VStack to `controlStrip`:
```swift
private var controlStrip: some View {
    VStack(spacing: 0) {
        controlButton(...)   // × unchanged
        controlButton(...)   // + unchanged
        controlButton(...)   // ›/‹ unchanged
    }
    .frame(width: controlStripWidth, height: closedHeight)
}
```

`buttonHeight` recalculates from new height: `closedHeight / 3` = 44pt.
Adjust circle hit target to `buttonHeight - 8` = 36pt (meets P2 HIG requirement
of ≥ 44pt total row height — each row IS 44pt, circle inside is 36pt visual).

### 5.2 — Peek panel view

```swift
private var peekPanel: some View {
    Group {
        if let activeJob = conversion.jobs.first(where: \.isRunning) {
            peekJobView(activeJob)
        } else if let lastJob = conversion.jobs.last {
            peekJobView(lastJob)
        } else {
            peekIdleView
        }
    }
    .clipped()
}
```

`peekIdleView` — floating drop arrow:
```swift
private var peekIdleView: some View {
    VStack(spacing: 6) {
        Image(systemName: isTargeted
            ? "arrow.down.circle.fill"
            : "arrow.down.circle"
        )
        .font(.system(size: 20))
        .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.45))
        .offset(y: floatOffset)      // animated — see below
        .animation(
            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
            value: floatOffset
        )
        .onAppear { floatOffset = 2 }

        Text(isTargeted ? "Release to convert" : "Drop files here")
            .font(.system(size: 11))
            .foregroundStyle(
                isTargeted ? Color.accentColor : .primary.opacity(0.4)
            )
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 12)
}

@State private var floatOffset: CGFloat = -2
```

`peekJobView` — live job snapshot:
```swift
private func peekJobView(_ job: ConversionJob) -> some View {
    HStack(spacing: 10) {
        // Icon with arc ring
        ZStack {
            if job.isRunning {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
                    .frame(width: 42, height: 42)
                ArcProgressRing(progress: job.progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 42, height: 42)
                    .animation(.linear(duration: 0.4), value: job.progress)
            }
            peekFileIcon(job)
                .frame(width: 30, height: 30)
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 3) {
            Text(job.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            peekStageLabel(job)
        }
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

`peekStageLabel`:
```swift
private func peekStageLabel(_ job: ConversionJob) -> some View {
    Group {
        switch job.stage {
        case .complete:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Label("Cancelled", systemImage: "minus.circle.fill")
                .foregroundStyle(.secondary)
        default:
            Text(stageName(job.stage))
                .foregroundStyle(.secondary)
        }
    }
    .font(.system(size: 10))
    .contentTransition(.opacity)
    .animation(.easeInOut(duration: 0.2), value: job.stage)
}
```

`peekFileIcon` — mirrors `ShelfItemView.fileIcon` logic:
```swift
@ViewBuilder private func peekFileIcon(_ job: ConversionJob) -> some View {
    if FileManager.default.fileExists(atPath: job.sourceURL.path),
       let icon = NSWorkspace.shared.icon(forFile: job.sourceURL.path) as NSImage? {
        Image(nsImage: icon).resizable().interpolation(.high).antialiased(true)
    } else {
        Image(systemName: "doc")
            .font(.system(size: 18)).foregroundStyle(.primary.opacity(0.5))
    }
}
```

### 5.3 — Update `totalWidth` calculation

```swift
private var totalWidth: CGFloat {
    guard isExpanded else { return closedWidth }
    let count = min(conversion.jobs.count, maxVisible)
    let content: CGFloat = count > 0
        ? CGFloat(count) * (itemWidth + itemSpacing) + itemSpacing
        : 200
    let overflow: CGFloat = conversion.jobs.count > maxVisible
        ? itemWidth + itemSpacing : 0
    return closedWidth + 8 + content + overflow
}
```

Unchanged logic; `closedWidth` now uses new constants so total expands correctly.

### Acceptance criteria

- [ ] Closed shelf is 217pt wide × 132pt tall
- [ ] Peek panel shows "Drop files here" with floating arrow animation when queue
      is empty
- [ ] Arrow bobs up 2pt and down 2pt on a 1.5s ease-in-out repeating animation
- [ ] When a job is active, peek panel shows file icon + arc ring + stage label
- [ ] When all jobs complete, peek panel shows last job's icon + "Done" label
- [ ] Peek panel does not overlap control strip (divider line visible)
- [ ] Expanded state width is unchanged in behaviour (cards + scroll view)
- [ ] Shelf window resizes correctly when toggling expand/collapse
- [ ] Hit targets on control strip buttons are ≥ 44pt (test with accessibility
      Inspector)

---

## Gate UI-6 — Onboarding Tour: Acts 1–4

**Why last:** Highest complexity, most new `NSPanel` code, and only runs on first
launch. Product-quality improvement but not a daily-use surface. Ship after all
other gates are stable.

**Depends on:** UI-1, UI-2, UI-5 (shelf must be in final state before tour demos it)

### 6.1 — Act 1: Full-screen welcome

**File:** `Upmarket/Services/TourManager.swift`

Replace `showStep(0)` with a dedicated `showWelcomeAct()`:

```swift
private func showWelcomeAct() {
    // Full-screen overlay panel
    guard let screen = NSScreen.main else { return }
    let screenFrame = screen.frame

    let overlayPanel = NSPanel(
        contentRect: screenFrame,
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    overlayPanel.level = .popUpMenu
    overlayPanel.isOpaque = false
    overlayPanel.backgroundColor = NSColor.black.withAlphaComponent(0)
    overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    overlayPanel.ignoresMouseEvents = false

    let welcomeView = TourWelcomeView {
        // On "Start" tap
        overlayPanel.orderOut(nil)
        self.overlayPanel = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.advance()   // proceed to Act 2
        }
    }
    overlayPanel.contentView = NSHostingView(rootView: welcomeView)
    overlayPanel.orderFrontRegardless()

    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.4
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        overlayPanel.animator().alphaValue = 1
    }

    self.overlayPanel = overlayPanel
}
```

**New file:** `Upmarket/Views/Tour/TourWelcomeView.swift`

```swift
import SwiftUI

struct TourWelcomeView: View {
    let onStart: () -> Void

    @State private var drawProgress: Double = 0
    @State private var line1Opacity: Double = 0
    @State private var line2Opacity: Double = 0
    @State private var buttonOpacity: Double = 0

    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 0) {
                // Animated # symbol
                HashSymbolView(progress: drawProgress)
                    .frame(width: 72, height: 72)
                    .padding(.bottom, 28)

                // Tagline — staggered fade-in
                Text("Convert anything. Read it anywhere.")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(line1Opacity)
                    .padding(.bottom, 8)

                Text("100% on this Mac. No cloud, no compromise.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(line2Opacity)
                    .padding(.bottom, 48)

                // Start button
                Button(action: onStart) {
                    Text("Start →")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 280, height: 50)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(hue: 0.67, saturation: 0.7, brightness: 0.85),
                                    Color(hue: 0.75, saturation: 0.65, brightness: 0.75)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .buttonStyle(.plain)
                .opacity(buttonOpacity)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)
        }
        .onAppear { runEntrance() }
    }

    private func runEntrance() {
        // 1. Draw hash symbol over 0.8s
        withAnimation(.easeInOut(duration: 0.8)) {
            drawProgress = 1.0
        }
        // 2. Line 1 fades in at t=0.85
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeOut(duration: 0.3)) { line1Opacity = 1 }
        }
        // 3. Line 2 at t=1.05
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.easeOut(duration: 0.3)) { line2Opacity = 1 }
        }
        // 4. Button at t=1.35
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            withAnimation(.easeOut(duration: 0.4)) { buttonOpacity = 1 }
        }
    }
}
```

**New file:** `Upmarket/Views/Tour/HashSymbolView.swift`

Draws the `#` character as a `Path` that trims progressively:

```swift
import SwiftUI

struct HashSymbolView: View {
    var progress: Double   // 0.0–1.0

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let stroke: CGFloat = 4

            // The # consists of 4 lines: 2 horizontal, 2 vertical
            // Each is 25% of total progress
            let paths: [(Path, Double, Double)] = [
                // (path, progressStart, progressEnd)
                (horizontalLine1(w: w, h: h), 0.0, 0.25),
                (horizontalLine2(w: w, h: h), 0.25, 0.5),
                (verticalLine1(w: w, h: h),   0.5, 0.75),
                (verticalLine2(w: w, h: h),   0.75, 1.0),
            ]

            for (path, start, end) in paths {
                let segmentProgress = max(0, min(1, (progress - start) / (end - start)))
                guard segmentProgress > 0 else { continue }
                let trimmed = path.trimmedPath(from: 0, to: segmentProgress)
                context.stroke(
                    trimmed,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
            }
        }
    }

    private func horizontalLine1(w: CGFloat, h: CGFloat) -> Path {
        Path { p in p.move(to: CGPoint(x: w * 0.12, y: h * 0.38))
                     p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.38)) }
    }
    private func horizontalLine2(w: CGFloat, h: CGFloat) -> Path {
        Path { p in p.move(to: CGPoint(x: w * 0.12, y: h * 0.62))
                     p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.62)) }
    }
    private func verticalLine1(w: CGFloat, h: CGFloat) -> Path {
        Path { p in p.move(to: CGPoint(x: w * 0.35, y: h * 0.10))
                     p.addLine(to: CGPoint(x: w * 0.27, y: h * 0.90)) }
    }
    private func verticalLine2(w: CGFloat, h: CGFloat) -> Path {
        Path { p in p.move(to: CGPoint(x: w * 0.65, y: h * 0.10))
                     p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.90)) }
    }
}
```

### 6.2 — Act 2: Split callout with animated preview

**File:** `Upmarket/Views/Tour/TourAct2View.swift`

The callout is 340pt × 220pt. Left and right halves:

```swift
struct TourAct2View: View {
    let step: TourStep
    let stepIndex: Int
    let total: Int
    let arrowEdge: TourArrowEdge
    let onAdvance: () -> Void
    let onSkip: () -> Void

    @State private var simulatedProgress: Double = 0
    @State private var showCheckmark = false

    var body: some View {
        ZStack {
            // Glass background
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

            HStack(spacing: 0) {
                // Left: text content (same as current TourCalloutView)
                tourTextContent
                    .frame(maxWidth: .infinity)
                    .padding(16)

                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 20)

                // Right: live animation preview
                tourAnimationPreview
                    .frame(width: 150)
                    .padding(16)
            }

            pointer
        }
        .frame(width: 340, height: 220)
        .onAppear { runSimulatedConversion() }
    }

    private var tourTextContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Progress track
            TourProgressTrack(currentAct: stepIndex, totalActs: total)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(step.symbolColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: step.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(step.symbolColor)
                }
                Text(step.title)
                    .font(.headline).fontWeight(.semibold)
            }

            Text(step.body)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAdvance) {
                Text(step.action)
                    .font(.subheadline).fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var tourAnimationPreview: some View {
        VStack(spacing: 8) {
            ZStack {
                if !showCheckmark {
                    // Arc ring around PDF icon
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 3)
                        .frame(width: 52, height: 52)
                    ArcProgressRing(progress: simulatedProgress)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 52, height: 52)
                        .animation(.linear(duration: 0.1), value: simulatedProgress)
                }
                // PDF icon
                Image(systemName: "doc.richtext")
                    .font(.system(size: 26))
                    .foregroundStyle(.primary.opacity(0.7))
                // Checkmark badge (appears on completion)
                if showCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                        .scaleEffect(showCheckmark ? 1.0 : 0.3)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(width: 52, height: 52)

            // Stage label
            Text(simulatedStageLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: simulatedStageLabel)
        }
        .frame(maxHeight: .infinity)
    }

    @State private var simulatedStageLabel = "Reading…"

    private func runSimulatedConversion() {
        simulatedProgress = 0
        showCheckmark = false
        simulatedStageLabel = "Reading…"

        // Fill arc over 2.5s in steps
        let steps: [(Double, String, Double)] = [
            (0.20, "Reading…",    0.0),
            (0.55, "Processing…", 0.6),
            (0.88, "Refining…",   1.5),
            (1.00, "Done",        2.2),
        ]
        for (progress, label, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation { simulatedProgress = progress }
                simulatedStageLabel = label
            }
        }
        // Show checkmark at t=2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                showCheckmark = true
            }
        }
        // Loop: restart after 4s
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation { showCheckmark = false; simulatedProgress = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                runSimulatedConversion()
            }
        }
    }

    // pointer — thicker rounded-tip arrow (replaces filled triangle)
    @ViewBuilder private var pointer: some View {
        switch arrowEdge {
        case .none: EmptyView()
        case .left:
            RoundedPointerShape(direction: .left)
                .fill(.ultraThinMaterial)
                .frame(width: 14, height: 22)
                .offset(x: -177)
        case .right:
            RoundedPointerShape(direction: .right)
                .fill(.ultraThinMaterial)
                .frame(width: 14, height: 22)
                .offset(x: 177)
        case .top:
            RoundedPointerShape(direction: .up)
                .fill(.ultraThinMaterial)
                .frame(width: 22, height: 14)
                .offset(y: -117)
        }
    }
}
```

**New file:** `Upmarket/Views/Tour/RoundedPointerShape.swift`

```swift
import SwiftUI

struct RoundedPointerShape: Shape {
    enum Direction { case left, right, up, down }
    let direction: Direction

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r: CGFloat = 3   // tip radius
        switch direction {
        case .left:
            // Points left: tip on minX side
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.midY - r))
            p.addArc(
                center: CGPoint(x: rect.minX + r, y: rect.midY),
                radius: r, startAngle: .degrees(-90), endAngle: .degrees(90),
                clockwise: false
            )
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .right:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.midY - r))
            p.addArc(
                center: CGPoint(x: rect.maxX - r, y: rect.midY),
                radius: r, startAngle: .degrees(-90), endAngle: .degrees(90),
                clockwise: true
            )
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .up:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX - r, y: rect.minY + r))
            p.addArc(
                center: CGPoint(x: rect.midX, y: rect.minY + r),
                radius: r, startAngle: .degrees(180), endAngle: .degrees(0),
                clockwise: true
            )
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .down:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX - r, y: rect.maxY - r))
            p.addArc(
                center: CGPoint(x: rect.midX, y: rect.maxY - r),
                radius: r, startAngle: .degrees(180), endAngle: .degrees(0),
                clockwise: false
            )
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}
```

**New file:** `Upmarket/Views/Tour/TourProgressTrack.swift`

```swift
import SwiftUI

struct TourProgressTrack: View {
    let currentAct: Int
    let totalActs: Int

    private let actLabels = ["Welcome", "Shelf", "Placement", "Menu Bar"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<totalActs, id: \.self) { i in
                    Text(i < actLabels.count ? actLabels[i] : "Step \(i+1)")
                        .font(.system(size: 8, weight: i == currentAct ? .semibold : .regular))
                        .foregroundStyle(i == currentAct ? .primary : .tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            // Progress fill bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: geo.size.width
                                   * (Double(currentAct + 1) / Double(totalActs))
                        )
                        .animation(.spring(duration: 0.4), value: currentAct)
                }
            }
            .frame(height: 3)
        }
    }
}
```

Replace the dot-row in existing `TourCalloutView` with `TourProgressTrack` —
Acts 1 and 3 (single-panel callouts) use the track too. Update `TourCalloutView`
to use `TourProgressTrack(currentAct: stepIndex, totalActs: total)` in place of
the `ForEach` dot row.

### 6.3 — Act 3: Ghost shelf corner demo

**File:** `Upmarket/Services/TourManager.swift`

After Act 2 (`showStep(2)`) calls `advance()`, the new `showGhostDemoAct()` fires:

```swift
private func showGhostDemoAct() {
    guard let screen = NSScreen.main,
          let realShelf = ShelfWindowController.shared.window else { return }

    let shelfSize = realShelf.frame.size
    let visible = screen.visibleFrame

    // Ghost panel — snapshot of shelf appearance
    let ghostPanel = NSPanel(
        contentRect: NSRect(origin: realShelf.frame.origin, size: shelfSize),
        styleMask: [.nonactivatingPanel, .borderless],
        backing: .buffered,
        defer: false
    )
    ghostPanel.level = .popUpMenu
    ghostPanel.isOpaque = false
    ghostPanel.backgroundColor = .clear
    ghostPanel.alphaValue = 0.55
    ghostPanel.ignoresMouseEvents = true
    ghostPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    // Render shelf snapshot as static image
    if let contentView = realShelf.contentView,
       let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
        contentView.cacheDisplay(in: contentView.bounds, to: bitmapRep)
        let image = NSImage(size: contentView.bounds.size)
        image.addRepresentation(bitmapRep)
        let imageView = NSImageView(image: image)
        imageView.frame = NSRect(origin: .zero, size: shelfSize)
        ghostPanel.contentView = imageView
    }

    ghostPanel.orderFrontRegardless()

    // Corner sequence with delays
    let corners: [(NSPoint, TimeInterval)] = [
        (NSPoint(                                           // top-right
            x: visible.maxX - shelfSize.width - 16,
            y: visible.maxY - shelfSize.height - 16
        ), 0.0),
        (NSPoint(                                           // top-left
            x: visible.minX + 16,
            y: visible.maxY - shelfSize.height - 16
        ), 0.9),
        (NSPoint(                                           // bottom-left
            x: visible.minX + 16,
            y: visible.minY + 16
        ), 1.8),
        (NSPoint(                                           // bottom-right (home)
            x: visible.maxX - shelfSize.width - 16,
            y: visible.minY + 16
        ), 2.7),
    ]

    for (destination, delay) in corners {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                let frame = NSRect(origin: destination, size: shelfSize)
                ghostPanel.animator().setFrame(frame, display: true)
            }
        }
    }

    // Fade out at t=3.6s, then show callout
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ghostPanel.animator().alphaValue = 0
        }, completionHandler: {
            ghostPanel.orderOut(nil)
        })
    }

    // Show Act 3 callout after ghost starts (it watches from the side)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.showCallout(for: self.steps[3])   // Act 3 callout step
    }
}
```

The Act 3 callout body is small (240pt × 120pt), uses existing `TourCalloutView`
with the `TourProgressTrack`, no split panel needed. Body text: `"Drag it to any
corner — it snaps in."`

### 6.4 — Act 4: Ghost dropdown + completion toast

Ghost dropdown panel — opens a fake `MenuBarDropdown` view:

```swift
private func showGhostDropdown() {
    guard let screen = NSScreen.main,
          let statusItem = AppDelegate.shared.statusItem else { return }

    // Position below the menu bar icon
    let iconFrame = statusItem.button?.window?.frame ?? .zero
    let dropdownSize = CGSize(width: 280, height: 240)
    let origin = NSPoint(
        x: iconFrame.midX - dropdownSize.width / 2,
        y: iconFrame.minY - dropdownSize.height - 4
    )

    let ghostPanel = NSPanel(
        contentRect: NSRect(origin: origin, size: dropdownSize),
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    ghostPanel.level = .popUpMenu
    ghostPanel.isOpaque = false
    ghostPanel.backgroundColor = .clear
    ghostPanel.alphaValue = 0
    ghostPanel.ignoresMouseEvents = true
    ghostPanel.collectionBehavior = [.canJoinAllSpaces]

    // Render a non-interactive fake dropdown
    let ghostView = MenuBarDropdownGhostView()
    ghostPanel.contentView = NSHostingView(rootView: ghostView)
    ghostPanel.orderFrontRegardless()

    // Fade in
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.3
        ghostPanel.animator().alphaValue = 0.8
    }

    // After 1.2s, fade out
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ghostPanel.animator().alphaValue = 0
        }, completionHandler: {
            ghostPanel.orderOut(nil)
        })
    }
}
```

**New file:** `Upmarket/Views/Tour/MenuBarDropdownGhostView.swift`

A static, non-interactive replica of the dropdown showing only the top 3 rows,
with the "Convert Document…" row highlighted:

```swift
import SwiftUI

struct MenuBarDropdownGhostView: View {
    @State private var highlightPrimary = false

    var body: some View {
        VStack(spacing: 0) {
            // Fake header
            HStack(spacing: 8) {
                Image(systemName: "number.square.fill")
                    .font(.system(size: 18)).foregroundStyle(.white.opacity(0.9))
                Text("Upmarket").font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color(hue: 0.67, saturation: 0.7, brightness: 0.75),
                             Color(hue: 0.75, saturation: 0.65, brightness: 0.70)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )

            Divider()

            // Highlighted primary row
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.arrowtriangle.up.fill")
                    .font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 20)
                Text("Convert Document…").font(.subheadline).fontWeight(.medium)
                Spacer()
                Text("⌘N").font(.system(size: 10).monospaced()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(highlightPrimary ? 0.15 : 0))
                    .padding(.horizontal, 4)
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeInOut(duration: 0.3)) { highlightPrimary = true }
                    // Simulated press: brief scale down
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeOut(duration: 0.15)) { highlightPrimary = false }
                    }
                }
            }

            Divider()

            // Dimmed second row (Show Shelf)
            HStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13)).foregroundStyle(Color.accentColor).frame(width: 18)
                Text("Show Shelf").font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 36)
            .foregroundStyle(.primary.opacity(0.5))
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .frame(width: 280)
    }
}
```

### 6.5 — Completion toast

Show from `ShelfWindowController` after tour finishes:

```swift
// Called from TourManager.finish()
func showCompletionToast() {
    guard let shelfWindow = window else { return }

    let toastFrame = NSRect(
        x: shelfWindow.frame.minX,
        y: shelfWindow.frame.minY - 52,
        width: shelfWindow.frame.width,
        height: 44
    )

    let toastPanel = NSPanel(
        contentRect: toastFrame,
        styleMask: [.nonactivatingPanel, .borderless],
        backing: .buffered, defer: false
    )
    toastPanel.level = .popUpMenu
    toastPanel.isOpaque = false
    toastPanel.backgroundColor = .clear
    toastPanel.ignoresMouseEvents = true
    toastPanel.collectionBehavior = [.canJoinAllSpaces]

    let toastView = TourToastView(message: "You're set. Drop your first file to begin.")
    toastPanel.contentView = NSHostingView(rootView: toastView)

    toastPanel.alphaValue = 0
    toastPanel.setFrame(toastFrame.offsetBy(dx: 0, dy: -8), display: false)
    toastPanel.orderFrontRegardless()

    // Slide up and fade in
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.35
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        toastPanel.animator().alphaValue = 1
        toastPanel.animator().setFrame(toastFrame, display: true)
    }

    // Auto-dismiss after 3s
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            toastPanel.animator().alphaValue = 0
        }, completionHandler: {
            toastPanel.orderOut(nil)
        })
    }
}
```

**New file:** `Upmarket/Views/Tour/TourToastView.swift`

```swift
import SwiftUI

struct TourToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.horizontal, 8)
    }
}
```

### 6.6 — Tour restructuring: steps → acts

Update `TourManager.steps` to 4 acts (down from 6 steps). Map existing step
indices to new act handlers:

| Act | Content | Panel type | Handler |
|---|---|---|---|
| 0 | Welcome | Full-screen overlay | `showWelcomeAct()` |
| 1 | Shelf + Drop | Split callout (340 × 220) | `showCallout(step:)` with `TourAct2View` |
| 2 | Corner placement | Small callout (240 × 120) + ghost shelf | `showGhostDemoAct()` |
| 3 | Menu bar | Callout + ghost dropdown | `showMenuBarAct()` |

Update `showStep(_ index: Int)` to route to the correct handler:

```swift
private func showStep(_ index: Int) {
    dismissCallout()
    switch index {
    case 0: showWelcomeAct()
    case 1: showShelfAct()
    case 2: showGhostDemoAct()
    case 3: showMenuBarAct()
    default: finish()
    }
}
```

Update `steps` array to 4 entries matching the 4 acts.

### Acceptance criteria

- [ ] Act 1 full-screen overlay covers all content, has correct dark opacity (0.72)
- [ ] `#` symbol draws itself stroke-by-stroke over 0.8s
- [ ] Tagline lines fade in sequentially (not all at once)
- [ ] "Start →" button appears at t≈1.35s
- [ ] Act 2 callout is 340 × 220pt with left text / right animation split
- [ ] Simulated arc fills from 0 to 1 over 2.5s, then shows checkmark
- [ ] Simulated conversion loops automatically every 4s
- [ ] `TourProgressTrack` shows correct act highlight and fill bar
- [ ] Act 3 ghost shelf is visually distinct from real shelf (lower opacity)
- [ ] Ghost visits all 4 corners with 0.9s between each
- [ ] Ghost fades out after completing the circuit
- [ ] Act 3 callout appears 0.3s after ghost starts moving
- [ ] Act 4 ghost dropdown appears beneath menu bar icon position
- [ ] "Convert Document…" row in ghost highlights then appears to press
- [ ] Toast appears below shelf, slides up, auto-dismisses after 3s
- [ ] Tour marks `upmarket.tourComplete` after Act 4 "Done" is tapped
- [ ] Skipping the tour at any act correctly dismisses all panels and marks complete

---

## Asset Inventory

All visual elements are implemented in SwiftUI/AppKit with no external image assets.
The following new Swift files are created across all gates:

| File | Gate | Purpose |
|---|---|---|
| `Views/Shared/ArcProgressRing.swift` | UI-1 | Reusable arc progress shape |
| `Views/Shared/PulseRingView.swift` | UI-1 | Reusable expanding glow ring |
| `Views/Tour/TourWelcomeView.swift` | UI-6 | Act 1 full-screen welcome |
| `Views/Tour/HashSymbolView.swift` | UI-6 | Animated # draw animation |
| `Views/Tour/TourAct2View.swift` | UI-6 | Act 2 split callout |
| `Views/Tour/RoundedPointerShape.swift` | UI-6 | Callout pointer arrow shape |
| `Views/Tour/TourProgressTrack.swift` | UI-6 | Act progress bar |
| `Views/Tour/MenuBarDropdownGhostView.swift` | UI-6 | Ghost dropdown for Act 4 |
| `Views/Tour/TourToastView.swift` | UI-6 | Completion toast |

No image assets, no SVGs, no `.xcassets` additions required.

### Colour tokens used

All colours are derived from system values — no hardcoded hex:

| Token | Usage |
|---|---|
| `Color.accentColor` | Rings, badges, primary actions, active states |
| `Color(hue: 0.67, saturation: 0.7, brightness: 0.75)` | Indigo (gradient start) |
| `Color(hue: 0.75, saturation: 0.65, brightness: 0.70)` | Purple (gradient end) |
| `.primary / .secondary / .tertiary` | All text hierarchy |
| `.ultraThinMaterial` | All glass surfaces |
| `.systemGreen / .systemRed` | Success/failure states only |

---

## Dependency Map

```
UI-1 (primitives)
  ├── UI-2 (shelf: drop zone + cards)
  │     └── (unblocks UI-5)
  ├── UI-3 (menu bar dropdown)
  └── UI-4 (menu bar icon)

UI-5 (shelf peek panel)    ← depends on UI-1, UI-2
  └── (unblocks UI-6)

UI-6 (tour)                ← depends on UI-1, UI-2, UI-5
```

Each gate can be PRed and merged before the next begins. UI-3 and UI-4 are
independent of UI-2 and can be built in parallel after UI-1 lands.

---

## Open Engineering Questions

These must be answered before the relevant gate begins, not during:

1. **`ConversionJob.progress` source (UI-1):** The stage-derived mapping in
   1.1 is a safe default. If the Python bridge starts emitting fractional progress
   events (e.g., `{"progress": 0.42}` in heartbeat), the `.python` band can be
   replaced with live interpolation. Decide before UI-1 ships whether to wire this
   now or add it in a follow-on.

2. **Ghost shelf snapshot (UI-6, Act 3):** `NSView.bitmapImageRepForCachingDisplay`
   captures a static bitmap. If the shelf has vibrancy/material effects, the
   snapshot may look flat. Alternative: render a lightweight `ShelfGhostView`
   (a duplicate SwiftUI view without live state) instead of a bitmap. Decide
   before UI-6 begins.

3. **`AppDelegate.shared.statusItem` access in Act 4 (UI-6):** The ghost dropdown
   needs the menu bar icon's screen frame. If `statusItem` is not accessible from
   `TourManager`, add a `statusBarFrame: NSRect?` property to a shared coordinator.
   Confirm the accessor path before starting UI-6.

4. **`ConversionQueue.overallProgress` exposure (UI-1, UI-3):** Confirm
   `ConversionQueue` is `@EnvironmentObject`-injected into `MenuBarDropdown`.
   The current code injects `conversion: ConversionQueue` — verify `overallProgress`
   is accessible without a new injection point.
