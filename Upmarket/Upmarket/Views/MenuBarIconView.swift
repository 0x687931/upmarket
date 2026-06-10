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
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(iconGradient)
            Ellipse()
                .fill(.white.opacity(0.12))
                .frame(width: 12, height: 3)
                .offset(y: -6)

            if #available(macOS 14.0, *) {
                Image(systemName: UpmarketSymbols.menuBarIcon(isConverting: isConverting))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: isConverting)
                    .symbolEffect(.bounce, value: completionToken)
                    .contentTransition(.symbolEffect(.replace.byLayer.downUp))
                    .baselineOffset(0.5)
            } else {
                Image(systemName: UpmarketSymbols.menuBarIcon(isConverting: isConverting))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .baselineOffset(0.5)
            }
        }
        .frame(width: 19, height: 19)
    }

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: isConverting
                ? [
                    Color(red: 1.00, green: 0.77, blue: 0.24),
                    Color(red: 0.97, green: 0.42, blue: 0.00),
                    Color(red: 0.91, green: 0.43, blue: 0.00)
                ]
                : [
                    Color(red: 1.00, green: 0.75, blue: 0.25),
                    Color(red: 0.91, green: 0.47, blue: 0.00),
                    Color(red: 0.91, green: 0.43, blue: 0.00)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
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
                .fill(AppTheme.Colour.success)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                .offset(x: 3, y: 3)
                .transition(.opacity.combined(with: .scale(scale: 0.5)))
        }
    }
}
