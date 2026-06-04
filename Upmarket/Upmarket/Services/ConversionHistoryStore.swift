import Combine
import Foundation
import OSLog

@MainActor
final class ConversionHistoryStore: ObservableObject {
    static let shared = ConversionHistoryStore()

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
        do {
            try save(record)
            records.removeAll { $0.id == record.id }
            records.insert(record, at: 0)
            records.sort { $0.createdAt > $1.createdAt }
        } catch {
            AppLog.fileAccess.error("Failed to save conversion history: \(error.localizedDescription, privacy: .private)")
        }
    }

    func load() {
        guard isEnabled else {
            records = []
            return
        }

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            records = []
            return
        }

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = urls
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
            records = []
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

    private func save(_ record: ConversionHistoryRecord) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        let url = directoryURL.appendingPathComponent(record.id.uuidString).appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
    }
}
