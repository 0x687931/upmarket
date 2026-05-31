import SwiftUI
import AppKit

/// True liquid glass effect using NSVisualEffectView with behindWindow blending.
/// This is what Dockside uses — it samples the actual pixels behind the shelf
/// and applies blur + vibrancy, creating the glass lens effect.
struct LiquidGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = 12
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material       = material
        view.blendingMode   = blendingMode
        view.state          = .active
        view.wantsLayer     = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material       = material
        nsView.blendingMode   = blendingMode
        nsView.layer?.cornerRadius = cornerRadius
    }
}

/// Tahoe liquid glass — uses the new GlassEffect API on macOS 26+,
/// falls back to NSVisualEffectView on older OS.
struct TahoeGlass: View {
    var cornerRadius: CGFloat = 12

    var body: some View {
        if #available(macOS 26, *) {
            // Native Tahoe liquid glass
            Color.clear
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            // NSVisualEffectView fallback — still very good
            LiquidGlassBackground(cornerRadius: cornerRadius)
        }
    }
}
