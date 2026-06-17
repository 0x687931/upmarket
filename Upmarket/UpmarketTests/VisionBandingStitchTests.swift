import XCTest
@testable import Upmarket

/// The pure grid-stitching used by VisionDocumentExtractor's tall-table banding fallback:
/// strips are re-assembled by dropping overlap-duplicated rows and normalizing every row to
/// the table's modal column count. Mirrors the validated Python harness (scripts/eval).
final class VisionBandingStitchTests: XCTestCase {

    func testOverlapRowDeduplicated() {
        let band1 = [["a", "b"], ["c", "d"]]
        let band2 = [["c", "d"], ["e", "f"]]  // first row repeats band1's tail (the overlap)
        XCTAssertEqual(
            VisionDocumentExtractor.stitchGrids([band1, band2]),
            [["a", "b"], ["c", "d"], ["e", "f"]]
        )
    }

    func testModalColumnNormalization() {
        // modal column count = 2: the 3-col strip-edge row is dropped, the 1-col row padded.
        let grids = [[["a", "b"], ["x", "y", "z"]], [["c", "d"], ["p"]]]
        XCTAssertEqual(
            VisionDocumentExtractor.stitchGrids(grids),
            [["a", "b"], ["c", "d"], ["p", ""]]
        )
    }

    func testOcrDriftDuplicateDroppedByKey() {
        // Same first-column key, OCR-varied text across the strip overlap — must dedup.
        let band1 = [["10.1.2", "First Amendment to the Plan"]]
        let band2 = [["10.1.2", "First Amendment to the Plan (incorporated)"], ["10.1.3", "Form of Agreement"]]
        XCTAssertEqual(
            VisionDocumentExtractor.stitchGrids([band1, band2]),
            [["10.1.2", "First Amendment to the Plan"], ["10.1.3", "Form of Agreement"]]
        )
    }

    func testEmptyFirstCellContinuationNotDropped() {
        // Continuation rows (empty key) are real, not dupes — must be kept.
        let grids = [[["1.1", "alpha"], ["", "beta continued"], ["1.2", "gamma"]]]
        XCTAssertEqual(
            VisionDocumentExtractor.stitchGrids(grids),
            [["1.1", "alpha"], ["", "beta continued"], ["1.2", "gamma"]]
        )
    }

    func testEmptyInputIsEmpty() {
        XCTAssertEqual(VisionDocumentExtractor.stitchGrids([]), [])
    }
}
