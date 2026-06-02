import SwiftUI

struct MenuBarIconView: View {

    let isConverting: Bool

    @State private var completionToken = 0
    @State private var showCompletionDot = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            iconSymbol
            badgeDot
        }
        .frame(width: 22, height: 22)
        .onReceive(NotificationCenter.default.publisher(for: .upmarketConversionEnded)) { _ in
            completionToken += 1
            showCompletionDot = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showCompletionDot = false
                }
            }
        }
    }

    // MARK: - Symbol

    // Always number.square — state is communicated by the badge, not the symbol shape.
    // .primary foreground keeps the icon template-compliant so the OS renders it
    // correctly against both light and dark menu bar backgrounds.
    @ViewBuilder private var iconSymbol: some View {
        if #available(macOS 14.0, *) {
            Image(systemName: "number.square")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, isActive: isConverting)
                .symbolEffect(.bounce, value: completionToken)
                .contentTransition(.symbolEffect(.replace.byLayer.downUp))
        } else {
            Image(systemName: "number.square")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary)
        }
    }

    // MARK: - Badge dot

    // 5pt circle, bottom-right of the 22pt frame.
    // offset(x:3, y:3) pushes it just past the symbol edge — stays within
    // the 22pt frame so it doesn't clip against the menu bar.
    @ViewBuilder private var badgeDot: some View {
        if isConverting {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .offset(x: 3, y: 3)
        } else if showCompletionDot {
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
                .offset(x: 3, y: 3)
                .transition(.opacity.combined(with: .scale(scale: 0.5)))
        }
    }
}
