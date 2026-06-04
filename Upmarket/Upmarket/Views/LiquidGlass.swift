import SwiftUI
import AppKit

/// True liquid glass — fully transparent with blur and vibrancy.
/// Uses NSVisualEffectView .behindWindow so it refracts whatever is behind it.
struct LiquidGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = 12
    var opacity: CGFloat = 0.72

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material     = .hudWindow        // lightest, most transparent material
        view.blendingMode = .behindWindow     // blurs actual screen content behind it
        view.state        = .active
        view.alphaValue   = opacity
        view.wantsLayer   = true
        view.layer?.cornerRadius   = cornerRadius
        view.layer?.masksToBounds  = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
        nsView.alphaValue = opacity
    }
}

struct ContextualLiquidGlassBackground: View {
    var cornerRadius: CGFloat = 12
    var opacity: CGFloat = 0.72
    var solidFillOpacity: Double = 0
    var isTargeted = false
    var isConverting = false
    var hasError = false

    var body: some View {
        LiquidGlassBackground(cornerRadius: cornerRadius, opacity: opacity)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(solidFillOpacity))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(tint)
                }
                .allowsHitTesting(false)
            }
            .shadow(
                color: isConverting ? Color.accentColor.opacity(0.25) : .clear,
                radius: isConverting ? 20 : 0
            )
            .animation(.easeInOut(duration: 0.2), value: isTargeted)
            .animation(.easeInOut(duration: 0.16), value: solidFillOpacity)
            .animation(.easeInOut(duration: 0.25), value: isConverting)
            .animation(.easeInOut(duration: 0.2), value: hasError)
    }

    private var tint: Color {
        if hasError {
            return Color.red.opacity(0.03)
        }
        if isTargeted {
            return Color.accentColor.opacity(0.04)
        }
        return .clear
    }
}
