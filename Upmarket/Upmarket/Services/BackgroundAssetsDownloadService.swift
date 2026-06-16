import BackgroundAssets
import Combine
import Foundation
import OSLog

/// Monitors Background Assets downloads for tier-based runtime and model assets.
///
/// Per TIER_CONTRACT.md, downloads are segmented by tier:
/// - Max: upmarket_ai (~600MB) — Granite-Docling mlx-swift model weights
///
/// Background Assets downloads are scheduled by the UpmarketBackgroundAssetsExtension
/// when the app is installed or updated. This service:
///   - Watches for completed downloads and extracts archives to Application Support.
///   - Lets ModelManager poll or await a specific asset's installation.
///   - Falls back to scheduling a manual download if the extension hasn't run yet.
///
/// Xcode setup required (one-time):
///   1. Add an App Extension target of type "Background Assets" named
///      "UpmarketBackgroundAssetsExtension".
///   2. Add entitlement "com.apple.developer.background-assets" to the main app.
///   3. Add entitlement "com.apple.developer.background-assets-downloader" to the extension.
///   4. Register assets and their download URLs in App Store Connect under your app.
@MainActor
final class BackgroundAssetsDownloadService: NSObject, ObservableObject {

    static let shared = BackgroundAssetsDownloadService()

    // Download identifiers — must match what the extension schedules
    // and what is registered in App Store Connect.
    // See docs/TIER_CONTRACT.md for size and tier requirements.
    static let upmarketAIDownloadID = "com.upmarket.download.upmarket-ai"

    private static let appGroup = "group.com.upmarket.app"

    /// Keyed by download identifier. Nil = not in progress.
    @Published private(set) var activeDownloads: [String: BADownload] = [:]

    private var installationWaiters: [String: [CheckedContinuation<Void, Error>]] = [:]

