import XCTest
@testable import UpmarketVLM

final class LFM2VLReferenceProcessorTests: XCTestCase {
    func testPortraitDocumentMatchesReferencePatchGrid() {
        let plan = LFM2VLImagePlan.reference(width: 1695, height: 2186)
        XCTAssertEqual(plan.resizedWidth, 448)
        XCTAssertEqual(plan.resizedHeight, 576)
        XCTAssertEqual(plan.patchColumns, 28)
        XCTAssertEqual(plan.patchRows, 36)
        XCTAssertEqual(plan.validPatchCount, 1008)
        XCTAssertEqual(plan.paddedPatchCount, 1024)
        XCTAssertEqual(plan.imageTokenCount, 252)
    }

    func testLandscapeDocumentStaysWithinPatchBudget() {
        let plan = LFM2VLImagePlan.reference(width: 2400, height: 1200)
        XCTAssertLessThanOrEqual(plan.validPatchCount, 1024)
        XCTAssertEqual(plan.resizedWidth % 16, 0)
        XCTAssertEqual(plan.resizedHeight % 16, 0)
        XCTAssertEqual(
            plan.imageTokenCount,
            (plan.patchRows / 2) * (plan.patchColumns / 2)
        )
    }

    func testPortraitDocumentUsesSixTilesAndThumbnail() {
        let tiles = LFM2VLTilePlan.reference(width: 1695, height: 2187)
        XCTAssertEqual(tiles.columns, 2)
        XCTAssertEqual(tiles.rows, 3)
    }

    func testPromptIncludesImageBoundariesTileMarkersAndThumbnail() {
        let tokens = LFM2VLPromptPlan.specialTokens(
            tileLayout: .init(columns: 2, rows: 3),
            includeThumbnail: true
        )
        XCTAssertEqual(tokens.first, "<|image_start|>")
        XCTAssertEqual(tokens.last, "<|image_end|>")
        XCTAssertEqual(tokens[1], "<|img_row_1_col_1|>")
        XCTAssertEqual(tokens[6], "<|img_row_3_col_2|>")
        XCTAssertEqual(tokens[7], "<|img_thumbnail|>")
    }
}
