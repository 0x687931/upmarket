import AppKit
import SwiftUI

@MainActor
final class ReportProblemWindowController: NSWindowController {
    static let shared = ReportProblemWindowController()

    private init() {
        let reportSize = AppTheme.WindowSize.modal
        let rootView = ReportProblemView()
            .environmentObject(ConversionQueue.shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: reportSize.width, height: reportSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Report a Problem"
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
