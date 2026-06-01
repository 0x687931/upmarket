import Foundation
import Combine

struct ModelStatus: Sendable {
    let key: String
    let name: String
    let description: String
    let isDownloaded: Bool
    let sizeMB: Int
    let isRequired: Bool
    let tier: String
}

final class ModelManager: ObservableObject {

    static let shared = ModelManager()

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var models: [ModelStatus] = [] {
        willSet { objectWillChange.send() }
    }

    private(set) var isDownloading = false {
        willSet { objectWillChange.send() }
    }

    private(set) var downloadProgress: Double = 0 {
        willSet { objectWillChange.send() }
    }

    private(set) var downloadMessage = "" {
        willSet { objectWillChange.send() }
    }

    private(set) var downloadError: String? {
        willSet { objectWillChange.send() }
    }

    private let pythonWorker = PythonWorker()

    private init() {}

    // Fast local conversion works without downloaded models.
    var allRequiredDownloaded: Bool { true }

    var enhancedDownloaded: Bool {
        models.first { $0.tier == "enhanced" }?.isDownloaded ?? false
    }

    var proDownloaded: Bool {
        let proModels = models.filter { $0.tier == "pro" }
        return !proModels.isEmpty && proModels.allSatisfy(\.isDownloaded)
    }

    var requiredSizeMB: Int {
        models.filter(\.isRequired).reduce(0) { $0 + $1.sizeMB }
    }

    var proSizeMB: Int {
        models.filter { $0.tier == "pro" }.reduce(0) { $0 + $1.sizeMB }
    }

    // MARK: - Storage

    /// Total disk space used by downloaded models in bytes
    var totalStorageUsed: Int64 {
        let cacheURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models")
        return directorySize(cacheURL)
    }

    var totalStorageUsedFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalStorageUsed, countStyle: .file)
    }

    /// Remove a specific model — user can re-download later
    func deleteModel(key: String) {
        let cacheURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models/\(key)")
        try? FileManager.default.removeItem(at: cacheURL)
        checkModels()
    }

    /// Remove all downloaded models — app falls back to fast path
    func deleteAllModels() {
        let cacheURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models")
        try? FileManager.default.removeItem(at: cacheURL)
        checkModels()
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return enumerator.compactMap { $0 as? URL }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0) { $0 + Int64($1) }
    }

    // MARK: - Public

    func checkModels() {
        Task.detached(priority: .userInitiated) {
            let result = (try? await self.pythonWorker.checkModels()) ?? []
            await MainActor.run {
                self.models = result
            }
        }
    }

    func downloadRequiredModels() {
        downloadModels(keys: models.filter(\.isRequired).map(\.key))
    }

    func downloadProModels() {
        guard DeviceCapability.shared.supportsUpmarketAI else {
            downloadError = DeviceCapability.shared.upmarketAIUnavailableReason
            return
        }
        downloadModels(keys: models.filter { $0.tier == "pro" && !$0.isDownloaded }.map(\.key))
    }

    // MARK: - Private

    private func downloadModels(keys: [String]) {
        guard !isDownloading else { return }
        isDownloading = true
        downloadError = nil
        downloadProgress = 0

        Task.detached(priority: .userInitiated) {
            for key in keys {
                await self.downloadSingleModel(key: key)
                if await self.downloadError != nil { break }
            }

            await self.pythonWorker.setOfflineMode()

            await MainActor.run {
                self.isDownloading = false
                self.checkModels()
            }
        }
    }

    private func downloadSingleModel(key: String) async {
        let workspace = try? AppWorkspace.create(prefix: "model-download")
        if workspace == nil {
            try? FileManager.default.createDirectory(at: AppWorkspace.baseDirectory, withIntermediateDirectories: true)
        }
        defer {
            if let workspace {
                AppWorkspace.remove(workspace)
            }
        }

        let progressFile = (workspace ?? AppWorkspace.baseDirectory)
            .appendingPathComponent("upmarket_\(key)_progress.jsonl")
            .path

        // Clear any existing progress file
        try? FileManager.default.removeItem(atPath: progressFile)

        // Start download in a separate task so we can poll progress
        let downloadTask = Task.detached {
            await self.pythonWorker.downloadModel(key: key, progressFile: progressFile)
        }

        // Poll progress file every 500ms
        while !downloadTask.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)

            if let line = Self.lastProgressLine(atPath: progressFile),
               let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let percent = json["percent"] as? Double ?? 0
                let message = json["message"] as? String ?? ""
                await MainActor.run {
                    self.downloadProgress = percent
                    self.downloadMessage = message
                }
            }

            // Check if download completed
            let result = await downloadTask.value
            if !result.success {
                await MainActor.run { self.downloadError = result.error ?? "Download failed" }
            }
            break
        }

        try? FileManager.default.removeItem(atPath: progressFile)
    }

    private static func lastProgressLine(atPath path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return nil }
        let bytesToRead = min(UInt64(8192), fileSize)
        try? handle.seek(toOffset: fileSize - bytesToRead)
        let data = handle.readDataToEndOfFile()
        guard let chunk = String(data: data, encoding: .utf8) else { return nil }
        return chunk
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last
            .map(String.init)
    }
}
