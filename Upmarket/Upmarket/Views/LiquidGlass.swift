import SwiftUI
import AppKit

/// True liquid glass — fully transparent with blur and vibrancy.
/// Uses NSVisualEffectView .behindWindow so it refracts whatever is behind it.
struct LiquidGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = 12

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material     = .hudWindow        // lightest, most transparent material
        view.blendingMode = .behindWindow     // blurs actual screen content behind it
        view.state        = .active
        view.wantsLayer   = true
        view.layer?.cornerRadius   = cornerRadius
        view.layer?.masksToBounds  = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
}
