import SwiftUI

/// Single expanding-ring glow animation.
/// Scales 1.0 → 1.25, fades 0.6 → 0 over 1.4s, loops.
/// Uses a single @State boolean driven by a repeating animation transaction —
/// no DispatchQueue, no onAppear re-entry, no flash on isActive toggle.
struct PulseRingView: View {

    var color: Color = .accentColor
    var lineWidth: CGFloat = 2
    var isActive: Bool = true
    /// Seconds before the first pulse starts. Stagger multiple rings with this.
    var phaseOffset: Double = 0

    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(color.opacity(pulsing ? 0 : 0.6), lineWidth: lineWidth)
            .scaleEffect(pulsing ? 1.25 : 1.0)
            // Animation is applied unconditionally so SwiftUI can interpolate
            // cleanly in both directions. The value binding drives the
            // animation only when pulsing changes.
            .animation(
                isActive
                    ? .easeOut(duration: 1.4)
                        .delay(phaseOffset)
                        .repeatForever(autoreverses: false)
                    : .easeOut(duration: 0.2),
                value: pulsing
            )
            .onAppear   { pulsing = isActive }
            .onChange(of: isActive) { pulsing = $0 }
    }
}
