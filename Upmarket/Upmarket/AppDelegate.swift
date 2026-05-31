import AppKit

/// AppDelegate handles app lifecycle so Upmarket behaves like a proper
/// menu-bar + shelf app — stays alive when all windows are closed,
/// and quits cleanly via Cmd+Q or the menu bar Quit button.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Stay alive — the shelf and menu bar are the UI, not windows
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure Cmd+Q works even when NSPanel is the only visible UI
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Clicking the Dock icon shows the shelf
        ShelfWindowController.shared.show()
        return false
    }
}
