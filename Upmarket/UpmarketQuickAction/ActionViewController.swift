import Cocoa
import AppKit

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

        for item in items {
            for provider in item.attachments ?? [] {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    } else if let url = item as? URL {
                        urls.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            self.convertFiles(urls)
        }
    }

    private func convertFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { done(); return }

        // Open Upmarket and send the files to it via URL scheme
        // Upmarket registers upmarket:// to receive files from extensions
        var components = URLComponents()
        components.scheme = "upmarket"
        components.host = "convert"

        let urlStrings = urls.map { $0.path }.joined(separator: ",")
        components.queryItems = [URLQueryItem(name: "files", value: urlStrings)]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }

        done()
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
