import SwiftUI

struct PulseRingView: View {
    var size: CGFloat = 20
    var color: Color = .accentColor
    var active: Bool = true
    @State private var animating = false

    var body: some View {
        ZStack {
            // Outer ring — pulses opacity and scale
            Circle()
                .stroke(color.opacity(animating ? 0.0 : 0.5), lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(animating ? 1.5 : 1.0)

            // Inner ring — steady
            Circle()
                .stroke(color.opacity(0.6), lineWidth: 1.5)
                .frame(width: size * 0.6, height: size * 0.6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
    }
}
