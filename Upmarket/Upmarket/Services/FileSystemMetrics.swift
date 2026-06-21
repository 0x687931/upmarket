import Foundation
import OSLog

/// Unified file system metric reader: file size, directory size, and file signatures.
/// All operations are async/cached for performance.
actor FileSystemMetrics {
    nonisolated static let shared = FileSystemMetrics()

    private var fileSizeCache: [URL: CacheEntry] = [:]
    private var directorySizeCache: [URL: CacheEntry] = [:]
    private var signatureCache: [SignatureCacheKey: (signature: FileSignature, timestamp: Date)] = [:]

    private struct CacheEntry {
        let size: Int64
        let timestamp: Date
        let ttlSeconds: TimeInterval

        func isExpired(now: Date = Date()) -> Bool {
            now.timeIntervalSince(timestamp) > ttlSeconds
        }
    }

    // MARK: - File Size

    /// Read file size asynchronously, optimized by storage location (local vs. iCloud).
    func readFileSize(_ url: URL) async -> Int64 {
        let cacheKey = url.standardizedFileURL
        if let entry = fileSizeCache[cacheKey], !entry.isExpired() {
            return entry.size
        }

        let isICloud = await checkIsICloudFile(url)
        let size = isICloud ? await readICloudFileSize(url) : await readLocalFileSize(url)
        // File sizes affect safety limits, so only coalesce near-simultaneous reads.
        // A long-lived cache could accept a file that changed after it was selected.
        fileSizeCache[cacheKey] = CacheEntry(size: size, timestamp: Date(), ttlSeconds: 0.25)
        return size
    }

    /// Read file size (local file only, fast sync read).
    private func readLocalFileSize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }.value
    }

    /// Read file size (iCloud file with NSFileCoordinator to prevent deletion during read).
    private func readICloudFileSize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .userInitiated) { [url] in
            var size: Int64 = 0
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var error: NSError?

            coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &error) { coordURL in
                let attributes = try? FileManager.default.attributesOfItem(atPath: coordURL.path)
                size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            }

            return size
        }.value
    }

    private func checkIsICloudFile(_ url: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) { [url] in
            (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        }.value
    }

    // MARK: - Directory Size

    /// Compute directory size asynchronously (enumeration off main thread).
    /// Caches result for 10 minutes.
    func readDirectorySize(_ url: URL) async -> Int64 {
        let cacheKey = url.standardizedFileURL
        if let entry = directorySizeCache[cacheKey], !entry.isExpired() {
            return entry.size
        }

        let size = await enumerateDirectorySize(url)
        directorySizeCache[cacheKey] = CacheEntry(size: size, timestamp: Date(), ttlSeconds: 600)
        return size
    }

    private func enumerateDirectorySize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            self.computeDirectorySizeSync(url)
        }.value
    }

    private nonisolated func computeDirectorySizeSync(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = values.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        return totalSize
    }

    // MARK: - File Signature

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

    private struct SignatureCacheKey: Hashable {
        let url: URL
        let folderID: UUID
    }

    /// Get or compute file signature asynchronously (used to detect file changes).
    func getFileSignature(for url: URL, folderID: UUID) async -> FileSignature? {
        let cacheKey = SignatureCacheKey(url: url.standardizedFileURL, folderID: folderID)
        if let cached = signatureCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 0.1 {
            return cached.signature
        }

        let signature = await readSignature(for: url, folderID: folderID)
        if let signature {
            signatureCache[cacheKey] = (signature, Date())
        }
        return signature
    }

    private func readSignature(for url: URL, folderID: UUID) async -> FileSignature? {
        await Task.detached(priority: .userInitiated) { [url, folderID] in
            self.readSignatureSync(for: url, folderID: folderID)
        }.value
    }

    private nonisolated func readSignatureSync(for url: URL, folderID: UUID) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileType = attributes[.type] as? FileAttributeType,
              fileType == .typeRegular else { return nil }

        return FileSignature(
            folderID: folderID,
            name: url.lastPathComponent,
            size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
            modified: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        )
    }

    // MARK: - Cache Invalidation

    func invalidate(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        fileSizeCache.removeValue(forKey: standardizedURL)
        directorySizeCache.removeValue(forKey: standardizedURL)
        signatureCache = signatureCache.filter { $0.key.url != standardizedURL }
    }

    func invalidateAll() {
        fileSizeCache.removeAll(keepingCapacity: true)
        directorySizeCache.removeAll(keepingCapacity: true)
        signatureCache.removeAll(keepingCapacity: true)
    }
}
