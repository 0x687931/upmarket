import CryptoKit
import Foundation
import OSLog

struct FirstPartyModelDownloadService: Sendable {
    typealias DataLoader = @Sendable (URL) async throws -> Data
    typealias FileDownloader = @Sendable (URL) async throws -> URL

    private let modelsDirectoryURL: URL
    private let manifestBaseURL: @Sendable () -> URL?
    private let dataLoader: DataLoader
    private let fileDownloader: FileDownloader
    private let fileManager: FileManager

    init(
        modelsDirectoryURL: URL? = nil,
        manifestBaseURL: @escaping @Sendable () -> URL? = Self.defaultManifestBaseURL,
        dataLoader: @escaping DataLoader = Self.defaultDataLoader,
        fileDownloader: @escaping FileDownloader = Self.defaultFileDownloader,
        fileManager: FileManager = .default
    ) {
        self.modelsDirectoryURL = modelsDirectoryURL ?? Self.defaultModelsDirectoryURL()
        self.manifestBaseURL = manifestBaseURL
        self.dataLoader = dataLoader
        self.fileDownloader = fileDownloader
        self.fileManager = fileManager
    }

    func downloadModel(key: String, progressFile: String) async -> ModelDownloadResult {
        do {
            let spec = try ModelDownloadCatalog.spec(for: key)
            guard let baseURL = manifestBaseURL() else {
                throw ModelDownloadError.missingManifestBaseURL
            }

            let manifestURL = baseURL.appendingPathComponent("\(key).json")
            writeProgress(0, "Checking model manifest…", progressFile: progressFile)
            let manifest = try await loadManifest(at: manifestURL, spec: spec)

            let stagingURL = modelsDirectoryURL.appendingPathComponent(".\(key).download", isDirectory: true)
            let destinationURL = modelsDirectoryURL.appendingPathComponent(spec.storageDirectory, isDirectory: true)
            try removeIfPresent(stagingURL)
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

            do {
                if let archive = manifest.archive {
                    try await downloadAndExtractArchive(
                        archive,
                        key: key,
                        manifestURL: manifestURL,
                        stagingURL: stagingURL,
                        progressFile: progressFile
                    )
                } else {
                    try await downloadFiles(
                        manifest.files,
                        manifestURL: manifestURL,
                        stagingURL: stagingURL,
                        progressFile: progressFile
                    )
                }
                try validateExpectedPaths(spec: spec, modelURL: stagingURL)
                try writeValidationManifest(spec: spec, files: manifest.files, modelURL: stagingURL)

                try fileManager.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
                try removeIfPresent(destinationURL)
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
                writeProgress(100, "\(spec.displayName) ready", progressFile: progressFile)
                return ModelDownloadResult(success: true, error: nil)
            } catch {
                try? removeIfPresent(stagingURL)
                throw error
            }
        } catch {
            AppLog.modelDownload.error("First-party model download failed key=\(key, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            return ModelDownloadResult(success: false, error: userMessage(for: error))
        }
    }

    private func loadManifest(at url: URL, spec: ModelDownloadSpec) async throws -> ModelSourceManifest {
        let data = try await dataLoader(url)
        let manifest = try JSONDecoder().decode(ModelSourceManifest.self, from: data)

        guard manifest.manifestVersion == ModelDownloadCatalog.manifestVersion else {
            throw ModelDownloadError.manifestMismatch("manifest version")
        }
        guard manifest.modelKey == spec.key else {
            throw ModelDownloadError.manifestMismatch("model key")
        }
        guard manifest.sourceID == spec.sourceID else {
            throw ModelDownloadError.manifestMismatch("source ID")
        }
        guard manifest.revision == spec.revision else {
            throw ModelDownloadError.manifestMismatch("revision")
        }
        guard manifest.storageDirectory == spec.storageDirectory else {
            throw ModelDownloadError.manifestMismatch("storage directory")
        }
        guard manifest.expectedFiles == spec.expectedFiles else {
            throw ModelDownloadError.manifestMismatch("expected files")
        }
        guard manifest.expectedDirs == spec.expectedDirs else {
            throw ModelDownloadError.manifestMismatch("expected directories")
        }
        guard !manifest.files.isEmpty || manifest.archive != nil else {
            throw ModelDownloadError.emptyManifest
        }

        return manifest
    }

    // MARK: - Individual file download (Apple CDN)

    private func downloadFiles(
        _ files: [ModelSourceFile],
        manifestURL: URL,
        stagingURL: URL,
        progressFile: String
    ) async throws {
        let total = files.count
        for (index, file) in files.enumerated() {
            guard isSafeRelativePath(file.path) else {
                throw ModelDownloadError.unsafePath(file.path)
            }
            guard let sourceURL = file.resolvedURL(relativeTo: manifestURL) else {
                throw ModelDownloadError.invalidURL(file.url)
            }

            let percent = 5 + (Double(index) / Double(max(total, 1))) * 85
            writeProgress(percent, "Downloading \(index + 1) of \(total)…", progressFile: progressFile)

            let temporaryURL = try await fileDownloader(sourceURL)
            defer { try? fileManager.removeItem(at: temporaryURL) }

            let actualSize = await FileSystemMetrics.shared.readFileSize(temporaryURL)
            if let expectedSize = file.bytes, expectedSize != actualSize {
                throw ModelDownloadError.sizeMismatch(file.path)
            }

            let actualHash = try sha256Hex(for: temporaryURL)
            guard actualHash == file.sha256.lowercased() else {
                throw ModelDownloadError.checksumMismatch(file.path)
            }

            let destinationURL = stagingURL.appendingPathComponent(file.path)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try removeIfPresent(destinationURL)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    // MARK: - Archive download (GitHub CDN)

    private func downloadAndExtractArchive(
        _ archive: ModelSourceArchive,
        key: String,
        manifestURL: URL,
        stagingURL: URL,
        progressFile: String
    ) async throws {
        guard let archiveURL = archive.resolvedURL(relativeTo: manifestURL) else {
            throw ModelDownloadError.invalidURL(archive.url)
        }

        // Partial file lives outside the staging dir so it survives retries.
        // Staging dir is wiped on each attempt; the partial carries progress across them.
        let partialURL = modelsDirectoryURL.appendingPathComponent(".\(key).archive.partial")

        let downloadedURL = try await downloadWithResume(
            from: archiveURL,
            expectedTotalBytes: archive.bytes,
            partialFileURL: partialURL,
            progressFile: progressFile,
            progressStart: 2,
            progressEnd: 78
        )

        writeProgress(80, "Verifying archive…", progressFile: progressFile)
        let actualHash = try sha256Hex(for: downloadedURL)
        guard actualHash == archive.sha256.lowercased() else {
            // Bad checksum — delete partial so next attempt starts clean.
            try? fileManager.removeItem(at: downloadedURL)
            throw ModelDownloadError.checksumMismatch("archive")
        }

        writeProgress(83, "Extracting…", progressFile: progressFile)
        try await extractTarGz(at: downloadedURL, to: stagingURL)

        // Partial is no longer needed after successful extraction.
        try? fileManager.removeItem(at: partialURL)
        writeProgress(95, "Verifying installation…", progressFile: progressFile)
    }

    /// Downloads `url` to `partialFileURL`, resuming from existing bytes if present.
    /// Writes download progress to `progressFile` between `progressStart` and `progressEnd`.
    private func downloadWithResume(
        from url: URL,
        expectedTotalBytes: Int64?,
        partialFileURL: URL,
        progressFile: String,
        progressStart: Double,
        progressEnd: Double
    ) async throws -> URL {
        try fileManager.createDirectory(
            at: partialFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Determine how many bytes we already have.
        let existingBytes: Int64
        if fileManager.fileExists(atPath: partialFileURL.path) {
            existingBytes = (try? fileManager.attributesOfItem(atPath: partialFileURL.path)[.size] as? Int64) ?? 0
        } else {
            existingBytes = 0
            fileManager.createFile(atPath: partialFileURL.path, contents: nil)
        }

        // If we already have all the bytes (re-run after checksum fail clears the partial),
        // skip the network round-trip.
        if let total = expectedTotalBytes, existingBytes >= total, total > 0 {
            return partialFileURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            writeProgress(progressStart, "Resuming download…", progressFile: progressFile)
        } else {
            writeProgress(progressStart, "Starting download…", progressFile: progressFile)
        }

        let handle = try FileHandle(forWritingTo: partialFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard httpStatus == 200 || httpStatus == 206 else {
            throw URLError(.badServerResponse)
        }

        // Compute the full expected size for progress reporting.
        let contentLength = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
        let fullTotal: Int64
        if let expected = expectedTotalBytes {
            fullTotal = expected
        } else if contentLength > 0 {
            fullTotal = existingBytes + contentLength
        } else {
            fullTotal = -1
        }

        var written: Int64 = existingBytes
        var buffer = Data(capacity: 256 * 1024)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if fullTotal > 0 {
                    let fraction = min(Double(written) / Double(fullTotal), 1.0)
                    let pct = progressStart + (progressEnd - progressStart) * fraction
                    writeProgress(pct, "Downloading \(formatBytes(written)) of \(formatBytes(fullTotal))…", progressFile: progressFile)
                } else {
                    writeProgress(progressStart, "Downloading \(formatBytes(written))…", progressFile: progressFile)
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }

        return partialFileURL
    }

    private func extractTarGz(at archiveURL: URL, to destinationURL: URL) async throws {
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
                    continuation.resume(throwing: ModelDownloadError.archiveExtractionFailed)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Validation

    private func validateExpectedPaths(spec: ModelDownloadSpec, modelURL: URL) throws {
        for relative in spec.expectedFiles {
            guard fileManager.isReadableFile(atPath: modelURL.appendingPathComponent(relative).path) else {
                throw ModelDownloadError.missingExpectedPath(relative)
            }
        }

        for relative in spec.expectedDirs {
            let directoryURL = modelURL.appendingPathComponent(relative, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil),
                  enumerator.nextObject() != nil else {
                throw ModelDownloadError.missingExpectedPath(relative)
            }
        }
    }

    private func writeValidationManifest(
        spec: ModelDownloadSpec,
        files: [ModelSourceFile],
        modelURL: URL
    ) throws {
        // The Python validator requires sha256 checksums for every expected_files entry.
        // Compute those first, then add any remaining individually-downloaded files.
        var hashes: [String: String] = [:]
        for relative in spec.expectedFiles {
            hashes[relative] = try sha256Hex(for: modelURL.appendingPathComponent(relative))
        }
        for file in files where hashes[file.path] == nil {
            hashes[file.path] = try sha256Hex(for: modelURL.appendingPathComponent(file.path))
        }

        let manifest = ModelValidationManifest(
            manifestVersion: ModelDownloadCatalog.manifestVersion,
            modelKey: spec.key,
            sourceID: spec.sourceID,
            revision: spec.revision,
            expectedFiles: spec.expectedFiles,
            expectedDirs: spec.expectedDirs,
            files: hashes,
            validatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let data = try JSONEncoder.upmarketModelManifest.encode(manifest)
        try data.write(to: modelURL.appendingPathComponent("upmarket_manifest.json"), options: .atomic)
    }

    // MARK: - Utilities

    private func writeProgress(_ percent: Double, _ message: String, progressFile: String) {
        guard !progressFile.isEmpty else { return }
        let clamped = min(max(percent, 0), 100)
        let line = #"{"percent":\#(clamped),"message":"\#(message)"}"# + "\n"
        let url = URL(fileURLWithPath: progressFile)
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: progressFile),
           let handle = FileHandle(forWritingAtPath: progressFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func userMessage(for error: Error) -> String {
        if let error = error as? ModelDownloadError {
            return error.errorDescription
        }
        return "Model download failed. Check your connection and try again."
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func sha256Hex(for url: URL) throws -> String {
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

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("..") else {
            return false
        }
        return true
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return "\(bytes / 1024) KB"
    }

    nonisolated private static func defaultManifestBaseURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["UPMARKET_MODEL_MANIFEST_BASE_URL"],
           let url = URL(string: value),
           !value.isEmpty {
            return url
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "UpmarketModelManifestBaseURL") as? String,
           let url = URL(string: value),
           !value.isEmpty {
            return url
        }
        return nil
    }

    nonisolated private static func defaultModelsDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models", isDirectory: true)
    }

    nonisolated private static func defaultDataLoader(_ url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    nonisolated private static func defaultFileDownloader(_ url: URL) async throws -> URL {
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        return downloadedURL
    }
}

private struct ModelDownloadSpec: Sendable {
    let key: String
    let displayName: String
    let sourceID: String
    let revision: String
    let storageDirectory: String
    let expectedFiles: [String]
    let expectedDirs: [String]
}

private enum ModelDownloadCatalog {
    static let manifestVersion = 1

    private static let specs = [
        ModelDownloadSpec(
            key: "upmarket_ai",
            displayName: "Upmarket AI",
            sourceID: "com.upmarket.models.upmarket-ai",
            revision: "e9939db25d2f296c8678d0491c4609a8c596c50a",
            storageDirectory: "upmarket_ai",
            expectedFiles: [
                "added_tokens.json",
                "chat_template.jinja",
                "config.json",
                "generation_config.json",
                "merges.txt",
                "model.safetensors",
                "model.safetensors.index.json",
                "preprocessor_config.json",
                "processor_config.json",
                "special_tokens_map.json",
                "tokenizer.json",
                "tokenizer_config.json",
                "vocab.json",
            ],
            expectedDirs: []
        ),
        // LFM2.5-VL 1.6B (8-bit mlx). Revision/expected_files must match scripts/models/
        // stage_model_assets.py and the hosted manifest.
        ModelDownloadSpec(
            key: "lfm25_vl",
            displayName: "Advanced AI for Tables & Layout",
            sourceID: "com.upmarket.models.lfm25-vl",
            revision: "051260290c8361562915be1b0292636a6ac8a7a3",
            storageDirectory: "lfm25_vl",
            expectedFiles: [
                "chat_template.jinja",
                "config.json",
                "generation_config.json",
                "model.safetensors",
                "model.safetensors.index.json",
                "processor_config.json",
                "tokenizer.json",
                "tokenizer_config.json",
            ],
            expectedDirs: []
        ),
    ]

    static func spec(for key: String) throws -> ModelDownloadSpec {
        guard let spec = specs.first(where: { $0.key == key }) else {
            throw ModelDownloadError.unknownModel
        }
        return spec
    }
}

private struct ModelSourceManifest: Decodable {
    let manifestVersion: Int
    let modelKey: String
    let sourceID: String
    let revision: String
    let storageDirectory: String
    let expectedFiles: [String]
    let expectedDirs: [String]
    let archive: ModelSourceArchive?
    let files: [ModelSourceFile]

    private enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case modelKey = "model_key"
        case sourceID = "source_id"
        case revision
        case storageDirectory = "storage_dir"
        case expectedFiles = "expected_files"
        case expectedDirs = "expected_dirs"
        case archive
        case files
    }
}

// A single downloadable archive (used by the GitHub CDN path).
// When present, the manifest's `files` array is ignored in favour of
// downloading and extracting this archive.
private struct ModelSourceArchive: Decodable {
    let url: String
    let sha256: String
    let bytes: Int64?

    func resolvedURL(relativeTo manifestURL: URL) -> URL? {
        if let absolute = URL(string: url), absolute.scheme != nil {
            return absolute
        }
        return URL(string: url, relativeTo: manifestURL.deletingLastPathComponent())?.absoluteURL
    }
}

private struct ModelSourceFile: Codable {
    let path: String
    let url: String
    let sha256: String
    let bytes: Int64?

    func resolvedURL(relativeTo manifestURL: URL) -> URL? {
        if let absolute = URL(string: url), absolute.scheme != nil {
            return absolute
        }
        return URL(string: url, relativeTo: manifestURL.deletingLastPathComponent())?.absoluteURL
    }
}

private struct ModelValidationManifest: Encodable {
    let manifestVersion: Int
    let modelKey: String
    let sourceID: String
    let revision: String
    let expectedFiles: [String]
    let expectedDirs: [String]
    let files: [String: String]
    let validatedAt: String

    private enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case modelKey = "model_key"
        case sourceID = "source_id"
        case revision
        case expectedFiles = "expected_files"
        case expectedDirs = "expected_dirs"
        case files
        case validatedAt = "validated_at"
    }
}

private enum ModelDownloadError: Error {
    case unknownModel
    case missingManifestBaseURL
    case manifestMismatch(String)
    case emptyManifest
    case invalidURL(String)
    case unsafePath(String)
    case sizeMismatch(String)
    case checksumMismatch(String)
    case missingExpectedPath(String)
    case archiveExtractionFailed

    var errorDescription: String {
        switch self {
        case .unknownModel:
            return "Unknown model."
        case .missingManifestBaseURL:
            return "Model download is not available in this build."
        case .manifestMismatch:
            return "Model manifest did not match this Upmarket build."
        case .emptyManifest:
            return "Model manifest did not list any files."
        case .invalidURL:
            return "Model manifest contains an invalid download URL."
        case .unsafePath:
            return "Model manifest contains an unsafe file path."
        case .sizeMismatch:
            return "Downloaded model file size did not match the manifest."
        case .checksumMismatch:
            return "Downloaded model file checksum did not match the manifest."
        case .missingExpectedPath:
            return "Downloaded model files were incomplete."
        case .archiveExtractionFailed:
            return "Model archive could not be extracted."
        }
    }
}

private extension JSONEncoder {
    static var upmarketModelManifest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
