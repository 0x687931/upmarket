import XCTest
@testable import UpmarketVLM

final class VLMOutputValidatorTests: XCTestCase {
    func testAcceptsNormalMarkdown() throws {
        let markdown = """
        # Report

        A concise paragraph with useful document content.

        | Item | Value |
        | --- | --- |
        | Alpha | 42 |
        """
        XCTAssertEqual(try VLMOutputValidator.validate(markdown), markdown)
    }

    func testRejectsEmptyOutput() {
        XCTAssertThrowsError(try VLMOutputValidator.validate(" \n ")) {
            XCTAssertEqual($0 as? VLMOutputValidator.Failure, .empty)
        }
    }

    func testRejectsRepeatedLines() {
        let line = "- developed a new pricing strategy with rules and implementation guidance."
        XCTAssertThrowsError(try VLMOutputValidator.validate(
            Array(repeating: line, count: 6).joined(separator: "\n")
        )) {
            XCTAssertEqual($0 as? VLMOutputValidator.Failure, .repeatedLine)
        }
    }

    func testRejectsAlternatingPhraseLoop() {
        let a = "The same generated sentence continues with enough words to form a repeated phrase."
        let b = "A second line alternates with it while the model remains stuck in a loop."
        let output = Array(repeating: "\(a)\n\(b)", count: 6).joined(separator: "\n")
        XCTAssertThrowsError(try VLMOutputValidator.validate(output))
    }
}
