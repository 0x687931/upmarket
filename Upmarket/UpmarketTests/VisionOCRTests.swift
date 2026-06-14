import XCTest
@testable import Upmarket

final class VisionOCRTests: XCTestCase {
    func testHandwritingRatioIncludesZeroScorePages() {
        let pageResults = [
            VisionOCR.PageResult(pageIndex: 0, text: "handwritten", confidence: 0.91, observations: [], handwritingConfidence: 0.91),
            VisionOCR.PageResult(pageIndex: 1, text: "printed", confidence: 0.95, observations: [], handwritingConfidence: 0.0),
            VisionOCR.PageResult(pageIndex: 2, text: "printed", confidence: 0.96, observations: [], handwritingConfidence: 0.0)
        ]

        let ratio = VisionOCR.handwritingRatio(
            from: pageResults,
            handwritingSum: pageResults.reduce(0) { $0 + $1.handwritingConfidence }
        )

        XCTAssertEqual(ratio, 0.3033333333, accuracy: 0.000001)
    }
}
