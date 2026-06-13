import XCTest
@testable import Upmarket

final class PackCreditLedgerTests: XCTestCase {
    func testVerifiedTransactionCreditsPackOnce() async throws {
        let ledger = makeLedger()

        _ = try await ledger.recordPackPurchase(transactionID: 1001)
        _ = try await ledger.recordPackPurchase(transactionID: 1001)

        let snapshot = try ledger.snapshot()
        XCTAssertEqual(snapshot.purchasedPackCount, 1)
        XCTAssertEqual(snapshot.availableCredits, 5)
    }

    func testConsumptionPersistsAsDebitsAgainstVerifiedCredits() async throws {
        let fileURL = temporaryLedgerURL()
        let ledger = PackCreditLedger(fileURL: fileURL)

        _ = try await ledger.recordPackPurchase(transactionID: 1001)
        let consumed1 = try await ledger.consumeCredit()
        let consumed2 = try await ledger.consumeCredit()

        XCTAssertTrue(consumed1)
        XCTAssertTrue(consumed2)

        let reloaded = PackCreditLedger(fileURL: fileURL)
        XCTAssertEqual(try reloaded.snapshot().availableCredits, 3)
        XCTAssertEqual(try reloaded.snapshot().consumedCreditCount, 2)
    }

    func testCannotConsumeWithoutAvailableCredit() async throws {
        let ledger = makeLedger()

        let consumed = try await ledger.consumeCredit()
        XCTAssertFalse(consumed)
        XCTAssertEqual(try ledger.snapshot().availableCredits, 0)
    }

    func testRevokedTransactionRemovesRemainingPackCredits() async throws {
        let ledger = makeLedger()

        _ = try await ledger.recordPackPurchase(transactionID: 1001)
        let consumed1 = try await ledger.consumeCredit()
        let consumed2 = try await ledger.consumeCredit()
        _ = try await ledger.revokePackPurchase(transactionID: 1001)

        XCTAssertTrue(consumed1)
        XCTAssertTrue(consumed2)

        let snapshot = try ledger.snapshot()
        XCTAssertEqual(snapshot.revokedPackCount, 1)
        XCTAssertEqual(snapshot.revokedCreditCount, 3)
        XCTAssertEqual(snapshot.availableCredits, 0)
    }

    func testNewPurchaseAfterRevocationGetsFreshCredits() async throws {
        let ledger = makeLedger()

        _ = try await ledger.recordPackPurchase(transactionID: 1001)
        let consumed1 = try await ledger.consumeCredit()
        let consumed2 = try await ledger.consumeCredit()
        _ = try await ledger.revokePackPurchase(transactionID: 1001)
        _ = try await ledger.recordPackPurchase(transactionID: 1002)

        XCTAssertTrue(consumed1)
        XCTAssertTrue(consumed2)
        XCTAssertEqual(try ledger.snapshot().availableCredits, 5)
    }

    func testLegacyCreditsMigrateOnce() async throws {
        let ledger = makeLedger()

        _ = try await ledger.migrateLegacyCredits(credits: 3, packsEverPurchased: 2)
        _ = try await ledger.migrateLegacyCredits(credits: 9, packsEverPurchased: 4)

        let snapshot = try ledger.snapshot()
        XCTAssertTrue(snapshot.legacyMigrationComplete)
        XCTAssertEqual(snapshot.migratedCreditCount, 3)
        XCTAssertEqual(snapshot.migratedPackCount, 2)
        XCTAssertEqual(snapshot.purchasedPackCount, 2)
        XCTAssertEqual(snapshot.availableCredits, 3)
    }

    func testCorruptLedgerFailsClosed() async throws {
        let fileURL = temporaryLedgerURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        let ledger = PackCreditLedger(fileURL: fileURL)

        XCTAssertThrowsError(try ledger.snapshot())
        do {
            _ = try await ledger.recordPackPurchase(transactionID: 1001)
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
    }

    private func makeLedger() -> PackCreditLedger {
        PackCreditLedger(fileURL: temporaryLedgerURL())
    }

    private func temporaryLedgerURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("PackCreditLedger.json")
    }
}
