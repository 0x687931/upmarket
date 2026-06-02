# UI-1 Visual Acceptance Criteria

**Gate:** UI-1 — Foundation: Progress Data and Shared Primitives  
**Status:** Implemented — awaiting visual QA  
**Files changed:**
- `Upmarket/Domain/ConversionJob.swift` — `progress: Double` computed property
- `Upmarket/Services/ConversionQueue.swift` — `overallProgress: Double` computed property
- `Upmarket/Views/Shared/ArcProgressRing.swift` — new file
- `Upmarket/Views/Shared/PulseRingView.swift` — new file

UI-1 produces no visible change in the running app on its own. All criteria below
are verified via Xcode Previews, unit tests, and manual inspection of the primitives
in isolation before they are composed in UI-2 and UI-3.

---

## 1. `ConversionJob.progress` — Data Correctness

Verify in unit tests (`UpmarketTests/ConversionQueueTests`). All assertions must pass.

| Stage | Expected `progress` | Tolerance |
|---|---|---|
| `.queued` | `0.0` | exact |
| `.copying` | `0.08` | exact |
| `.extracting` | `0.20` | exact |
| `.python` | `0.55` | exact |
| `.postProcessing` | `0.88` | exact |
| `.complete` | `1.0` | exact |
| `.failed` | `1.0` | exact |
| `.cancelled` | `1.0` | exact |

**Monotonicity:** Progress values must be non-decreasing through the normal
execution path: `queued(0.0) → copying(0.08) → extracting(0.20) →
python(0.55) → postProcessing(0.88) → complete(1.0)`.

**Terminal-state value:** Both `.failed` and `.cancelled` return `1.0` so
that any arc ring or progress bar snaps to full on completion regardless of
the outcome. This is intentional — the ring filling means "done", not
"succeeded". Success vs. failure is communicated by colour and badge
separately.

---

## 2. `ConversionQueue.overallProgress` — Aggregation Logic

| Queue state | Expected `overallProgress` |
|---|---|
| Empty (`jobs = []`) | `0.0` |
| All jobs complete (no running) | `1.0` |
| One active job at `.copying` | `0.08` |
| One active job at `.python` | `0.55` |
| Two active jobs: `.extracting` + `.python` | `(0.20 + 0.55) / 2 = 0.375` |
| One active (`.postProcessing`), one complete | `0.88` (only active jobs averaged) |

The complete job is excluded from the average — it no longer counts as "active".
This prevents a finished job from dragging the overall progress backward.

---

## 3. `ArcProgressRing` — Visual Specification

### Geometry

The arc is a circular segment drawn as a stroked `Path`. It is **not filled**.

- **Origin:** 12 o'clock (top-centre, −90° in standard screen coordinates)
- **Direction:** clockwise
- **At `progress = 0.0`:** no arc drawn (empty `Path`)
- **At `progress = 0.25`:** quarter-circle ending at 3 o'clock
- **At `progress = 0.5`:** half-circle ending at 6 o'clock
- **At `progress = 0.75`:** three-quarter circle ending at 9 o'clock
- **At `progress = 1.0`:** full circle (360°)

### Rendering

The shape itself has no stroke or fill — callers apply `.stroke()`:

```swift
ArcProgressRing(progress: 0.62)
    .stroke(Color.accentColor,
            style: StrokeStyle(lineWidth: 3, lineCap: .round))
    .frame(width: 48, height: 48)
```

**Required stroke style in all UI-2/UI-3 usage:**
- `lineWidth: 3` (shelf card and peek panel) or `2.5` (peek panel, space-constrained)
- `lineCap: .round` — the arc ends must be rounded caps, not square/flat
- Colour: `Color.accentColor` (adapts to system accent, dark/light mode)

**Track ring (required companion):** Always render a full-circle track beneath
the arc ring:

