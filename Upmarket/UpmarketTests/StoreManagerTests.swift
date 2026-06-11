import XCTest
@testable import Upmarket

@MainActor
final class StoreManagerTests: XCTestCase {
    func testDebugBuildStartsUnlockedForDeveloperUse() async {
        #if DEBUG
        for _ in 0..<20 {
            if StoreManager.shared.entitlement == .basic { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(StoreManager.shared.canConvert)
        XCTAssertTrue(StoreManager.shared.hasBasicOrAbove)
        XCTAssertEqual(StoreManager.shared.entitlement, .basic)
        #else
        throw XCTSkip("Debug-only regression test")
        #endif
    }
}
