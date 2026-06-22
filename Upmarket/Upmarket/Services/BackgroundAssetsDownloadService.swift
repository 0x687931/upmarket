import BackgroundAssets
import Combine
import Foundation
import OSLog
import StoreKit
import System

/// Drives Apple-hosted **managed** Background Assets for the Max-tier model packs.
///
/// Both packs use an `onDemand` download policy, so the app requests availability when the
/// user enables a model. Apple hosts and stores the packs; we never copy them into Application
/// Support and never persist their resolved URLs (those are process-lifetime values).
///
///   - Max: granite_docling (~600MB) — Granite-Docling mlx-swift weights (default AI engine)
///   - Max: lfm25_vl (~2.0GB)       — LFM2.5-VL mlx-swift weights (opt-in alternative)
///
/// Pack IDs come from `ModelAsset.assetPackID` (the single source, matched by
/// resources/asset-packs/*.json and App Store Connect). Debug builds bypass this entirely and
/// use `FirstPartyModelDownloadService` against local directories — see `ModelManager`.
@MainActor
final class BackgroundAssetsDownloadService: NSObject, ObservableObject {

    static let shared = BackgroundAssetsDownloadService()

    /// Maps a model key (ModelAsset.rawValue) to its Apple-hosted managed asset-pack ID.
    static func packID(for key: String) -> String? {
        ModelAsset(rawValue: key)?.assetPackID
    }

    // MARK: - Download

    /// Ensures the managed pack for `key` is available locally, mirroring progress into the
    /// existing progress-file contract that ModelManager polls. Returns when the pack is ready.
    func install(key: String, progressFile: String) async -> ModelDownloadResult {
        guard let asset = ModelAsset(rawValue: key) else {
            return ModelDownloadResult(success: false, error: "Unknown model key: \(key)")
        }
        let packID = asset.assetPackID
        writeProgress(0, "Preparing download…", progressFile: progressFile)

        // Mirror status into the progress file while ensureLocalAvailability runs. Completion
        // is decided by ensureLocalAvailability, not the stream, so a stream-shape mismatch
        // can only affect the progress bar, never correctness.
        let progressTask = Task { [weak self] in
            await self?.streamProgress(packID: packID, progressFile: progressFile)
        }
        defer { progressTask.cancel() }

        do {
            let pack = try await AssetPackManager.shared.assetPack(withID: packID)
            try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
            writeProgress(100, "\(asset.displayName) ready", progressFile: progressFile)
            return ModelDownloadResult(success: true, error: nil)
        } catch {
            AppLog.modelDownload.error("Managed pack download failed id=\(packID, privacy: .public) error=\(error, privacy: .private)")
            return ModelDownloadResult(success: false, error: "Could not download the model. Try again.")
        }
    }

    // MARK: - Lookup / status / removal (managed backend)

    /// Process-lifetime directory of a downloaded managed pack. Do not persist this URL.
    /// Resolves directly to the directory containing `config.json` (the pack's top-level
    /// directory is named after the model key); fails explicitly if that is not the case.
    func managedModelDirectory(for asset: ModelAsset) async throws -> URL {
        let url = try AssetPackManager.shared.url(for: FilePath(asset.rawValue))
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path) else {
            throw ManagedPackError.invalidModelDirectory
        }
        return url
    }

    /// Whether the managed pack is already on disk. `assetPackIsAvailableLocally` needs macOS
    /// 26.4; to keep the 26.0 deployment target we resolve the pack path and verify its required
    /// top-level config file. `url(for:)` alone is not an availability signal.
    func isAvailableLocally(_ asset: ModelAsset) async -> Bool {
        (try? await managedModelDirectory(for: asset)) != nil
    }

    func remove(_ asset: ModelAsset) async throws {
        try await AssetPackManager.shared.remove(assetPackWithID: asset.assetPackID)
    }

    // MARK: - Progress

    // This only feeds the progress bar; `ensureLocalAvailability` owns completion.
    private func streamProgress(packID: String, progressFile: String) async {
        for await status in AssetPackManager.shared.statusUpdates(forAssetPackWithID: packID) {
            switch status {
            case .downloading(_, let progress):
                let percent = min(max(progress.fractionCompleted * 100, 1), 99)
                writeProgress(percent, "Downloading…", progressFile: progressFile)
            default:
                continue
            }
        }
    }

    private func writeProgress(_ percent: Double, _ message: String, progressFile: String) {
        guard !progressFile.isEmpty else { return }
        let clamped = min(max(percent, 0), 100)
        let line = #"{"percent":\#(clamped),"message":"\#(message)"}"# + "\n"
        let url = URL(fileURLWithPath: progressFile)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: progressFile),
           let handle = FileHandle(forWritingAtPath: progressFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) { try? handle.write(contentsOf: data) }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private enum ManagedPackError: LocalizedError {
    case invalidModelDirectory
    var errorDescription: String? {
        switch self {
        case .invalidModelDirectory:
            return "The model package is missing required files (config.json)."
        }
    }
}