```swift
ZStack {
    Circle()
        .stroke(Color.primary.opacity(0.1), lineWidth: 3)   // track
    ArcProgressRing(progress: job.progress)
        .stroke(Color.accentColor,
                style: StrokeStyle(lineWidth: 3, lineCap: .round))
}
```

The track opacity `0.1` ensures it is barely visible but provides spatial
context for where the arc will travel.

### Clamping

Progress values outside `[0, 1]` are clamped silently. During SwiftUI
animation interpolation, transient out-of-range values are expected and
must not produce visual artefacts (negative arcs, arcs > 360°).

### Animation

Applied by the caller, not inside the shape:

```swift
.animation(.linear(duration: 0.4), value: job.progress)
```

- Duration: `0.4s` — short enough to feel responsive, long enough to read as
  smooth progress rather than a jump
- Curve: `.linear` — progress bars feel wrong with ease-in-out because they
  appear to decelerate as the work finishes; linear matches perceived effort
- The `animatableData` conformance on `ArcProgressRing` enables SwiftUI to
  interpolate the arc angle between any two `progress` values automatically

### Sizes used across gates

| Surface | Frame | lineWidth |
|---|---|---|
| Shelf item card (active) | 46 × 46 pt | 3 pt |
| Shelf peek panel | 42 × 42 pt | 2.5 pt |
| Tour Act 2 preview | 52 × 52 pt | 3 pt |

---

## 4. `PulseRingView` — Visual Specification

### Motion

A single ring that:
1. **Starts** at scale `1.0`, opacity `0.6`
2. **Expands** to scale `1.25`, opacity `0.0`
3. **Restarts** immediately from scale `1.0` — no pause between cycles
4. Duration: `1.4s` per cycle, `.easeOut` curve
5. The opacity fade is driven by SwiftUI's animation interpolation on the
   `.opacity` modifier (value tied to `animating` bool)

### What "1.25 scale" means

If the view frame is `W × H`, at peak the ring stroke reaches `1.25W × 1.25H`.
Size the view to match the surface it surrounds; use negative padding to allow
the ring to extend outside its parent's bounds without clipping:

```swift
.overlay(
    PulseRingView(color: .accentColor, lineWidth: 2, isActive: isTargeted)
        .padding(-8)
)
```

The `−8` padding means the ring extends 8pt beyond the shelf bounds at scale 1.0
and `8 + 0.25 × (frame / 2)` at peak.

### Colour

- Drop zone active: `Color.accentColor`, `lineWidth: 2`
- Tour spotlight (UI-6): `Color.accentColor`, `lineWidth: 2`

### Phase offset (double-ring effect)

Two `PulseRingView`s stacked with `phaseOffset: 0.7` creates a continuous
double-ring pulse — ring B starts 0.7s after ring A, so at any moment one
ring is near-opaque and one is near-transparent:

```swift
ZStack {
    PulseRingView(color: .accentColor, isActive: active)
    PulseRingView(color: .accentColor, isActive: active, phaseOffset: 0.7)
}
```

The single-ring version (no phase offset) is used in UI-2 for the drop zone.

### On/off transitions

- `isActive = true → false`: animation stops, ring snaps to hidden state
  (`animating = false` causes scale/opacity to snap to start values)
- `isActive = false → true`: animation restarts from the beginning after
  `phaseOffset` delay
- Must not leave a ghost ring visible after `isActive` becomes false

---

## 5. Xcode Preview Verification Checklist

Open `ArcProgressRing.swift` and `PulseRingView.swift` in Xcode and add
these previews manually to verify before merging:

### ArcProgressRing preview

```swift
#Preview("ArcProgressRing — all stages") {
    VStack(spacing: 16) {
        ForEach([0.0, 0.08, 0.20, 0.55, 0.88, 1.0], id: \.self) { p in
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 3)
                ArcProgressRing(progress: p)
                    .stroke(Color.accentColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Text(String(format: "%.0f%%", p * 100))
                    .font(.system(size: 10))
            }
            .frame(width: 48, height: 48)
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}
```

