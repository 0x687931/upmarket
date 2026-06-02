import SwiftUI

/// Partial-circle arc drawn from the 12 o'clock position clockwise.
/// progress = 0.0 draws nothing; progress = 1.0 draws a full circle.
/// Conforms to Animatable so SwiftUI interpolates the arc smoothly between
/// any two progress values with a standard .animation() modifier.
///
/// Usage:
///   ZStack {
///       Circle()
///           .stroke(Color.primary.opacity(0.1), lineWidth: 3)
///       ArcProgressRing(progress: job.progress)
///           .stroke(Color.accentColor,
///                   style: StrokeStyle(lineWidth: 3, lineCap: .round))
///           .animation(.linear(duration: 0.4), value: job.progress)
///   }
///   .frame(width: 48, height: 48)
struct ArcProgressRing: Shape {

    /// 0.0 (empty) → 1.0 (full circle).
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Clamp defensively — callers should not pass out-of-range values but
        // SwiftUI interpolation can briefly produce values outside [0, 1].
        let clamped = progress.clamped(to: 0...1)
        guard clamped > 0 else { return Path() }

        var p = Path()
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        p.addArc(
            center: centre,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * clamped),
            clockwise: false
        )
        return p
    }
}

// MARK: - Comparable clamp

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
