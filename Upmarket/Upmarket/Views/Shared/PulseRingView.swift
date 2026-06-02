import SwiftUI

/// Single expanding-ring glow animation.
/// When isActive = true the ring scales from 1.0 → 1.25 while fading
/// from opacity 0.6 → 0, then immediately restarts — creating a continuous
/// outward pulse.
///
/// Compose two PulseRingViews with a 0.7s phase offset for a double-ring effect:
///   ZStack {
///       PulseRingView(color: .accentColor, isActive: isTargeted)
///       PulseRingView(color: .accentColor, isActive: isTargeted, phaseOffset: 0.7)
///   }
///
/// Size the view to match the surface it surrounds; the ring stroke sits
/// exactly on the view boundary. Add negative padding to extend beyond it:
///   .overlay(PulseRingView(...).padding(-8))
struct PulseRingView: View {

    var color: Color = .accentColor
    var lineWidth: CGFloat = 2
    var isActive: Bool = true
    /// Seconds to wait before starting the first pulse. Use to stagger rings.
    var phaseOffset: Double = 0

    @State private var animating = false

    var body: some View {
        Circle()
            .stroke(color.opacity(animating ? 0 : 0.6), lineWidth: lineWidth)
            .scaleEffect(animating ? 1.25 : 1.0)
            .onAppear {
                guard isActive else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + phaseOffset) {
                    startPulse()
                }
            }
            .onChange(of: isActive) { active in
                if active {
                    DispatchQueue.main.asyncAfter(deadline: .now() + phaseOffset) {
                        startPulse()
                    }
                } else {
                    animating = false
                }
            }
    }

    private func startPulse() {
        guard isActive else { return }
        animating = false
        withAnimation(
            .easeOut(duration: 1.4).repeatForever(autoreverses: false)
        ) {
            animating = true
        }
    }
}
