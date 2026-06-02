import XCTest
@testable import Upmarket

final class MarkdownQualityScorerTests: XCTestCase {
    func testStructuredMarkdownScoresAboveNoisyOutput() {
        let structured = """
        # Quarterly Report

        Revenue increased during the quarter and operating margin improved.

        | Metric | Value |
        | --- | --- |
        | Revenue | 100 |

        - Growth improved
        - Costs remained controlled
        """
        let noisy = """
        R
        e
        v
        1
        2
        3
        xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        """

        let structuredScore = MarkdownQualityScorer.score(markdown: structured, pages: 1)
        let noisyScore = MarkdownQualityScorer.score(markdown: noisy, pages: 1)

        XCTAssertGreaterThan(structuredScore.overall, noisyScore.overall)
        XCTAssertGreaterThan(structuredScore.structure, noisyScore.structure)
    }

    func testImageTextAgreementRewardsMatchingOutput() {
        let reference = "The quick brown fox jumps over the lazy document converter."
        let matching = "# Title\n\nThe quick brown fox jumps over the lazy document converter."
        let unrelated = "# Title\n\nRevenue cost margin shareholder dividend earnings."

        let matchingScore = MarkdownQualityScorer.score(markdown: matching, pages: 1, imageText: reference)
        let unrelatedScore = MarkdownQualityScorer.score(markdown: unrelated, pages: 1, imageText: reference)

        XCTAssertGreaterThan(matchingScore.imageTextAgreement ?? 0, unrelatedScore.imageTextAgreement ?? 0)
        XCTAssertGreaterThan(matchingScore.overall, unrelatedScore.overall)
    }

    func testBestCandidateUsesQualityScore() {
        let low = ConversionOutput(markdown: "x", pages: 1, format: "PDF", title: "low", pipeline: .fast)
        let high = ConversionOutput(markdown: "# Report\n\nThis is a coherent report with enough words to be useful.", pages: 1, format: "PDF", title: "high", pipeline: .fast)
        let candidates = [
            (label: "low", output: low, score: MarkdownQualityScorer.score(markdown: low.markdown, pages: 1)),
            (label: "high", output: high, score: MarkdownQualityScorer.score(markdown: high.markdown, pages: 1)),
        ]

        XCTAssertEqual(MarkdownQualityScorer.best(candidates)?.label, "high")
    }
}
