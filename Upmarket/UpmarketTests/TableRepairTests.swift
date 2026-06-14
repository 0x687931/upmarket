import XCTest
@testable import Upmarket

final class TableRepairTests: XCTestCase {
    func testDetectMissingTablesMatchesByContentNotSuffix() {
        let tableA = TableRepair.StructuredTable(rows: [["A1", "A2"], ["A3", "A4"]])
        let tableB = TableRepair.StructuredTable(rows: [["B1", "B2"], ["B3", "B4"]])
        let tableC = TableRepair.StructuredTable(rows: [["C1", "C2"], ["C3", "C4"]])
        let markdown = """
        | a1 | a2 |
        | --- | --- |
        | a3 | a4 |

        body text

        | c1 | c2 |
        | --- | --- |
        | c3 | c4 |
        """

        let missing = TableRepair.detectMissingTables(
            originalTables: [tableA, tableB, tableC],
            outputMarkdown: markdown
        )

        XCTAssertEqual(missing, [tableB])
    }
}
