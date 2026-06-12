import CryptoKit
import Foundation
import OSLog

/// Shared utilities for extracting and installing downloaded model archives.
/// Used by both ODRModelDownloadService and BackgroundAssetsDownloadService.
enum ModelArchiveInstaller {

    // MARK: - Extraction

    /// Extracts a `.tar.gz` archive into `destinationURL` using the system tar.
    static func extractTarGz(at archiveURL: URL, to destinationURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["xzf", archiveURL.path, "-C", destinationURL.path]
            process.standardOutput = Pipe()
            let errorPipe = Pipe()
            process.standardError = errorPipe

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let msg = String(
                        data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    AppLog.modelDownload.error("tar extraction failed: \(msg, privacy: .private)")
                    continuation.resume(throwing: InstallerError.extractionFailed)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Validation manifest

    /// Writes an `upmarket_manifest.json` into `modelURL` for the given model key.
    /// The Python validator requires sha256 checksums of every `expected_files` entry.
    static func writeValidationManifest(
        modelKey: String,
        sourceID: String,
        revision: String,
        expectedFiles: [String],
        expectedDirs: [String],
        at modelURL: URL
    ) throws {
        var hashes: [String: String] = [:]
        for relative in expectedFiles {
            hashes[relative] = try sha256Hex(for: modelURL.appendingPathComponent(relative))
        }

        let manifest: [String: Any] = [
            "manifest_version": 1,
            "model_key": modelKey,
            "source_id": sourceID,
            "revision": revision,
            "expected_files": expectedFiles,
            "expected_dirs": expectedDirs,
            "files": hashes,
            "validated_at": ISO8601DateFormatter().string(from: Date()),
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: modelURL.appendingPathComponent("upmarket_manifest.json"), options: .atomic)
    }

    // MARK: - Path helpers

    static func defaultModelsDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models", isDirectory: true)
    }

    static func defaultRuntimeDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/runtime", isDirectory: true)
    }

    // MARK: - Private

    static func sha256Hex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    enum InstallerError: Error, LocalizedError {
        case extractionFailed
        case missingExpectedPath(String)

        var errorDescription: String? {
            switch self {
            case .extractionFailed: return "Model archive could not be extracted."
            case .missingExpectedPath(let p): return "Downloaded model files were incomplete: \(p)"
            }
        }
    }
}
