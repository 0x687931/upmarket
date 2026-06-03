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
        .task(id: completionToken) {
            guard completionToken > 0 else { return }
            showCompletionDot = true
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.4)) {
                showCompletionDot = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketConversionEnded)) { _ in
            completionToken += 1
        }
    }

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

    // 6pt dot with a 1pt white stroke — readable on both light and dark menu bars
    // and against the symbol itself. Offset pushes it to the corner of the 22pt frame.
    @ViewBuilder private var badgeDot: some View {
        if isConverting {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                .offset(x: 3, y: 3)
        } else if showCompletionDot {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                .offset(x: 3, y: 3)
                .transition(.opacity.combined(with: .scale(scale: 0.5)))
        }
    }
}
