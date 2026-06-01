import Cocoa
import AppKit

private let appGroupID = "group.com.upmarket.app"

private struct QuickActionHandoff: Encodable {
    let files: [String]
}

/// Finder Quick Action: right-click file → Quick Actions → "Convert to Markdown"
/// This runs inside a sandboxed extension process.
class ActionViewController: NSViewController {

    override var nibName: NSNib.Name? { return NSNib.Name("ActionViewController") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Process files immediately on load
        processFiles()
    }

    private func processFiles() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            done()
            return
        }

        var urls: [URL] = []
        let group = DispatchGroup()
        let urlQueue = DispatchQueue(label: "com.upmarket.quickaction.urls")

        for item in items {
            for provider in item.attachments ?? [] {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urlQueue.async { urls.append(url) }
                    } else if let url = item as? URL {
                        urlQueue.async { urls.append(url) }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            let collected = urlQueue.sync { urls }
            self.convertFiles(collected)
        }
    }

    private func convertFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { done(); return }
        guard let handoffID = createHandoff(for: urls) else {
            done()
            return
        }

        // Open Upmarket with only an opaque handoff ID. Files are copied into
        // App Group storage so the main app never trusts URL-supplied paths.
        var components = URLComponents()
        components.scheme = "upmarket"
        components.host = "convert"
        components.queryItems = [URLQueryItem(name: "handoff", value: handoffID)]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }

        done()
    }

    private func createHandoff(for urls: [URL]) -> String? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }

        let id = UUID().uuidString
        let handoffDirectory = container
            .appendingPathComponent("QuickActionHandoffs", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: handoffDirectory, withIntermediateDirectories: true)
            var fileNames: [String] = []

            for (index, url) in urls.enumerated() {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let name = "\(index)-\(url.lastPathComponent)"
                let destination = handoffDirectory.appendingPathComponent(name)
                try FileManager.default.copyItem(at: url, to: destination)
                fileNames.append(name)
            }

            let manifest = QuickActionHandoff(files: fileNames)
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: handoffDirectory.appendingPathComponent("manifest.json"), options: .atomic)
            return id
        } catch {
            try? FileManager.default.removeItem(at: handoffDirectory)
            return nil
        }
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
