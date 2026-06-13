import Foundation

/// Efficient, cached directory size computation for async use.
/// Prevents 1-3s main-thread stalls when enumerating Python runtime or model directories.
actor DirectorySizeReader {
    private var sizeCache: [URL: CacheEntry] = [:]

    nonisolated static let shared = DirectorySizeReader()

    private struct CacheEntry {
        let size: Int64
        let timestamp: Date

        func isExpired(now: Date = Date()) -> Bool {
            now.timeIntervalSince(timestamp) > 600  // 10 minutes
        }
    }

    /// Compute directory size asynchronously (enumeration off main thread).
    /// Returns 0 if enumeration fails (non-fatal; used for display only).
    /// Caches result for 10 minutes.
    func computeSize(of url: URL) async -> Int64 {
        if let entry = sizeCache[url], !entry.isExpired() {
            return entry.size
        }

        let size = await enumerateDirectorySize(url)
        sizeCache[url] = CacheEntry(size: size, timestamp: Date())
        return size
    }

    /// Invalidate cache (call after file operations that change directory contents).
    func invalidate(_ url: URL) {
        sizeCache.removeValue(forKey: url)
    }

    /// Invalidate entire cache (call when storage settings change).
    func invalidateAll() {
        sizeCache.removeAll(keepingCapacity: true)
    }

    // MARK: - Private

    /// Enumerate directory recursively, summing file sizes.
    /// Runs on background thread; does not block main thread.
    private func enumerateDirectorySize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            self.computeDirectorySizeSync(url)
        }.value
    }

    /// Synchronous helper (runs in background task, safe to block here).
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
                // Skip files we can't read (permission denied, etc.)
                continue
            }
        }
        return totalSize
    }
}
