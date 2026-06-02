import XCTest
@testable import Upmarket

@MainActor
final class ProgrammaticConversionAuthorizationTests: XCTestCase {

    func testAuthorizationRefreshesEntitlementsBeforeConsumingCredit() async throws {
        var events: [String] = []
        let authorizer = ProgrammaticConversionAuthorizer(
            refreshEntitlements: {
                events.append("refresh")
            },
            aiUnavailableReason: { _ in
                events.append("ai")
                return nil
            },
            consumeConversion: {
                events.append("consume")
                return true
            }
        )

        try await authorizer.authorize(useAI: false)

        XCTAssertEqual(events, ["refresh", "ai", "consume"])
    }

    func testAIUnavailableDoesNotConsumeCredit() async throws {
        var consumed = false
        let authorizer = ProgrammaticConversionAuthorizer(
            refreshEntitlements: {},
            aiUnavailableReason: { useAI in
                useAI ? "Upmarket AI is not available" : nil
            },
            consumeConversion: {
                consumed = true
                return true
            }
        )

        do {
            try await authorizer.authorize(useAI: true)
            XCTFail("Expected AI authorization to fail")
        } catch let error as UpmarketIntentError {
            XCTAssertEqual(error, .aiUnavailable)
        }

        XCTAssertFalse(consumed)
    }

    func testPurchaseRequiredWhenNoCreditCanBeConsumed() async throws {
        var consumeCount = 0
        let authorizer = ProgrammaticConversionAuthorizer(
            refreshEntitlements: {},
            aiUnavailableReason: { _ in nil },
            consumeConversion: {
                consumeCount += 1
                return false
            }
        )

        do {
            try await authorizer.authorize(useAI: false)
            XCTFail("Expected purchase requirement")
        } catch let error as UpmarketIntentError {
            XCTAssertEqual(error, .purchaseRequired)
        }

        XCTAssertEqual(consumeCount, 1)
    }

    func testSuccessfulAuthorizationConsumesOneCredit() async throws {
        var consumeCount = 0
        let authorizer = ProgrammaticConversionAuthorizer(
            refreshEntitlements: {},
            aiUnavailableReason: { _ in nil },
            consumeConversion: {
                consumeCount += 1
                return true
            }
        )

        try await authorizer.authorize(useAI: true)

        XCTAssertEqual(consumeCount, 1)
    }
}
