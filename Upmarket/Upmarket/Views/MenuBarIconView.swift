import SwiftUI

struct MenuBarIconView: View {

    let isConverting: Bool
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    private var iconWeight: Font.Weight { colorScheme == .light ? .semibold : .regular }
    private var iconOpacity: Double     { colorScheme == .light ? 1.0 : 0.9 }

    var body: some View {
        ZStack {
            if isConverting {
                convertingIcon
            } else {
                idleIcon
                    .onTapGesture { isPressed.toggle() }
                    .modifier(BounceOnPress(isPressed: isPressed))
            }
        }
        .frame(width: 18, height: 18)
    }

    // Indeterminate circular spinner with the # centred inside
    private var convertingIcon: some View {
        ZStack {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.55)
                .tint(Color(nsColor: .labelColor).opacity(iconOpacity))
            Image(systemName: "number")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color(nsColor: .labelColor).opacity(iconOpacity))
        }
    }

    @ViewBuilder
    private var idleIcon: some View {
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

private struct BounceOnPress: ViewModifier {
    let isPressed: Bool
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.symbolEffect(.bounce, value: isPressed)
        } else {
            content
        }
    }
}
