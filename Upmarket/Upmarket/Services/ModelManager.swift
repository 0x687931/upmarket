import Darwin
import Foundation
import Combine

struct ModelDownloadResult: Sendable {
    let success: Bool
    let error: String?
}

nonisolated struct ModelStatus: Equatable, Sendable {
    let key: String
    let name: String
    let description: String
    let isDownloaded: Bool
    let sizeMB: Int
    let isRequired: Bool
    let tier: String
    let isAvailable: Bool
    let error: String?
    let storageDirectory: String

    init(
        key: String,
        name: String,
        description: String,
        isDownloaded: Bool,
        sizeMB: Int,
        isRequired: Bool,
        tier: String,
        isAvailable: Bool = true,
        error: String? = nil,
        storageDirectory: String? = nil
    ) {
        self.key = key
        self.name = name
        self.description = description
        self.isDownloaded = isDownloaded
        self.sizeMB = sizeMB
        self.isRequired = isRequired
        self.tier = tier
        self.isAvailable = isAvailable
        self.error = error
        self.storageDirectory = storageDirectory ?? key
    }

    func withDownloadState(isDownloaded: Bool, error: String?) -> ModelStatus {
        ModelStatus(
            key: key,
            name: name,
            description: description,
            isDownloaded: isDownloaded,
            sizeMB: sizeMB,
            isRequired: isRequired,
            tier: tier,
            isAvailable: isAvailable,
            error: error,
            storageDirectory: storageDirectory
        )
    }
}

enum ModelInstallState: Equatable, Sendable {
    case unchecked
    case checking
    case ready
    case failed(String)
}

final class ModelManager: ObservableObject {

    nonisolated static let shared = ModelManager()

    typealias CheckModelsHandler = @Sendable () async throws -> [ModelStatus]
    typealias DownloadModelHandler = @Sendable (_ key: String, _ progressFile: String) async -> ModelDownloadResult
    typealias OfflineModeHandler = @Sendable () async -> Void

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

    private(set) var downloadingModelKey: String? {
        willSet { objectWillChange.send() }
    }

    private(set) var downloadError: String? {
        willSet { objectWillChange.send() }
    }

    private(set) var installState: ModelInstallState = .unchecked {
        willSet { objectWillChange.send() }
    }

    private let checkModelsHandler: CheckModelsHandler
    private let downloadModelHandler: DownloadModelHandler
    private let offlineModeHandler: OfflineModeHandler
    private let modelsDirectoryURL: URL
    let runtimeDirectoryURL: URL

    init(
        models: [ModelStatus] = [],
        modelsDirectoryURL: URL? = nil,
        runtimeDirectoryURL: URL? = nil,
        checkModelsHandler: @escaping CheckModelsHandler = {
            ModelManager.nativeModelStatuses(in: ModelManager.defaultModelsDirectoryURL())
        },
        downloadModelHandler: @escaping DownloadModelHandler = ModelManager.makeDownloadHandler(),
        offlineModeHandler: @escaping OfflineModeHandler = { }
    ) {
        self.models = models
        self.modelsDirectoryURL = modelsDirectoryURL ?? Self.defaultModelsDirectoryURL()
        self.runtimeDirectoryURL = runtimeDirectoryURL ?? Self.defaultRuntimeDirectoryURL()
        self.checkModelsHandler = checkModelsHandler
        self.downloadModelHandler = downloadModelHandler
        self.offlineModeHandler = offlineModeHandler
    }

    // MARK: - Asset state

    /// The set of assets currently installed and validated on disk.
    var downloadedAssets: Set<ModelAsset> {
        Set(models.filter(\.isDownloaded).compactMap { ModelAsset(rawValue: $0.key) })
    }

    /// True when all assets required for `capability` are present on disk.
    func assetsReady(for capability: ConversionCapability) -> Bool {
        capability.requiredAssets.allSatisfy { downloadedAssets.contains($0) }
    }

    // MARK: - Gating

    /// Builds an AppTierGate snapshot for the current model state and supplied tier.
    /// Pass this to UI and services instead of calling individual check functions.
    func gate(tier: AppTier) -> AppTierGate {
        AppTierGate(
            tier: tier,
            downloadedAssets: downloadedAssets,
            deviceSupportsRuntime: DeviceCapability.shared.isAppleSilicon,
            aiFeatureEnabled: FeatureFlags.shared.aiAvailable,
            aiFeatureUnavailableReason: FeatureFlags.shared.aiUnavailableReason
        )
    }

    /// Ensures models have been checked, then returns the gate. Use before AI conversion.
    func gateAfterChecking(tier: AppTier) async -> AppTierGate {
        switch installState {
        case .unchecked, .checking: await checkModelsNow()
        case .ready, .failed: break
        }
        return gate(tier: tier)
    }

