import XCTest
@testable import Upmarket

final class AIEngineTests: XCTestCase {

    func testEngineAssetMappingIsDistinctAndCoversBothMaxAssets() {
        XCTAssertEqual(AIEngine.granite.asset, .graniteDocling)
        XCTAssertEqual(AIEngine.lfm2.asset, .lfm25VL)
        // Every AI engine maps to a distinct asset, and together they cover the Max AI assets.
        let mapped = Set(AIEngine.allCases.map(\.asset))
        XCTAssertEqual(mapped.count, AIEngine.allCases.count)
        XCTAssertEqual(mapped, [.graniteDocling, .lfm25VL])
    }

    func testSelectedDefaultsWhenUnset() {
        UserDefaults.standard.removeObject(forKey: AIEngine.storageKey)
        XCTAssertEqual(AIEngine.selected, .default)
        XCTAssertEqual(AIEngine.default, .granite)
    }

    func testSelectedReadsPersistedRawValue() {
        defer { UserDefaults.standard.removeObject(forKey: AIEngine.storageKey) }
        UserDefaults.standard.set(AIEngine.lfm2.rawValue, forKey: AIEngine.storageKey)
        XCTAssertEqual(AIEngine.selected, .lfm2)
        UserDefaults.standard.set("garbage", forKey: AIEngine.storageKey)
        XCTAssertEqual(AIEngine.selected, .default, "unknown raw value falls back to default")
    }

    func testBothValidatedEnginesAreExposed() {
        XCTAssertEqual(AIEngine.productionCases, [.granite, .lfm2])
        XCTAssertTrue(AIEngine.lfm2.isProductionAvailable)
    }

    func testBothMaxAssetsAreReportedAndRequireMax() async {
        // The download UI is data-driven over nativeModelStatuses; both AI assets must surface.
        let statuses = await ModelManager.nativeModelStatuses(in: FileManager.default.temporaryDirectory)
        let keys = Set(statuses.map(\.key))
        XCTAssertTrue(keys.contains(ModelAsset.graniteDocling.rawValue))
        XCTAssertTrue(keys.contains(ModelAsset.lfm25VL.rawValue))
        XCTAssertEqual(ModelAsset.lfm25VL.requiredTier, .max)
        XCTAssertEqual(ModelAsset.lfm25VL.delivery, .backgroundAssets)
    }
}
