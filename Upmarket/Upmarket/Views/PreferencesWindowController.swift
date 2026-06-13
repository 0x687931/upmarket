import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        let rootView = PreferencesView()
            .environmentObject(ModelManager.shared)
            .environmentObject(StoreManager.shared)
            .environmentObject(ConversionHistoryStore.shared)
            .environmentObject(WatchedFolderService.shared)
        let prefsSize = AppTheme.WindowSize.preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: prefsSize.width, height: prefsSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.minSize = NSSize(width: prefsSize.width, height: 400)
        window.maxSize = NSSize(width: prefsSize.width * 1.5, height: NSScreen.main?.frame.height ?? 1000)
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
