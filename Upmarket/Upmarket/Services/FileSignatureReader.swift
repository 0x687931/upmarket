import Foundation

/// Efficient file signature caching for watched folder monitoring.
/// Prevents repeated metadata reads and enables stable-file detection.
actor FileSignatureReader {
    private var signatureCache: [URL: (signature: FileSignature, timestamp: Date)] = [:]

    nonisolated static let shared = FileSignatureReader()

    struct FileSignature: Equatable {
        let folderID: UUID
        let name: String
        let size: Int
        let modified: TimeInterval

        init(folderID: UUID, name: String, size: Int, modified: TimeInterval) {
            self.folderID = folderID
            self.name = name
            self.size = size
            self.modified = modified
        }
    }

    /// Get or compute file signature asynchronously with caching.
    /// Signature includes size, name, and modification date (used to detect file changes).
    func getSignature(for url: URL, folderID: UUID) async -> FileSignature? {
        // Check cache (valid for 100ms — file monitor calls repeatedly)
        if let cached = signatureCache[url],
           Date().timeIntervalSince(cached.timestamp) < 0.1 {
            return cached.signature
        }

        let signature = await readSignature(for: url, folderID: folderID)
        if let signature {
            signatureCache[url] = (signature, Date())
        }
        return signature
    }

    /// Clear cache for a URL (call when file changes detected).
    func invalidate(_ url: URL) {
        signatureCache.removeValue(forKey: url)
    }

    // MARK: - Private

    /// Read file metadata asynchronously on background thread.
    private func readSignature(for url: URL, folderID: UUID) async -> FileSignature? {
        await Task.detached(priority: .userInitiated) { [url, folderID] in
            self.readSignatureSync(for: url, folderID: folderID)
        }.value
    }

    /// Synchronous helper (runs in background task).
    private nonisolated func readSignatureSync(for url: URL, folderID: UUID) -> FileSignature? {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]) else { return nil }

        guard values.isDirectory != true, values.isRegularFile != false else { return nil }

        return FileSignature(
            folderID: folderID,
            name: url.lastPathComponent,
            size: values.fileSize ?? 0,
            modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }
}
