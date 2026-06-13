import Foundation

/// Maintains O(1) lookup of conversion jobs by UUID.
/// Avoids repeated linear searches when accessing jobs by ID.
actor JobIndexer<Job: Identifiable> where Job.ID == UUID {
    private var idToIndex: [UUID: Int] = [:]

    /// Update index after jobs array changes.
    /// Call whenever the jobs array is modified.
    func rebuild(for jobs: [Job]) {
        idToIndex.removeAll(keepingCapacity: true)
        for (index, job) in jobs.enumerated() {
            idToIndex[job.id] = index
        }
    }

    /// Get the array index for a job ID (if it exists).
    /// Returns nil if job not found (O(1) lookup).
    func index(for id: UUID) -> Int? {
        idToIndex[id]
    }

    /// Get job from array using cached index.
    /// Safer than `jobs[index]` — checks bounds.
    func job(id: UUID, in jobs: [Job]) -> Job? {
        guard let index = idToIndex[id],
              jobs.indices.contains(index) else { return nil }
        return jobs[index]
    }

    /// Mark a job as removed (update index).
    /// Called when job is deleted from array.
    func remove(id: UUID) {
        idToIndex.removeValue(forKey: id)
    }

    /// Mark a job as added at specific index.
    func insert(id: UUID, at index: Int) {
        // Shift indices of all jobs after insertion point
        for (key, existingIndex) in idToIndex where existingIndex >= index {
            idToIndex[key] = existingIndex + 1
        }
        idToIndex[id] = index
    }

    /// Clear all cached indices.
    func clear() {
        idToIndex.removeAll(keepingCapacity: true)
    }
}

// MARK: - Extension for ConversionQueue usage

extension JobIndexer where Job == ConversionJob {
    /// Convenience initializer for ConversionJob.
    nonisolated static func forConversions() -> JobIndexer<ConversionJob> {
        JobIndexer<ConversionJob>()
    }
}