**What to verify:**
- [ ] `0%` row: nothing drawn (neither arc nor artefact)
- [ ] `8%` row: a short stub arc at 12 o'clock, visibly starting and ending with round caps
- [ ] `55%` row: arc passes 6 o'clock (slightly past half)
- [ ] `100%` row: full circle — arc end meets arc start with no visible gap or overlap
- [ ] All arcs start precisely at 12 o'clock
- [ ] All arcs travel clockwise
- [ ] Round caps visible on both ends of every partial arc
- [ ] Accent colour renders correctly in dark mode

### ArcProgressRing animation preview

```swift
#Preview("ArcProgressRing — animated") {
    struct Demo: View {
        @State private var p: Double = 0
        var body: some View {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3)
                ArcProgressRing(progress: p)
                    .stroke(Color.accentColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .animation(.linear(duration: 0.4), value: p)
            }
            .frame(width: 48, height: 48)
            .onAppear {
                let stages: [Double] = [0, 0.08, 0.20, 0.55, 0.88, 1.0]
                for (i, s) in stages.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.0) {
                        p = s
                    }
                }
            }
        }
    }
    return Demo()
}
```

**What to verify:**
- [ ] Arc grows smoothly between each stage value
- [ ] No jump or flicker when value changes
- [ ] Animation takes ~0.4s per step (linear)
- [ ] Arc does not reverse or overshoot

### PulseRingView preview

```swift
#Preview("PulseRingView — single and double") {
    HStack(spacing: 40) {
        // Single ring
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .frame(width: 80, height: 80)
            PulseRingView(color: .accentColor, lineWidth: 2, isActive: true)
                .frame(width: 80, height: 80)
                .padding(-8)
            Text("single").font(.caption2)
        }
        // Double ring
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .frame(width: 80, height: 80)
            ZStack {
                PulseRingView(color: .accentColor, lineWidth: 2, isActive: true)
                PulseRingView(color: .accentColor, lineWidth: 2, isActive: true,
                              phaseOffset: 0.7)
            }
            .frame(width: 80, height: 80)
            .padding(-8)
            Text("double").font(.caption2)
        }
    }
    .padding(40)
    .background(Color(.windowBackgroundColor))
}
```

**What to verify:**
- [ ] Single ring expands outward continuously — never reverses
- [ ] Ring fades to invisible at peak scale, not merely dim
- [ ] Ring at `phaseOffset: 0.7` is visibly offset in phase from ring at offset `0`
- [ ] Both rings share the same scale range and duration — they look identical except phase
- [ ] At no point are two rings simultaneously fully opaque
- [ ] Rings do not clip inside the 80pt frame (verify ring extends past frame edge)

---

## 6. Regression Checklist

Verify these existing behaviours are unchanged after UI-1:

- [ ] `ConversionQueue` tests pass: `xcodebuild test -only-testing:UpmarketTests`
      → `Test Suite 'All tests' passed`
- [ ] `ConversionJob.isRunning` still returns `true` for the 5 active stages
      (queued, copying, extracting, python, postProcessing)
- [ ] `ConversionJob.isRunning` returns `false` for complete, failed, cancelled
- [ ] `ConversionQueue.isConverting` still works correctly (unchanged — derives
      from `jobs.contains { $0.isRunning }`)
- [ ] Shelf view renders without changes in the running app (UI-1 adds no
      view-layer code — `ArcProgressRing` and `PulseRingView` are not yet
      composed into any existing view)
- [ ] No new compiler warnings in `ConversionJob.swift` or `ConversionQueue.swift`

---

## 7. What UI-1 Does NOT Change

- No visible change in the running app
- No layout changes to `ShelfView`, `MenuBarDropdown`, or `TourManager`
- No new user-facing strings
- No changes to conversion logic, queuing, cancellation, or StoreKit
- `ConversionJob.Equatable` conformance is unaffected — `progress` is a
  computed property derived from `stage`, which is already part of equality