    // MARK: - Size display helpers

    var aiSizeMB: Int  { ModelAsset.upmarketAI.sizeMB }
    var proSizeMB: Int { ModelAsset.upmarketAI.sizeMB }

    /// Native model inventory: each downloadable asset's on-disk presence. Replaces the
    /// former Python helper's model listing. Only the Max-tier AI weights remain.
    static func nativeModelStatuses(in modelsDirectoryURL: URL) -> [ModelStatus] {
        ModelAsset.allCases.map { asset in
            let dir = modelsDirectoryURL.appendingPathComponent(asset.rawValue, isDirectory: true)
            return ModelStatus(
                key: asset.rawValue,
                name: asset.displayName,
                description: asset.displayName,
                isDownloaded: modelDirectoryIsPopulated(dir),
                sizeMB: asset.sizeMB,
                isRequired: false,
                tier: asset.requiredTier == .max ? "max" : "pro",
                storageDirectory: asset.rawValue
            )
        }
    }

    /// An mlx-swift model directory is usable when it has a config and weight shards.
    private static func modelDirectoryIsPopulated(_ url: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return items.contains("config.json") && items.contains { $0.hasSuffix(".safetensors") }
    }

    func actualInstalledSizeMB(_ asset: ModelAsset) -> Int {
        guard downloadedAssets.contains(asset) else { return 0 }
        let bytes = directorySize(modelDirectoryURL(for: asset))
        return Int(bytes / 1_000_000)
    }

    /// Filesystem directory of a downloaded model asset — used by native engines
    /// (e.g. `GraniteDoclingEngine`) to load weights without re-downloading.
    func modelDirectoryURL(for asset: ModelAsset) -> URL {
        let modelDir = models.first { $0.key == asset.rawValue }?.storageDirectory ?? asset.rawValue
        return modelsDirectoryURL.appendingPathComponent(modelDir, isDirectory: true)
    }

    var checkError: String? {
        guard case .failed(let message) = installState else { return nil }
        return message
    }

    var hasCheckedModels: Bool {
        if case .ready = installState { return true }
        return false
    }

    // MARK: - Storage

    var downloadedModelCount: Int {
        models.filter(\.isDownloaded).count
    }

    var downloadedModelEstimatedSizeMB: Int {
        models.filter(\.isDownloaded).reduce(0) { $0 + $1.sizeMB }
    }

    /// Total disk space used by currently installed, recognized models in bytes.
    var totalStorageUsed: Int64 {
        let directories = Set(models.filter(\.isDownloaded).map(\.storageDirectory))
        return directories.reduce(Int64(0)) { total, directory in
            total + directorySize(modelsDirectoryURL.appendingPathComponent(directory, isDirectory: true))
        }
    }

