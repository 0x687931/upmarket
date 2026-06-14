import Cocoa
import AppKit
import UniformTypeIdentifiers

private let appGroupID = "group.com.upmarket.app"
private let maxInputBytes: Int64 = 500 * 1024 * 1024
private let maxBatchBytes: Int64 = 2 * 1024 * 1024 * 1024
private let maxBatchFiles = 100
private let quickActionStaleAge: TimeInterval = 24 * 60 * 60

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

        let providers = items.flatMap { $0.attachments ?? [] }
        loadFileURLsSerially(from: providers, at: 0, collected: [])
    }

    private func loadFileURLsSerially(from providers: [NSItemProvider], at index: Int, collected: [URL]) {
        guard providers.indices.contains(index), collected.count < maxBatchFiles else {
            convertFiles(collected)
            return
        }

        providers[index].loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var next = collected
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                next.append(url)
            } else if let url = item as? URL {
                next.append(url)
            }
            DispatchQueue.main.async {
                self.loadFileURLsSerially(from: providers, at: index + 1, collected: next)
            }
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

        removeStaleHandoffs(in: container)

        let id = UUID().uuidString
        let handoffDirectory = container
            .appendingPathComponent("QuickActionHandoffs", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: handoffDirectory, withIntermediateDirectories: true)
            var fileNames: [String] = []
            var totalBytes: Int64 = 0

            for (index, url) in urls.enumerated() {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                guard let fileSize = readableRegularFileSize(url) else { continue }
                guard totalBytes + fileSize <= maxBatchBytes else { break }
                totalBytes += fileSize

                let name = "\(index)-\(url.lastPathComponent)"
                let destination = handoffDirectory.appendingPathComponent(name)
                try FileManager.default.copyItem(at: url, to: destination)
                fileNames.append(name)
            }

            guard !fileNames.isEmpty else {
                try? FileManager.default.removeItem(at: handoffDirectory)
                return nil
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

    private func readableRegularFileSize(_ url: URL) -> Int64? {
        guard ToolFormatCapabilityMatrix.accepts(url) else { return nil }
        guard (try? url.checkResourceIsReachable()) == true else { return nil }
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isReadableKey,
            .fileSizeKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]) else { return nil }
        guard values.isRegularFile != false, values.isReadable != false else { return nil }
        guard let fileSize = values.fileSize, Int64(fileSize) <= maxInputBytes else { return nil }
        if values.isUbiquitousItem == true,
           let status = values.ubiquitousItemDownloadingStatus,
           status != .current,
           status != .downloaded {
            return nil
        }
        return Int64(fileSize)
    }

    private func removeStaleHandoffs(in container: URL) {
        let root = container.appendingPathComponent("QuickActionHandoffs", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-quickActionStaleAge)
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true,
                  (values?.contentModificationDate ?? .distantPast) < cutoff else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
