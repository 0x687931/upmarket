import XCTest
@testable import Upmarket

final class StoreAccountingServiceTests: XCTestCase {
    func testInitialStateDiscardsLegacyLocalCredits() throws {
        let defaults = makeDefaults()
        defaults.set(2, forKey: "upmarket.freeDocsRemaining")
        defaults.set(3, forKey: "upmarket.packCredits")
        defaults.set(2, forKey: "upmarket.packsEverPurchased")
        let service = makeService(defaults: defaults)

        let snapshot = service.loadInitialState()

        XCTAssertEqual(snapshot.freeDocsRemaining, 0)
        XCTAssertEqual(snapshot.packCredits, 0)
        XCTAssertEqual(snapshot.packsEverPurchased, 0)
        XCTAssertEqual(defaults.integer(forKey: "upmarket.freeDocsRemaining"), 0)
        XCTAssertNil(defaults.object(forKey: "upmarket.packCredits"))
        XCTAssertNil(defaults.object(forKey: "upmarket.packsEverPurchased"))
        XCTAssertEqual(service.loadInitialState().packCredits, 0)
    }

    func testDoesNotConsumeEditableFreeTrialOrPackCreditState() throws {
        let defaults = makeDefaults()
        let service = makeService(defaults: defaults)
        _ = try service.recordPackTransaction(transactionID: 1001, isRevoked: false, freeDocsRemaining: 1)

        let result = try service.consumeConversion(freeDocsRemaining: 1, packCredits: 5)

        XCTAssertFalse(result.consumed)
        XCTAssertEqual(result.snapshot.freeDocsRemaining, 0)
        XCTAssertEqual(result.snapshot.packCredits, 0)
        XCTAssertEqual(defaults.integer(forKey: "upmarket.freeDocsRemaining"), 0)
    }

    func testVerifiedPackTransactionsDoNotGrantBetaConversionCredits() throws {
        let service = makeService()
        let credited = try service.recordPackTransaction(transactionID: 1001, isRevoked: false, freeDocsRemaining: 0)
        XCTAssertEqual(credited.packCredits, 0)

        let result = try service.consumeConversion(freeDocsRemaining: 0, packCredits: credited.packCredits)

        XCTAssertFalse(result.consumed)
        XCTAssertEqual(result.snapshot.packCredits, 0)
    }

    func testTrialPaywallPromptIsDisabledWhenLocalTrialCreditsAreNotAuthoritative() {
        let service = makeService()

        XCTAssertFalse(service.shouldShowTrialPaywallAfterConversion(
            hasPaidEntitlement: false,
            freeDocsRemaining: 3,
            packCredits: 0
        ))
        XCTAssertFalse(service.shouldShowTrialPaywallAfterConversion(
            hasPaidEntitlement: false,
            freeDocsRemaining: 1,
            packCredits: 0
        ))
        XCTAssertFalse(service.shouldShowTrialPaywallAfterConversion(
            hasPaidEntitlement: true,
            freeDocsRemaining: 0,
            packCredits: 0
        ))
    }

    private func makeService(defaults: UserDefaults? = nil) -> StoreAccountingService {
        StoreAccountingService(
            defaults: defaults ?? makeDefaults(),
            packLedger: PackCreditLedger(fileURL: temporaryLedgerURL())
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "StoreAccountingServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryLedgerURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("PackCreditLedger.json")
    }
}