    var totalStorageUsedFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalStorageUsed, countStyle: .file)
    }

    /// Remove a specific model — user can re-download later
    func deleteModel(key: String) {
        if let index = models.firstIndex(where: { $0.key == key }) {
            models[index] = models[index].withDownloadState(isDownloaded: false, error: "not downloaded")
        }
        let directory = models.first { $0.key == key }?.storageDirectory ?? key
        let cacheURL = modelsDirectoryURL.appendingPathComponent(directory, isDirectory: true)
        try? FileManager.default.removeItem(at: cacheURL)
        checkModels()
    }

    /// Remove all downloaded models — app falls back to fast path
    func deleteAllModels() {
        models = models.map { $0.withDownloadState(isDownloaded: false, error: "not downloaded") }
        try? FileManager.default.removeItem(at: modelsDirectoryURL)
        checkModels()
    }

    private static func defaultModelsDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models", isDirectory: true)
    }

    static func defaultRuntimeDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/runtime", isDirectory: true)
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
        Task { await checkModelsNow() }
    }

    func checkModelsNow() async {
        installState = .checking
        downloadError = nil
        do {
            models = try await checkModelsHandler()
            installState = .ready
        } catch {
            models = []
            installState = .failed("Upmarket couldn't check local model files. Try again from Settings.")
        }
    }

    func downloadRequiredModels() {
        downloadModels(keys: models.filter(\.isRequired).map(\.key))
    }

    /// Download all missing assets needed for `capability`.
    /// The gate is checked first; if blocked, `downloadError` is set and nothing downloads.
    func downloadAssets(for capability: ConversionCapability, gate: AppTierGate) {
        let missing = gate.missingDownloadableAssets(for: capability)

        if missing.isEmpty {
            if let reason = gate.downloadUnavailableReason(for: capability.requiredAssets.first ?? .upmarketAI) {
                downloadError = reason
            }
            return
        }
        downloadModels(keys: missing.map(\.rawValue))
    }

    /// Download a single asset if the gate permits it.
    func downloadAsset(_ asset: ModelAsset, gate: AppTierGate) {
        if let reason = gate.downloadUnavailableReason(for: asset) {
            downloadError = reason
            return
        }
        if downloadedAssets.contains(asset) { return }
        downloadModels(keys: [asset.rawValue])
    }

    // MARK: - Private

    private static func makeDownloadHandler() -> DownloadModelHandler {
        { key, progressFile in
#if DEBUG
            return await FirstPartyModelDownloadService(modelsDirectoryURL: ModelManager.defaultModelsDirectoryURL())
                .downloadModel(key: key, progressFile: progressFile)
#else
            switch key {
            case ModelAsset.upmarketAI.rawValue:
                return await BackgroundAssetsDownloadService.shared.install(key: key, progressFile: progressFile)
            default:
                return ModelDownloadResult(success: false, error: "Unknown model key: \(key)")
            }
#endif
        }
    }

    private func downloadModels(keys: [String]) {
        guard !isDownloading else { return }
        guard !keys.isEmpty else {
            downloadError = "No local models are available to download. Try checking again."
            return
        }
        isDownloading = true
        downloadError = nil
        downloadProgress = 0
        downloadMessage = "Starting download…"
        downloadingModelKey = keys.first

        Task.detached(priority: .userInitiated) {
            for key in keys {
                await MainActor.run {
                    self.downloadingModelKey = key
                }
                await self.downloadSingleModel(key: key)
                let hasError = await MainActor.run { self.downloadError != nil }
                if hasError { break }
            }

            let hadError = await MainActor.run { self.downloadError != nil }
            if !hadError {
                await self.offlineModeHandler()
            }

            await MainActor.run {
                self.isDownloading = false
                self.downloadingModelKey = nil
                if !hadError {
                    self.checkModels()
                }
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

        let resultBox = ModelDownloadResultBox()

        // Start download in a separate task so we can monitor progress.
        let downloadTask = Task.detached {
            let result = await self.downloadModelHandler(key, progressFile)
            await resultBox.set(result)
        }

        // Monitor progress file for changes (event-driven instead of polling).
        await monitorDownloadProgress(progressFile: progressFile, downloadTask: downloadTask, resultBox: resultBox)

        try? FileManager.default.removeItem(atPath: progressFile)
    }

    private func monitorDownloadProgress(progressFile: String, downloadTask: Task<Void, Never>, resultBox: ModelDownloadResultBox) async {
        let descriptor = open(progressFile, O_EVTONLY)
        guard descriptor >= 0 else {
            // Fallback to polling if file monitoring unavailable
            await pollingDownloadProgress(progressFile: progressFile, downloadTask: downloadTask, resultBox: resultBox)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                if let line = Self.lastProgressLine(atPath: progressFile),
                   let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let percent = json["percent"] as? Double ?? 0
                    let message = json["message"] as? String ?? ""
                    self?.downloadProgress = percent
                    self?.downloadMessage = message
                }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()

        // Wait for download to complete
        while await resultBox.result == nil && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)  // Check every 100ms for completion
        }

        source.cancel()

        // Process final result
        if let result = await resultBox.result {
            await downloadTask.value
            await MainActor.run { [weak self] in
                if result.success {
                    self?.downloadProgress = max(self?.downloadProgress ?? 0, 100)
                    if self?.downloadMessage.isEmpty ?? true {
                        self?.downloadMessage = "Download complete"
                    }
                } else {
                    self?.downloadError = result.error ?? "Download failed"
                }
            }
        }
    }

    private func pollingDownloadProgress(progressFile: String, downloadTask: Task<Void, Never>, resultBox: ModelDownloadResultBox) async {
        while await resultBox.result == nil && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)

            if let line = Self.lastProgressLine(atPath: progressFile),
               let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let percent = json["percent"] as? Double ?? 0
                let message = json["message"] as? String ?? ""
                await MainActor.run { [weak self] in
                    self?.downloadProgress = percent
                    self?.downloadMessage = message
                }
            }
        }

        if let result = await resultBox.result {
            await downloadTask.value
            await MainActor.run { [weak self] in
                if result.success {
                    self?.downloadProgress = max(self?.downloadProgress ?? 0, 100)
                    if self?.downloadMessage.isEmpty ?? true {
                        self?.downloadMessage = "Download complete"
                    }
                } else {
                    self?.downloadError = result.error ?? "Download failed"
                }
            }
        }
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

private actor ModelDownloadResultBox {
    private(set) var result: ModelDownloadResult?

    func set(_ result: ModelDownloadResult) {
        self.result = result
    }
}
