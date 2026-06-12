import Foundation
import OSLog

/// Installs models that are physically bundled inside the app (not downloaded separately).
///
/// The layout model (~172 MB) ships inside the .app bundle as a folder reference so it
/// is available from first launch without any network request. This service copies it to
/// the models directory where the Python bridge expects to find it, then writes the
/// validation manifest.
///
/// Xcode setup required (one-time):
///   1. Run `scripts/ci/ensure_models.sh` to populate resources/models/layout/ via LFS.
///   2. In Xcode, drag `resources/models/layout/` into the Upmarket target as a folder
///      reference (blue folder icon, NOT a group). Tick "Copy items if needed" and select
///      the Upmarket target.
///   3. Verify the folder appears in the app bundle under Contents/Resources/layout/.
struct BundledModelService: Sendable {

    private static let layoutBundleSubdirectory = "layout"
    private static let destinationURL = ModelArchiveInstaller.defaultModelsDirectoryURL()
        .appendingPathComponent("layout", isDirectory: true)

    // MARK: - Startup install

    /// Called at app startup. Copies bundled models to Application Support if not already
    /// present. Returns immediately (sync) after the copy — fast enough for the launch path.
    static func installBundledModelsIfNeeded() {
        let destination = Self.destinationURL
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        guard let sourceURL = Bundle.main.url(forResource: Self.layoutBundleSubdirectory, withExtension: nil) else {
            AppLog.modelDownload.debug("Bundled layout model not found in app bundle — skipping startup install")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            try ModelArchiveInstaller.writeValidationManifest(
                modelKey: "layout",
                sourceID: "com.upmarket.models.layout",
                revision: "72661864b9c29fb7cced011822786bed346811ea",
                expectedFiles: ["config.json"],
                expectedDirs: ["model_artifacts"],
                at: destination
            )
            AppLog.modelDownload.info("Bundled layout model installed at startup")
        } catch {
            AppLog.modelDownload.error("Bundled layout model startup install failed: \(error, privacy: .private)")
        }
    }

    // MARK: - On-demand copy (user-triggered "download")

    /// Called when the user explicitly triggers a layout model install (e.g. after deletion).
    /// Returns a result compatible with ModelManager's DownloadModelHandler typealias.
    func install(progressFile: String) async -> ModelDownloadResult {
        guard let sourceURL = Bundle.main.url(forResource: Self.layoutBundleSubdirectory, withExtension: nil) else {
            return ModelDownloadResult(success: false, error: "Enhanced model is not included in this build.")
        }

        let destination = Self.destinationURL
        writeProgress(10, "Installing Enhanced model…", progressFile: progressFile)

        let stagingURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".layout.install", isDirectory: true)

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: stagingURL.path) { try fm.removeItem(at: stagingURL) }
            try fm.copyItem(at: sourceURL, to: stagingURL)

            writeProgress(80, "Finalising…", progressFile: progressFile)

            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: stagingURL, to: destination)

            try ModelArchiveInstaller.writeValidationManifest(
                modelKey: "layout",
                sourceID: "com.upmarket.models.layout",
                revision: "72661864b9c29fb7cced011822786bed346811ea",
                expectedFiles: ["config.json"],
                expectedDirs: ["model_artifacts"],
                at: destination
            )

            writeProgress(100, "Enhanced model ready", progressFile: progressFile)
            return ModelDownloadResult(success: true, error: nil)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            AppLog.modelDownload.error("Bundled layout install failed: \(error, privacy: .private)")
            return ModelDownloadResult(success: false, error: "Could not install Enhanced model.")
        }
    }

    private func writeProgress(_ percent: Double, _ message: String, progressFile: String) {
        guard !progressFile.isEmpty else { return }
        let clamped = min(max(percent, 0), 100)
        let line = #"{"percent":\#(clamped),"message":"\#(message)"}"# + "\n"
        let url = URL(fileURLWithPath: progressFile)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
