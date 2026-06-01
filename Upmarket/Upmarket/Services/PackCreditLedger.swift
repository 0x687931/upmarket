import Foundation

final class PackCreditLedger {
    static let creditsPerPack = 5

    struct Snapshot: Equatable {
        let purchasedPackCount: Int
        let revokedPackCount: Int
        let revokedCreditCount: Int
        let consumedCreditCount: Int

        var availableCredits: Int {
            max(0, (purchasedPackCount * PackCreditLedger.creditsPerPack) - revokedCreditCount - consumedCreditCount)
        }
    }

    private struct Ledger: Codable {
        var creditedTransactionIDs: [String] = []
        var revokedTransactionIDs: [String] = []
        var revokedCreditCount: Int = 0
        var consumedCreditCount: Int = 0

        private enum CodingKeys: String, CodingKey {
            case creditedTransactionIDs
            case revokedTransactionIDs
            case revokedCreditCount
            case consumedCreditCount
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            creditedTransactionIDs = try container.decodeIfPresent([String].self, forKey: .creditedTransactionIDs) ?? []
            revokedTransactionIDs = try container.decodeIfPresent([String].self, forKey: .revokedTransactionIDs) ?? []
            revokedCreditCount = try container.decodeIfPresent(Int.self, forKey: .revokedCreditCount) ?? 0
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
    func recordPackPurchase(transactionID: UInt64) throws -> Snapshot {
        var ledger = try loadLedger()
        let id = String(transactionID)
        if !ledger.creditedTransactionIDs.contains(id) {
            ledger.creditedTransactionIDs.append(id)
            try save(ledger)
        }
        return snapshot(from: ledger)
    }

    @discardableResult
    func revokePackPurchase(transactionID: UInt64) throws -> Snapshot {
        var ledger = try loadLedger()
        let id = String(transactionID)
        if ledger.creditedTransactionIDs.contains(id),
           !ledger.revokedTransactionIDs.contains(id) {
            ledger.revokedCreditCount += min(snapshot(from: ledger).availableCredits, Self.creditsPerPack)
            ledger.revokedTransactionIDs.append(id)
            try save(ledger)
        }
        return snapshot(from: ledger)
    }

    @discardableResult
    func consumeCredit() throws -> Bool {
        var ledger = try loadLedger()
        guard snapshot(from: ledger).availableCredits > 0 else { return false }
        ledger.consumedCreditCount += 1
        try save(ledger)
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

    private func save(_ ledger: Ledger) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(ledger)
        try data.write(to: fileURL, options: .atomic)
    }

    private func snapshot(from ledger: Ledger) -> Snapshot {
        Snapshot(
            purchasedPackCount: ledger.creditedTransactionIDs.count,
            revokedPackCount: ledger.revokedTransactionIDs.count,
            revokedCreditCount: ledger.revokedCreditCount,
            consumedCreditCount: ledger.consumedCreditCount
        )
    }
}
