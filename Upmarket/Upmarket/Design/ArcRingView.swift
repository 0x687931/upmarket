import SwiftUI

struct ArcRingView<Content: View>: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let ringColor: Color
    let trackColor: Color
    let content: () -> Content

    init(
        progress: Double,
        size: CGFloat,
        lineWidth: CGFloat,
        ringColor: Color,
        trackColor: Color = AppTheme.Colour.arcTrack,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
        self.ringColor = ringColor
        self.trackColor = trackColor
        self.content = content
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            ArcProgressRing(progress: min(max(progress, 0), 1))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .animation(.linear(duration: 0.4), value: min(max(progress, 0), 1))

            content()
        }
        .frame(width: size, height: size)
    }
}
