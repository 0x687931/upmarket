import XCTest
@testable import TableEvalKit

final class TEDSTests: XCTestCase {
    let a = "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>"

    func testIdenticalTablesScoreOne() {
        XCTAssertEqual(TEDS.score(predictedHTML: a, groundTruthHTML: a, structural: true), 1.0, accuracy: 1e-9)
        XCTAssertEqual(TEDS.score(predictedHTML: a, groundTruthHTML: a, structural: false), 1.0, accuracy: 1e-9)
    }

    func testStructuralIgnoresContentButTotalDoesNot() {
        // Same shape, different cell text: structural must be perfect, total must drop.
        let b = "<table><tr><td>x</td><td>y</td></tr><tr><td>z</td><td>w</td></tr></table>"
        XCTAssertEqual(TEDS.score(predictedHTML: b, groundTruthHTML: a, structural: true), 1.0, accuracy: 1e-9)
        XCTAssertLessThan(TEDS.score(predictedHTML: b, groundTruthHTML: a, structural: false), 1.0)
    }

    func testMissingCellLowersStructuralScore() {
        // Drop one cell: a single deletion against a 7-node tree (table+2tr+4td).
        let short = "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td></tr></table>"
        let score = TEDS.score(predictedHTML: short, groundTruthHTML: a, structural: true)
        XCTAssertEqual(score, 1.0 - 1.0 / 7.0, accuracy: 1e-9)
    }

    func testHeaderNormalizedToCellAndSectionsFlattened() {
        // thead/tbody + <th> must compare equal to a plain tr/td table of the same shape.
        let withSections = "<table><thead><tr><th>1</th><th>2</th></tr></thead>"
            + "<tbody><tr><td>3</td><td>4</td></tr></tbody></table>"
        XCTAssertEqual(TEDS.score(predictedHTML: withSections, groundTruthHTML: a, structural: false), 1.0, accuracy: 1e-9)
    }

    func testUnparseablePredictionScoresZero() {
        XCTAssertEqual(TEDS.score(predictedHTML: "no table here", groundTruthHTML: a, structural: true), 0.0)
    }
}
