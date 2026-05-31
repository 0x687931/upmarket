import SwiftUI

/// The menu bar icon for Upmarket.
/// Uses SF Symbol palette rendering for colour, with animation states.
struct MenuBarIconView: View {

    let isConverting: Bool
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    // Icon adapts: darker/heavier on light menu bar, lighter on dark
    private var iconWeight: Font.Weight { colorScheme == .light ? .semibold : .regular }
    private var iconOpacity: Double     { colorScheme == .light ? 0.85 : 0.9 }

    var body: some View {
        ZStack {
            if #available(macOS 15.0, *) {
                icon
                    .symbolEffect(.bounce, value: isPressed)
                    .symbolEffect(.rotate, isActive: isConverting)
            } else if #available(macOS 14.0, *) {
                icon
                    .symbolEffect(.bounce, value: isPressed)
                    .symbolEffect(.pulse, isActive: isConverting)
            } else {
                icon
            }
        }
        .onTapGesture {
            isPressed.toggle()
        }
    }

    @ViewBuilder
    private var icon: some View {
        if isConverting {
            // Converting: accent filled circle — accent colour works in both modes
            if #available(macOS 14.0, *) {
                Image(systemName: "number.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color(nsColor: .controlAccentColor))
                    .font(.system(size: 16, weight: iconWeight))
                    .symbolEffect(.pulse, isActive: true)
            } else {
                Image(systemName: "number.circle.fill")
                    .font(.system(size: 16, weight: .medium))
            }
        } else {
            // Idle: adapts weight and opacity to menu bar appearance
            if #available(macOS 14.0, *) {
                Image(systemName: colorScheme == .dark ? "number.square" : "number.square.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .labelColor).opacity(iconOpacity))
                    .font(.system(size: 15, weight: iconWeight))
            } else {
                Image(systemName: "number")
                    .font(.system(size: 15, weight: .medium))
            }
        }
    }
}
