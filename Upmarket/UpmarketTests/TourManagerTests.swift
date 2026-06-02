import XCTest
@testable import Upmarket

@MainActor
final class TourManagerTests: XCTestCase {
    func testTourCompletionDoesNotShowPaywallBeforeConversionValue() async throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "upmarket.tourComplete")

        let paywallShown = expectation(description: "Tour completion should not show paywall")
        paywallShown.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .showPaywall,
            object: nil,
            queue: .main
        ) { _ in
            paywallShown.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            defaults.removeObject(forKey: "upmarket.tourComplete")
        }

        TourManager.shared.skip()

        await fulfillment(of: [paywallShown], timeout: 0.7)
        XCTAssertTrue(defaults.bool(forKey: "upmarket.tourComplete"))
    }
}
