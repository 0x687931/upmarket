import AppKit

private let appGroupID = "group.com.upmarket.app"

private struct QuickActionHandoff: Decodable {
    let files: [String]
}

/// AppDelegate handles app lifecycle, URL scheme handling (from Quick Action),
/// and Services menu integration.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Stay alive as menu bar + shelf app
    }

    func applicationWillTerminate(_ notification: Notification) {
        ConversionQueue.shared.cancelAll()
        AppWorkspace.removeStaleWorkspaces()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = self
        MemoryPressureMonitor.shared.start()

        // Observe conversion state for Dock tile animation
        NotificationCenter.default.addObserver(
            self, selector: #selector(conversionStarted),
            name: .upmarketConversionStarted, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(conversionEnded),
            name: .upmarketConversionEnded, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(showPaywall),
            name: .showPaywall, object: nil
        )
    }

    @objc private func conversionStarted() {
        ConversionIconLayerView.startDockAnimation()
    }

    @objc private func conversionEnded() {
        ConversionIconLayerView.stopDockAnimation()
    }

    @objc private func showPaywall() {
        Task { @MainActor in
            PaywallWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        ShelfWindowController.shared.show()
        return false
    }

    // MARK: - URL Scheme handler (from Quick Action extension)
    // upmarket://convert?handoff=<uuid>

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "upmarket", url.host == "convert",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let handoffID = components.queryItems?.first(where: { $0.name == "handoff" })?.value
            else { continue }

            openQuickActionHandoff(id: handoffID)
        }
    }

    private func openQuickActionHandoff(id: String) {
        guard UUID(uuidString: id) != nil,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return }

        let handoffDirectory = container
            .appendingPathComponent("QuickActionHandoffs", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        let manifestURL = handoffDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let handoff = try? JSONDecoder().decode(QuickActionHandoff.self, from: data)
        else { return }

        ShelfWindowController.shared.show()
        for fileName in handoff.files where !fileName.contains("/") {
            NotificationCenter.default.post(
                name: .upmarketConvertFile,
                object: handoffDirectory.appendingPathComponent(fileName)
            )
        }
    }

    // MARK: - Services menu handler

    @objc func convertToMarkdown(_ pasteboard: NSPasteboard,
                                  userData: String?,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !items.isEmpty else { return }

        ShelfWindowController.shared.show()
        for url in items {
            NotificationCenter.default.post(name: .upmarketConvertFile, object: url)
        }
    }
}

extension Notification.Name {
    static let upmarketConvertFile = Notification.Name("upmarket.convertFile")
}
