import XCTest
@testable import UpmarketVLM

final class DocTagsTests: XCTestCase {
    func testHeadersTextListAndTable() {
        let dt = "<doctag>"
            + "<title><loc_1><loc_2><loc_3><loc_4>Quarterly Report</title>"
            + "<text><loc_1><loc_2><loc_3><loc_4>Revenue grew this year.</text>"
            + "<section_header_level_1><loc_1><loc_2><loc_3><loc_4>Financials</section_header_level_1>"
            + "<otsl><loc_1><loc_2><loc_3><loc_4><ched>Year<ched>Revenue<nl><fcel>2014<fcel>$18<nl><fcel>2015<fcel>$22<nl></otsl>"
            + "<list_item><loc_1><loc_2><loc_3><loc_4>First point</list_item>"
            + "</doctag>"
        let md = DocTags.toMarkdown(dt)
        XCTAssertTrue(md.contains("# Quarterly Report"), md)
        XCTAssertTrue(md.contains("## Financials"), md)
        XCTAssertTrue(md.contains("Revenue grew this year."))
        XCTAssertTrue(md.contains("| Year | Revenue |"), md)
        XCTAssertTrue(md.contains("| 2014 | $18 |"), md)
        XCTAssertTrue(md.contains("- First point"), md)
        XCTAssertFalse(md.contains("<loc_"))
        XCTAssertFalse(md.contains("<fcel>"))
        XCTAssertFalse(md.contains("<otsl>"))
    }

    func testStructuredRowCellIsPreserved() {
        let dt = "<doctag><otsl><ecel><ched>A<ched>B<nl>"
            + "<srow>Blend (%):<ecel><ecel><nl></otsl></doctag>"
        let md = DocTags.toMarkdown(dt)
        XCTAssertTrue(md.contains("| Blend (%):"), md)
    }
}
