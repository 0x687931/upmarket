import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    static let shared = MainWindowController()

    private init() {
        let mainSize = AppTheme.WindowSize.main
        let rootView = ContentView()
            .environmentObject(ConversionQueue.shared)
            .environmentObject(StoreManager.shared)
            .environmentObject(ModelManager.shared)
            .environmentObject(ConversionHistoryStore.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: mainSize.width, height: mainSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Upmarket"
        window.minSize = NSSize(width: mainSize.width, height: mainSize.height)
        window.maxSize = NSSize(width: mainSize.width, height: mainSize.height)
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(pickFile: Bool = false) {
        guard let window else { return }

        if pickFile {
            let urls = FileAccessService.shared.chooseDocuments(allowsMultipleSelection: true)
            guard !urls.isEmpty else { return }
            window.centerIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .upmarketOpenFiles, object: urls)
            }
        } else {
            window.centerIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        guard !isVisible else { return }
        center()
    }
}