    override init() {
        super.init()
        if #available(macOS 13.3, *) {
            BADownloadManager.shared.delegate = self
        }
    }

    // MARK: - Public interface

    /// Called by ModelManager when the user taps Download for an AI-tier model.
    /// Returns once the model is extracted into Application Support.
    func install(key: String, progressFile: String) async -> ModelDownloadResult {
        guard #available(macOS 13.3, *) else {
            return ModelDownloadResult(success: false, error: "Background Assets require macOS 13.3 or later.")
        }

        let downloadID = downloadIdentifier(for: key)
        writeProgress(0, "Checking download status…", progressFile: progressFile)

        // If the extension already downloaded the file, fetch and install it.
        if let completed = fetchCompletedDownload(id: downloadID) {
            return await extractAndInstall(key: key, fileURL: completed, progressFile: progressFile)
        }

        // Schedule a download if not already in flight (handles cases where
        // the extension hasn't had a chance to run yet).
        if activeDownloads[downloadID] == nil {
            scheduleDownload(for: key)
        }

        writeProgress(5, "Downloading in background…", progressFile: progressFile)

        // Wait for the BA system to finish and call our delegate.
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                installationWaiters[downloadID, default: []].append(continuation)
            }
            return ModelDownloadResult(success: true, error: nil)
        } catch {
            return ModelDownloadResult(success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Private

    @available(macOS 13.3, *)
    private func fetchCompletedDownload(id: String) -> URL? {
        // BADownloadManager surfaces completed-but-not-yet-handled downloads on relaunch.
        var result: URL?
        BADownloadManager.shared.fetchCurrentDownloads { downloads, _ in
            // completed downloads have no associated active task
            _ = downloads
        }
        // In production this would check the shared container for a completed archive.
        // The delegate method download(_:finishedWithFileURL:) handles the hot path.
        return result
    }

    @available(macOS 13.3, *)
    private func scheduleDownload(for key: String) {
        // Placeholder URLs — replace with App Store Connect registered asset URLs
        // after uploading archives via scripts/build/stage_github_model_assets.py
        // or scripts/build/stage_first_party_model_assets.py.
        guard let url = assetURL(for: key) else {
            AppLog.modelDownload.error("No asset URL configured for Background Assets key=\(key, privacy: .public)")
            return
        }

        let download = BAURLDownload(
            identifier: downloadIdentifier(for: key),
            request: URLRequest(url: url),
            fileSize: estimatedFileSize(for: key),
            applicationGroupIdentifier: Self.appGroup
        )

        do {
            try BADownloadManager.shared.scheduleDownload(download)
            activeDownloads[downloadIdentifier(for: key)] = download
        } catch {
            AppLog.modelDownload.error("BA schedule failed key=\(key, privacy: .public) error=\(error, privacy: .private)")
        }
    }

    private func extractAndInstall(key: String, fileURL: URL, progressFile: String) async -> ModelDownloadResult {
        let destinationURL = destinationURL(for: key)
        let stagingURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(key).ba.install", isDirectory: true)

        writeProgress(60, "Extracting…", progressFile: progressFile)

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: stagingURL.path) {
                try fileManager.removeItem(at: stagingURL)
            }
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

            try await ModelArchiveInstaller.extractTarGz(at: fileURL, to: stagingURL)

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: stagingURL, to: destinationURL)

            let spec = modelSpec(for: key)
            try ModelArchiveInstaller.writeValidationManifest(
                modelKey: key,
                sourceID: spec.sourceID,
                revision: spec.revision,
                expectedFiles: spec.expectedFiles,
                expectedDirs: spec.expectedDirs,
                at: destinationURL
            )

            writeProgress(100, "\(spec.displayName) ready", progressFile: progressFile)
            return ModelDownloadResult(success: true, error: nil)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            AppLog.modelDownload.error("BA install failed key=\(key, privacy: .public) error=\(error, privacy: .private)")
            return ModelDownloadResult(success: false, error: "Could not install model. Try again.")
        }
    }

    private func downloadIdentifier(for key: String) -> String {
        switch key {
        case ModelAsset.upmarketAI.rawValue: return Self.upmarketAIDownloadID
        default: return "com.upmarket.download.\(key)"
        }
    }

    private func destinationURL(for key: String) -> URL {
        // The model is extracted to a flat directory named after the asset key so the
        // native mlx-swift engine can load it via ModelConfiguration(directory:).
        ModelArchiveInstaller.defaultModelsDirectoryURL()
            .appendingPathComponent(key, isDirectory: true)
    }

    private func assetURL(for key: String) -> URL? {
        // These are set in App Store Connect. Override via Info.plist key
        // "UpmarketBAAssetURL_<key>" for local testing if needed.
        let plistKey = "UpmarketBAAssetURL_\(key)"
        if let value = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
           let url = URL(string: value) {
            return url
        }
        return nil
    }

    private func estimatedFileSize(for key: String) -> Int {
        switch key {
        case ModelAsset.upmarketAI.rawValue:
            return 600_000_000  // Model weights (estimate)
        default:
            return 0
        }
    }

    private struct ModelSpec {
        let sourceID: String
        let revision: String
        let displayName: String
        let expectedFiles: [String]
        let expectedDirs: [String]
    }

    private func modelSpec(for key: String) -> ModelSpec {
        switch key {
        case ModelAsset.upmarketAI.rawValue:
            return ModelSpec(
                sourceID: "com.upmarket.models.upmarket-ai",
                revision: "e9939db25d2f296c8678d0491c4609a8c596c50a",
                displayName: "AI Model",
                expectedFiles: ["config.json", "model.safetensors"],
                expectedDirs: []
            )
        default:
            return ModelSpec(sourceID: "", revision: "", displayName: key, expectedFiles: [], expectedDirs: [])
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

// MARK: - BADownloadManagerDelegate

@available(macOS 13.3, *)
extension BackgroundAssetsDownloadService: BADownloadManagerDelegate {

    nonisolated func downloadDidBegin(_ download: BADownload) {
        Task { @MainActor in
            activeDownloads[download.identifier] = download
        }
    }

    nonisolated func download(
        _ download: BADownload,
        didWriteBytes bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalExpectedBytes: Int64
    ) {
        // Progress is surfaced via ModelManager polling or the PreferencesView
        // observing BackgroundAssetsDownloadService.activeDownloads.
    }

    nonisolated func download(_ download: BADownload, finishedWithFileURL fileURL: URL) {
        Task { @MainActor in
            activeDownloads.removeValue(forKey: download.identifier)
            let key = modelKey(for: download.identifier)
            let result = await extractAndInstall(key: key, fileURL: fileURL, progressFile: "")

            for continuation in installationWaiters.removeValue(forKey: download.identifier) ?? [] {
                if result.success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BAInstallError(message: result.error ?? "Install failed"))
                }
            }
        }
    }

    nonisolated func download(_ download: BADownload, failedWithError error: Error) {
        Task { @MainActor in
            activeDownloads.removeValue(forKey: download.identifier)
            AppLog.modelDownload.error("BA download failed id=\(download.identifier, privacy: .public) error=\(error, privacy: .private)")
            for continuation in installationWaiters.removeValue(forKey: download.identifier) ?? [] {
                continuation.resume(throwing: error)
            }
        }
    }

    private func modelKey(for downloadID: String) -> String {
        switch downloadID {
        case Self.upmarketAIDownloadID: return ModelAsset.upmarketAI.rawValue
        default: return downloadID.components(separatedBy: ".").last ?? downloadID
        }
    }
}

private struct BAInstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
