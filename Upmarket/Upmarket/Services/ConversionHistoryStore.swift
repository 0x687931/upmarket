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

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        loadImmediately: Bool = true
    ) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.fileManager = fileManager
        self.userDefaults = userDefaults
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

        Task.detached(priority: .utility) { [weak self, record] in
            await self?.saveRecord(record)
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
        do {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            records = []
        } catch {
            AppLog.fileAccess.error("Failed to clear conversion history: \(error.localizedDescription, privacy: .private)")
        }
    }

    func filteredRecords(query: String) -> [ConversionHistoryRecord] {
        records.filter { $0.matches(query: query) }
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Upmarket", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    private func saveRecord(_ record: ConversionHistoryRecord) async {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            let url = directoryURL.appendingPathComponent(record.id.uuidString).appendingPathExtension("json")
            try await FileWriteService.shared.writeMarkdown(String(data: data, encoding: .utf8) ?? "", to: url)
        } catch {
            AppLog.fileAccess.error("Failed to save conversion history: \(error.localizedDescription, privacy: .private)")
        }
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
