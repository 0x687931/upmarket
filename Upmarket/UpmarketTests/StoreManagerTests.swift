import XCTest
@testable import Upmarket

@MainActor
final class StoreManagerTests: XCTestCase {
    func testBasicTierIsDefaultAndCanAlwaysConvert() {
        XCTAssertTrue(StoreManager.shared.canConvert)
        XCTAssertEqual(StoreManager.shared.tier, .basic)
    }
}
