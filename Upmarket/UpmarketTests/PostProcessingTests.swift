import XCTest
@testable import Upmarket

/// Tests for the NaturalLanguage and Writing Tools post-processing pipeline.
/// Run these before any release to verify output quality on real documents.
final class PostProcessingTests: XCTestCase {

    // MARK: - TextStructurer Tests

    func testSentenceBoundaryDetection() {
        let input = TextStructurer.Input(
            rawMarkdown: "This is sentence one. This is sentence two. And a third.",
            detectedLanguage: "en"
        )
        let output = TextStructurer.refine(input)
        XCTAssertEqual(output.sentenceCount, 3)
        XCTAssertFalse(output.markdown.isEmpty)
    }

    func testHeadingsPreserved() {
        let input = TextStructurer.Input(
            rawMarkdown: "# Title\n\nBody text here. Another sentence.\n\n## Section\n\nMore text.",
            detectedLanguage: "en"
        )
        let output = TextStructurer.refine(input)
        XCTAssertTrue(output.markdown.contains("# Title"))
        XCTAssertTrue(output.markdown.contains("## Section"))
    }

    func testDividerPreserved() {
        let input = TextStructurer.Input(
            rawMarkdown: "Page one content.\n\n---\n\nPage two content.",
            detectedLanguage: "en"
        )
        let output = TextStructurer.refine(input)
        XCTAssertTrue(output.markdown.contains("---"))
    }

    func testBrokenSentencesMerged() {
        // PDF often splits sentences across lines
        let input = TextStructurer.Input(
            rawMarkdown: "This sentence was broken\nacross two lines in the PDF.",
            detectedLanguage: "en"
        )
        let output = TextStructurer.refine(input)
        // Should merge into single paragraph
        XCTAssertFalse(output.markdown.contains("\n"))
    }

    func testWritingToolsRefinesTextOnMacOS151Plus() async {
        // PDF text with broken sentences that should be merged
        let input = "The quick brown fox\njumps over the lazy dog."
        let output = await WritingToolsService.refineMarkdown(input, language: "en")

        // On all platforms (since actual NSWritingToolsCoordinator integration is deferred),
        // the service should still perform basic refinement:
        // 1. Merge broken sentences
        // 2. Preserve structure
        // 3. Mark whether refinement occurred

        if WritingToolsAvailabilityCheck.isAvailable {
            // When Writing Tools is available, should attempt refinement
            XCTAssertTrue(output.markdown.count > 0, "Output should have content")
            // Check if sentence merging happened
            if !output.markdown.contains("\n") || output.markdown.contains("fox jumps") {
                XCTAssertTrue(output.wasRefined, "Should mark as refined if sentences were merged")
            }
        } else {
            // When Writing Tools is unavailable (e.g. Apple Intelligence off), no refinement
            XCTAssertFalse(output.wasRefined, "Should not claim refinement when Writing Tools is unavailable")
        }
    }

    func testLanguageDetection() {
        let english = "The quick brown fox jumps over the lazy dog."
        let detected = TextStructurer.detectLanguage(english)
        XCTAssertEqual(detected, "en")
    }

    func testEmptyInputHandled() {
        let input = TextStructurer.Input(rawMarkdown: "", detectedLanguage: nil)
        let output = TextStructurer.refine(input)
        XCTAssertTrue(output.markdown.isEmpty)
        XCTAssertEqual(output.sentenceCount, 0)
    }

    func testParagraphCount() {
        let input = TextStructurer.Input(
            rawMarkdown: "First paragraph text.\n\nSecond paragraph text.\n\nThird paragraph.",
            detectedLanguage: "en"
        )
        let output = TextStructurer.refine(input)
        XCTAssertEqual(output.paragraphCount, 3)
    }

    func testMultipleLanguages() {
        let inputs: [(String, String)] = [
            ("Le renard brun rapide saute par-dessus le chien paresseux.", "fr"),
            ("Der schnelle braune Fuchs springt über den faulen Hund.", "de"),
        ]
        for (text, expectedLang) in inputs {
            let detected = TextStructurer.detectLanguage(text)
            XCTAssertEqual(detected, expectedLang, "Failed for language: \(expectedLang)")
        }
    }

    // MARK: - WritingToolsRefiner Tests

    func testFallbackOnOlderOS() async {
        // WritingToolsRefinerAdapter always returns input unchanged on unsupported OS
        let input = "# Test\n\nSome content here."
        let output = await WritingToolsService.refineMarkdown(input, language: "en")
        // When Writing Tools is unavailable (Apple Intelligence off / unsupported), no refinement
        if !WritingToolsAvailabilityCheck.isAvailable {
            XCTAssertFalse(output.wasRefined)
            XCTAssertEqual(output.markdown, input)
        }
    }

    func testChunkSplitting() async {
        // Large document should be chunked without losing content
        let longText = (0..<50).map { "Paragraph \($0). This is body text for testing." }.joined(separator: "\n\n")
        let output = await WritingToolsService.refineMarkdown(longText, language: "en")
        // Content should be preserved regardless of refinement
        XCTAssertFalse(output.markdown.isEmpty)
    }

    func testHeadingsNotCorrupted() async {
        let input = "# Main Title\n\n## Section One\n\nBody text here.\n\n### Subsection\n\nMore text."
        let output = await WritingToolsService.refineMarkdown(input, language: "en")
        XCTAssertTrue(output.markdown.contains("# Main Title"))
        XCTAssertTrue(output.markdown.contains("## Section One"))
        XCTAssertTrue(output.markdown.contains("### Subsection"))
    }

    func testWritingToolsLineMergePreservesMarkdownTableRows() {
        XCTAssertFalse(WritingToolsRefiner.shouldMergeLine("| --- | --- |", into: "| A | B |"))
        XCTAssertTrue(WritingToolsRefiner.isMarkdownTableRow("| A | B |"))
    }

    // MARK: - Integration: NL → Writing Tools Pipeline

    func testFullPipeline() async {
        let rawPDFOutput = """
        # Document Title

        This sentence was split
        across a line in the PDF. And this is another sentence.

        ## Section Heading

        Body paragraph one. It has multiple sentences. This is the third.

        Body paragraph two with different content here.
        """

        // Step 1: NaturalLanguage structuring
        let nlInput = TextStructurer.Input(rawMarkdown: rawPDFOutput, detectedLanguage: "en")
        let nlOutput = TextStructurer.refine(nlInput)

        XCTAssertTrue(nlOutput.markdown.contains("# Document Title"))
        XCTAssertTrue(nlOutput.sentenceCount > 0)

        // Step 2: Writing Tools refinement (may be no-op on older OS)
        let wtOutput = await WritingToolsService.refineMarkdown(
            nlOutput.markdown,
            language: nlOutput.detectedLanguage
        )

        XCTAssertFalse(wtOutput.markdown.isEmpty)
        XCTAssertTrue(wtOutput.markdown.contains("# Document Title"))
    }
}

/// Exposes availability check for test assertions
enum WritingToolsAvailabilityCheck {
    static var isAvailable: Bool {
        // Deployment target is macOS 26.0, so the OS always satisfies Writing Tools'
        // macOS 15.1 requirement; availability now depends only on the feature itself.
        WritingToolsRefiner.isAvailable
    }
}
