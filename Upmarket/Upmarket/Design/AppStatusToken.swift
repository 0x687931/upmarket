import SwiftUI

struct AppStatusToken: View {
    enum Kind {
        case check
        case cross
    }

    let color: Color
    let kind: Kind
    var size: CGFloat = 20
    /// Width of the white ring drawn around the badge (0 = no ring, matches Badge.jsx's `border: 1.5px solid #fff`).
    var ringWidth: CGFloat = 0
    /// Stroke width of the glyph in its 12x12 viewBox units (Badge.jsx uses 1.9, FileRow's badge uses 1.8).
    var glyphStrokeWidth: CGFloat = 1.8
    /// Fraction of `size` occupied by the glyph's drawing canvas (Badge.jsx's 9px glyph inside a 15px circle = 0.6).
    var glyphSizeRatio: CGFloat = 1.0

    var body: some View {
        let glyphSize = size * glyphSizeRatio
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white, lineWidth: ringWidth)
                )

            Canvas { context, canvasSize in
                let scale = canvasSize.width / 12
                var path = Path()

                if kind == .check {
                    path.move(to: CGPoint(x: 2.5 * scale, y: 6.2 * scale))
                    path.addLine(to: CGPoint(x: 4.9 * scale, y: 8.6 * scale))
                    path.addLine(to: CGPoint(x: 9.5 * scale, y: 3.6 * scale))
                } else {
                    path.move(to: CGPoint(x: 3.2 * scale, y: 3.2 * scale))
                    path.addLine(to: CGPoint(x: 8.8 * scale, y: 8.8 * scale))
                    path.move(to: CGPoint(x: 8.8 * scale, y: 3.2 * scale))
                    path.addLine(to: CGPoint(x: 3.2 * scale, y: 8.8 * scale))
                }

                context.stroke(
                    path,
                    with: .color(.white),
                    lineWidth: glyphStrokeWidth * (canvasSize.width / 12)
                )
            }
            .frame(width: glyphSize, height: glyphSize)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
