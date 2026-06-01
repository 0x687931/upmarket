import XCTest
@testable import Upmarket

final class PackCreditLedgerTests: XCTestCase {
    func testVerifiedTransactionCreditsPackOnce() throws {
        let ledger = makeLedger()

        try ledger.recordPackPurchase(transactionID: 1001)
        try ledger.recordPackPurchase(transactionID: 1001)

        let snapshot = try ledger.snapshot()
        XCTAssertEqual(snapshot.purchasedPackCount, 1)
        XCTAssertEqual(snapshot.availableCredits, 5)
    }

    func testConsumptionPersistsAsDebitsAgainstVerifiedCredits() throws {
        let fileURL = temporaryLedgerURL()
        let ledger = PackCreditLedger(fileURL: fileURL)

        try ledger.recordPackPurchase(transactionID: 1001)
        XCTAssertTrue(try ledger.consumeCredit())
        XCTAssertTrue(try ledger.consumeCredit())

        let reloaded = PackCreditLedger(fileURL: fileURL)
        XCTAssertEqual(try reloaded.snapshot().availableCredits, 3)
        XCTAssertEqual(try reloaded.snapshot().consumedCreditCount, 2)
    }

    func testCannotConsumeWithoutAvailableCredit() throws {
        let ledger = makeLedger()

        XCTAssertFalse(try ledger.consumeCredit())
        XCTAssertEqual(try ledger.snapshot().availableCredits, 0)
    }

    func testRevokedTransactionRemovesRemainingPackCredits() throws {
        let ledger = makeLedger()

        try ledger.recordPackPurchase(transactionID: 1001)
        XCTAssertTrue(try ledger.consumeCredit())
        XCTAssertTrue(try ledger.consumeCredit())
        try ledger.revokePackPurchase(transactionID: 1001)

        let snapshot = try ledger.snapshot()
        XCTAssertEqual(snapshot.revokedPackCount, 1)
        XCTAssertEqual(snapshot.revokedCreditCount, 3)
        XCTAssertEqual(snapshot.availableCredits, 0)
    }

    func testNewPurchaseAfterRevocationGetsFreshCredits() throws {
        let ledger = makeLedger()

        try ledger.recordPackPurchase(transactionID: 1001)
        XCTAssertTrue(try ledger.consumeCredit())
        XCTAssertTrue(try ledger.consumeCredit())
        try ledger.revokePackPurchase(transactionID: 1001)
        try ledger.recordPackPurchase(transactionID: 1002)

        XCTAssertEqual(try ledger.snapshot().availableCredits, 5)
    }

    func testCorruptLedgerFailsClosed() throws {
        let fileURL = temporaryLedgerURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        let ledger = PackCreditLedger(fileURL: fileURL)

        XCTAssertThrowsError(try ledger.snapshot())
        XCTAssertThrowsError(try ledger.recordPackPurchase(transactionID: 1001))
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
