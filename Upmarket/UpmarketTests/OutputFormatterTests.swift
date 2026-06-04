import XCTest
@testable import Upmarket

@MainActor
final class OutputFormatterTests: XCTestCase {
    func testMarkdownModeReturnsRawMarkdown() {
        let output = makeOutput(markdown: "# Title\n\nBody")

        let formatted = OutputFormatter.format(
            output,
            sourceDisplayName: "source.pdf",
            mode: .markdown,
            convertedAt: fixedDate
        )

        XCTAssertEqual(formatted.text, "# Title\n\nBody")
        XCTAssertEqual(formatted.fileExtension, "md")
    }

    func testFrontmatterEscapesStringsAndDoesNotIncludeFullPath() {
        let output = makeOutput(
            title: #"Q3 "Financial" Report"# + "\nDraft",
            markdown: "# Revenue\n\nGrowth was steady."
        )

        let formatted = OutputFormatter.format(
            output,
            sourceDisplayName: "report.pdf",
            mode: .markdownWithFrontmatter,
            convertedAt: fixedDate
        )

        XCTAssertEqual(formatted.fileExtension, "md")
        XCTAssertTrue(formatted.text.hasPrefix("---\n"))
        XCTAssertTrue(formatted.text.contains(#"title: "Q3 \"Financial\" Report\nDraft""#))
        XCTAssertTrue(formatted.text.contains(#"source: "report.pdf""#))
        XCTAssertTrue(formatted.text.contains(#"converted: "2026-06-03T00:00:00Z""#))
        XCTAssertTrue(formatted.text.contains(#"pipeline: "enhanced""#))
        XCTAssertTrue(formatted.text.contains("word_count: 4"))
        XCTAssertTrue(formatted.text.contains("\n---\n\n# Revenue"))
        XCTAssertFalse(formatted.text.contains("/Users/"))
    }

    func testJSONModeProducesValidJSONForUnicodeMarkdown() throws {
        let markdown = "# Résumé\n\nこんにちは \"world\""
        let output = makeOutput(markdown: markdown)

        let formatted = OutputFormatter.format(
            output,
            sourceDisplayName: "resume.pdf",
            mode: .json,
            convertedAt: fixedDate
        )

        XCTAssertEqual(formatted.fileExtension, "json")
        let data = try XCTUnwrap(formatted.text.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["markdown"] as? String, markdown)
        XCTAssertEqual(object["title"] as? String, "Report")
        let metadata = try XCTUnwrap(object["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["source"] as? String, "resume.pdf")
        XCTAssertEqual(metadata["pipeline"] as? String, "enhanced")
        XCTAssertEqual(metadata["converted"] as? String, "2026-06-03T00:00:00Z")
        XCTAssertFalse(formatted.text.contains("/Users/"))
    }

    private var fixedDate: Date {
        ISO8601DateFormatter().date(from: "2026-06-03T00:00:00Z")!
    }

    private func makeOutput(
        title: String = "Report",
        markdown: String
    ) -> ConversionOutput {
        ConversionOutput(
            markdown: markdown,
            pages: 2,
            format: "PDF",
            title: title,
            pipeline: .enhanced,
            selectedPathway: .enhanced
        )
    }
}
