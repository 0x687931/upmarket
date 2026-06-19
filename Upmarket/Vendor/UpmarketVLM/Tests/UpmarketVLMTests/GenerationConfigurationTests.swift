import XCTest
@testable import UpmarketVLM

final class GenerationConfigurationTests: XCTestCase {
    func testGraniteUsesModelCardRecipe() {
        let parameters = GraniteDoclingEngine.generationParameters
        XCTAssertEqual(parameters.maxTokens, 4096)
        XCTAssertEqual(parameters.temperature, 0.0)
        XCTAssertEqual(parameters.minP, 0.0)
        XCTAssertNil(parameters.repetitionPenalty)
    }

    func testGraniteStopsAtCompleteDocTag() {
        XCTAssertEqual(
            GraniteDoclingEngine.completedDocTags(
                in: "<doctag><text>Hello</text></doctag>ignored"
            ),
            "<doctag><text>Hello</text></doctag>"
        )
        XCTAssertNil(GraniteDoclingEngine.completedDocTags(in: "<doctag>"))
    }

    func testLFMUsesLiquidVisionRecipe() {
        let parameters = LFM2VLEngine.generationParameters
        XCTAssertEqual(parameters.maxTokens, 4096)
        XCTAssertEqual(parameters.temperature, 0.1)
        XCTAssertEqual(parameters.minP, 0.15)
        XCTAssertEqual(parameters.repetitionPenalty, 1.05)
        XCTAssertEqual(parameters.repetitionContextSize, 64)
    }
}
