import Foundation
import OSLog

/// Thread-safe utility for reading file size efficiently, with special handling for iCloud files.
/// - Local files: Fast async read via resourceValues on background thread
/// - iCloud files: NSFileCoordinator ensures file stays available during read
actor FileSizeReader {
    private var sizeCache: [URL: CacheEntry] = [:]

    nonisolated static let shared = FileSizeReader()

    private struct CacheEntry {
        let size: Int64
        let timestamp: Date

        func isExpired(now: Date = Date()) -> Bool {
            now.timeIntervalSince(timestamp) > 300  // 5 minutes
        }
    }

    /// Read file size asynchronously, optimized by storage location (local vs. iCloud).
    /// Returns 0 if size cannot be determined (non-fatal; logging only).
    func readSize(_ url: URL) async -> Int64 {
        if let entry = sizeCache[url], !entry.isExpired() {
            return entry.size
        }

        let size = await readSizeUncached(url)
        sizeCache[url] = CacheEntry(size: size, timestamp: Date())
        return size
    }

    /// Clear cached size for a URL (call after file operations that change size).
    func invalidate(_ url: URL) {
        sizeCache.removeValue(forKey: url)
    }

    // MARK: - Private

    private func readSizeUncached(_ url: URL) async -> Int64 {
        let isICloud = await checkIsICloudFile(url)
        return isICloud ? await readICloudFileSize(url) : await readLocalFileSize(url)
    }

    /// Local file: Direct resourceValues read on background thread (10-50µs typically).
    private func readLocalFileSize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return Int64(size)
        }.value
    }

    /// iCloud file: NSFileCoordinator ensures the file won't be deleted/modified
    /// while we read its size.
    private func readICloudFileSize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .userInitiated) { [url] in
            var size: Int64 = 0
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var error: NSError?

            coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &error) { coordURL in
                let bytes = (try? coordURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                size = Int64(bytes)
            }

            return size
        }.value
    }

    /// Check if file is iCloud-backed (may trigger brief metadata lookup).
    private func checkIsICloudFile(_ url: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) { [url] in
            (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        }.value
    }
}
