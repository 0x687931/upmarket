import Foundation

final class PackCreditLedger {
    static let creditsPerPack = 5

    struct Snapshot: Equatable {
        let purchasedPackCount: Int
        let revokedPackCount: Int
        let revokedCreditCount: Int
        let migratedCreditCount: Int
        let migratedPackCount: Int
        let legacyMigrationComplete: Bool
        let consumedCreditCount: Int

        var availableCredits: Int {
            let verifiedPackCount = purchasedPackCount - migratedPackCount
            return max(0, (verifiedPackCount * PackCreditLedger.creditsPerPack) + migratedCreditCount - revokedCreditCount - consumedCreditCount)
        }
    }

    private struct Ledger: Codable {
        var creditedTransactionIDs: [String] = []
        var revokedTransactionIDs: [String] = []
        var revokedCreditCount: Int = 0
        var migratedCreditCount: Int = 0
        var migratedPackCount: Int = 0
        var legacyMigrationComplete = false
        var consumedCreditCount: Int = 0

        private enum CodingKeys: String, CodingKey {
            case creditedTransactionIDs
            case revokedTransactionIDs
            case revokedCreditCount
            case migratedCreditCount
            case migratedPackCount
            case legacyMigrationComplete
            case consumedCreditCount
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            creditedTransactionIDs = try container.decodeIfPresent([String].self, forKey: .creditedTransactionIDs) ?? []
            revokedTransactionIDs = try container.decodeIfPresent([String].self, forKey: .revokedTransactionIDs) ?? []
            revokedCreditCount = try container.decodeIfPresent(Int.self, forKey: .revokedCreditCount) ?? 0
            migratedCreditCount = try container.decodeIfPresent(Int.self, forKey: .migratedCreditCount) ?? 0
            migratedPackCount = try container.decodeIfPresent(Int.self, forKey: .migratedPackCount) ?? 0
            legacyMigrationComplete = try container.decodeIfPresent(Bool.self, forKey: .legacyMigrationComplete) ?? false
            consumedCreditCount = try container.decodeIfPresent(Int.self, forKey: .consumedCreditCount) ?? 0
        }
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func snapshot() throws -> Snapshot {
        snapshot(from: try loadLedger())
    }

    @discardableResult
    func migrateLegacyCredits(credits: Int, packsEverPurchased: Int) async throws -> Snapshot {
        var ledger = try loadLedger()
        guard !ledger.legacyMigrationComplete else { return snapshot(from: ledger) }
        ledger.migratedCreditCount = max(0, credits)
        ledger.migratedPackCount = max(0, packsEverPurchased)
        ledger.legacyMigrationComplete = true
        try await save(ledger)
        return snapshot(from: ledger)
    }

    @discardableResult
    func recordPackPurchase(transactionID: UInt64) async throws -> Snapshot {
        var ledger = try loadLedger()
        let id = String(transactionID)
        if !ledger.creditedTransactionIDs.contains(id) {
            ledger.creditedTransactionIDs.append(id)
            try await save(ledger)
        }
        return snapshot(from: ledger)
    }

    @discardableResult
    func revokePackPurchase(transactionID: UInt64) async throws -> Snapshot {
        var ledger = try loadLedger()
        let id = String(transactionID)
        if ledger.creditedTransactionIDs.contains(id),
           !ledger.revokedTransactionIDs.contains(id) {
            ledger.revokedCreditCount += min(snapshot(from: ledger).availableCredits, Self.creditsPerPack)
            ledger.revokedTransactionIDs.append(id)
            try await save(ledger)
        }
        return snapshot(from: ledger)
    }

    @discardableResult
    func consumeCredit() async throws -> Bool {
        var ledger = try loadLedger()
        guard snapshot(from: ledger).availableCredits > 0 else { return false }
        ledger.consumedCreditCount += 1
        try await save(ledger)
        return true
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Upmarket", isDirectory: true)
            .appendingPathComponent("PackCreditLedger.json")
    }

    private func loadLedger() throws -> Ledger {
        guard fileManager.fileExists(atPath: fileURL.path) else { return Ledger() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Ledger.self, from: data)
    }

    private func save(_ ledger: Ledger) async throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(ledger)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        try await FileWriteService.shared.writeMarkdown(jsonString, to: fileURL)
    }

    private func snapshot(from ledger: Ledger) -> Snapshot {
        Snapshot(
            purchasedPackCount: ledger.creditedTransactionIDs.count + ledger.migratedPackCount,
            revokedPackCount: ledger.revokedTransactionIDs.count,
            revokedCreditCount: ledger.revokedCreditCount,
            migratedCreditCount: ledger.migratedCreditCount,
            migratedPackCount: ledger.migratedPackCount,
            legacyMigrationComplete: ledger.legacyMigrationComplete,
            consumedCreditCount: ledger.consumedCreditCount
        )
    }
}
