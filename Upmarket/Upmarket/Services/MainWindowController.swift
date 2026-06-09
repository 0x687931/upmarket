import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    static let shared = MainWindowController()

    private init() {
        let rootView = ContentView()
            .environmentObject(ConversionQueue.shared)
            .environmentObject(StoreManager.shared)
            .environmentObject(ModelManager.shared)

        let windowSize = AppTheme.WindowSize.thick
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Upmarket"
        window.minSize = NSSize(width: 500, height: 600)
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(pickFile: Bool = false) {
        guard let window else { return }
        window.centerIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        guard pickFile else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .openFilePicker, object: nil)
        }
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        guard !isVisible else { return }
        center()
    }
}
