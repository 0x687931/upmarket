import Combine
import Foundation
import OSLog

@MainActor
final class ConversionHistoryStore: ObservableObject {
    static let shared = ConversionHistoryStore(loadImmediately: false)

    @Published private(set) var records: [ConversionHistoryRecord] = []
    @Published var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                load()
            } else {
                clear()
            }
        }
    }

    private static let enabledDefaultsKey = "upmarket.keepConversionHistory"

    private let directoryURL: URL
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let persistence: ConversionHistoryPersistence
    private var persistenceGeneration = 0
    private var pendingPersistenceTasks: [UUID: Task<Void, Never>] = [:]
    private var persistenceTail = Task<Void, Never> {}

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        loadImmediately: Bool = true
    ) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.persistence = ConversionHistoryPersistence(
            directoryURL: self.directoryURL,
            fileManager: fileManager
        )
        self.isEnabled = userDefaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
        if loadImmediately {
            load()
        }
    }

    func record(job: ConversionJob, output: ConversionOutput) {
        guard isEnabled else { return }
        let record = ConversionHistoryRecord(job: job, output: output)
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        records.sort { $0.createdAt > $1.createdAt }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(record)
        } catch {
            AppLog.fileAccess.error("Failed to encode conversion history: \(error.localizedDescription, privacy: .private)")
            return
        }

        let generation = persistenceGeneration
        trackPersistenceTask { [persistence] in
            await persistence.save(data, id: record.id, generation: generation)
        }
    }

    func load() {
        guard isEnabled else {
            records = []
            return
        }

        records = Self.loadRecords(from: directoryURL, fileManager: fileManager)
    }

    func loadDeferred() {
        guard isEnabled else {
            records = []
            return
        }

        let directoryURL = self.directoryURL
        let fileManager = self.fileManager
        Task.detached(priority: .utility) { [directoryURL, fileManager] in
            let records = Self.loadRecords(from: directoryURL, fileManager: fileManager)
            await MainActor.run { [weak self] in
                guard let self, self.isEnabled else { return }
                self.records = Self.mergeLoadedRecords(records, with: self.records)
            }
        }
    }

    func clear() {
        persistenceGeneration += 1
        let generation = persistenceGeneration
        records = []
        trackPersistenceTask { [persistence] in
            await persistence.clear(generation: generation)
        }
    }

    func filteredRecords(query: String) -> [ConversionHistoryRecord] {
        records.filter { $0.matches(query: query) }
    }

    func waitForPendingWrites() async {
        while !pendingPersistenceTasks.isEmpty {
            let tasks = Array(pendingPersistenceTasks.values)
            for task in tasks {
                await task.value
            }
        }
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Upmarket", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    private func trackPersistenceTask(
        _ operation: @escaping @Sendable () async -> Void
    ) {
        let id = UUID()
        let previous = persistenceTail
        let task = Task(priority: .utility) { [weak self] in
            await previous.value
            await operation()
            await MainActor.run {
                _ = self?.pendingPersistenceTasks.removeValue(forKey: id)
            }
        }
        persistenceTail = task
        pendingPersistenceTasks[id] = task
    }

    nonisolated private static func loadRecords(from directoryURL: URL, fileManager: FileManager) -> [ConversionHistoryRecord] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return urls
                .filter { $0.pathExtension == "json" }
                .compactMap { url in
                    do {
                        let data = try Data(contentsOf: url)
                        return try decoder.decode(ConversionHistoryRecord.self, from: data)
                    } catch {
                        AppLog.fileAccess.error("Ignoring corrupt conversion history record: \(error.localizedDescription, privacy: .private)")
                        return nil
                    }
                }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            AppLog.fileAccess.error("Failed to load conversion history: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    nonisolated private static func mergeLoadedRecords(
        _ loadedRecords: [ConversionHistoryRecord],
        with currentRecords: [ConversionHistoryRecord]
    ) -> [ConversionHistoryRecord] {
        let merged = Dictionary(
            uniqueKeysWithValues: (currentRecords + loadedRecords).map { ($0.id, $0) }
        )
        return merged.values.sorted { $0.createdAt > $1.createdAt }
    }
}

private actor ConversionHistoryPersistence {
    private let directoryURL: URL
    private let fileManager: FileManager
    private var generation = 0

    init(directoryURL: URL, fileManager: FileManager) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func save(_ data: Data, id: UUID, generation requestedGeneration: Int) {
        guard requestedGeneration == generation else { return }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let url = directoryURL
                .appendingPathComponent(id.uuidString)
                .appendingPathExtension("json")
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.fileAccess.error("Failed to save conversion history: \(error.localizedDescription, privacy: .private)")
        }
    }

    func clear(generation requestedGeneration: Int) {
        guard requestedGeneration >= generation else { return }
        generation = requestedGeneration
        do {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
        } catch {
            AppLog.fileAccess.error("Failed to clear conversion history: \(error.localizedDescription, privacy: .private)")
        }
    }
}
