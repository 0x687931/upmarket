import AppKit

/// AppDelegate handles app lifecycle, URL scheme handling (from Quick Action),
/// and Services menu integration.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Stay alive as menu bar + shelf app
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Register for Services — tells macOS this app handles the convertToMarkdown service
        NSApp.servicesProvider = self
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        ShelfWindowController.shared.show()
        return false
    }

    // MARK: - URL Scheme handler (from Quick Action extension)
    // upmarket://convert?files=/path/to/file1.pdf,/path/to/file2.docx

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "upmarket", url.host == "convert",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let filesParam = components.queryItems?.first(where: { $0.name == "files" })?.value
            else { continue }

            let filePaths = filesParam.components(separatedBy: ",")
            ShelfWindowController.shared.show()
            for path in filePaths {
                let fileURL = URL(fileURLWithPath: path)
                NotificationCenter.default.post(
                    name: .upmarketConvertFile,
                    object: fileURL
                )
            }
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
