import Foundation
import OSLog

/// Watches the shared CLI handoff directory and converts requests as they appear, so any
/// running app instance services the CLI/MCP regardless of URL-scheme/LaunchServices routing.
/// The CLI drops a fully-formed `CLIHandoffs/<uuid>/` (atomic move) and waits for `response.json`.
@MainActor
final class CLIHandoffWatcher {
    static let shared = CLIHandoffWatcher()

    private let fileManager = FileManager.default
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var inFlight = Set<String>()

    func start() {
        guard source == nil, let directory = handoffsDirectory else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Catch anything queued while the app was launching, then watch for new requests.
        scan(directory)

        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            AppLog.conversion.error("CLI handoff watcher could not open \(directory.path, privacy: .public)")
            return
        }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend], queue: .main)
        watcher.setEventHandler { [weak self] in
            guard let self, let directory = self.handoffsDirectory else { return }
            self.scan(directory)
        }
        watcher.setCancelHandler { [weak self] in
            if let fd = self?.descriptor, fd >= 0 { close(fd) }
            self?.descriptor = -1
        }
        source = watcher
        watcher.resume()
    }

    private var handoffsDirectory: URL? {
        CLIHandoffPaths.rootURL(fileManager: fileManager)?
            .appendingPathComponent(CLIHandoffPaths.requestsDirectoryName, isDirectory: true)
    }

    /// Process every complete request that hasn't been answered or started yet (idempotent —
    /// the URL-scheme handler may also fire; whichever runs first wins, the other is skipped).
    private func scan(_ directory: URL) {
        guard let ids = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for id in ids where UUID(uuidString: id) != nil && !inFlight.contains(id) {
            let requestDir = directory.appendingPathComponent(id, isDirectory: true)
            guard fileManager.fileExists(atPath: requestDir.appendingPathComponent("request.json").path),
                  !fileManager.fileExists(atPath: requestDir.appendingPathComponent("response.json").path) else { continue }
            inFlight.insert(id)
            Task { @MainActor in
                await CLIConversionBroker.live()?.process(id: id)
                self.inFlight.remove(id)
            }
        }
    }
}
