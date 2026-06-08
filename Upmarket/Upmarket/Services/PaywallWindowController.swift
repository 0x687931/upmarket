import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController: NSWindowController {

    static let shared = PaywallWindowController()

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Unlock Upmarket"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(
            rootView: PaywallView(onDismiss: { [weak panel] in
                panel?.close()
            })
                .environmentObject(StoreManager.shared)
        )
        panel.contentView = hosting

        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Escape to dismiss

extension PaywallWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // Escape
                self?.window?.close()
                return nil
            }
            return event
        }
    }
}
