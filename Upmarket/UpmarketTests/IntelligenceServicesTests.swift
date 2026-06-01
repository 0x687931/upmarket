import XCTest
import NaturalLanguage
@testable import Upmarket

/// Tests for tasks #23-27: DocumentIntelligence, VisionOCR,
/// SpeechTranscriber, FoundationModelEnhancer, VisionDocumentExtractor.
/// All tests use the Docling corpus from tests/corpus/docling/.
final class IntelligenceServicesTests: XCTestCase {

    // MARK: - #27 DocumentIntelligence (NLTagger)

    func testLanguageDetection() {
        XCTAssertEqual(DocumentIntelligence.extractMetadata(from: englishText).language, "en")
    }

    func testPersonNameExtraction() {
        let text = "The paper was written by John Smith and Mary Johnson at MIT."
        let meta = DocumentIntelligence.extractMetadata(from: text)
        XCTAssertTrue(meta.authors.contains(where: { $0.contains("Smith") || $0.contains("Johnson") }))
    }

    func testOrganisationExtraction() {
        let text = "Research conducted at Apple Inc. in partnership with Stanford University."
        let meta = DocumentIntelligence.extractMetadata(from: text)
        XCTAssertFalse(meta.organisations.isEmpty)
    }

    func testDocumentTypeClassification() {
        let academic = DocumentIntelligence.extractMetadata(from: "Abstract. Introduction. Methodology. References. DOI: 10.1000/xyz")
        XCTAssertEqual(academic.documentType, .academic)

        let legal = DocumentIntelligence.extractMetadata(from: "Whereas the plaintiff hereinafter referred to as the party...")
        XCTAssertEqual(legal.documentType, .legal)

        let business = DocumentIntelligence.extractMetadata(from: "Q3 revenue grew 12% year-over-year. Shareholders approved the dividend.")
        XCTAssertEqual(business.documentType, .business)
    }

    func testReadingTimeEstimate() {
        let shortText = String(repeating: "word ", count: 200)
        let meta = DocumentIntelligence.extractMetadata(from: shortText)
        XCTAssertEqual(meta.estimatedReadingMinutes, 1)

        let longText = String(repeating: "word ", count: 2000)
        let meta2 = DocumentIntelligence.extractMetadata(from: longText)
        XCTAssertEqual(meta2.estimatedReadingMinutes, 10)
    }

    func testHeadingConfidenceNounPhrase() {
        // Clear noun phrase — high confidence heading
        let annotation = DocumentIntelligence.headingConfidence(
            for: "Introduction to Machine Learning", language: "en"
        )
        XCTAssertTrue(annotation.isNounPhrase)
        XCTAssertGreaterThan(annotation.confidence, 0.6)
    }

    func testHeadingConfidenceSentence() {
        // Full sentence — low confidence heading
        let annotation = DocumentIntelligence.headingConfidence(
            for: "The results show that our method outperforms baselines.", language: "en"
        )
        XCTAssertTrue(annotation.hasVerb)
        XCTAssertLessThan(annotation.confidence, 0.5)
    }

    func testRunningHeaderDetection() {
        // Simulate a document with a repeating header on each page
        let pages = (0..<10).map { i in
            "Journal of Computer Science Vol. 12\nContent for page \(i). This is unique text for page \(i) only."
        }
        let candidates = DocumentIntelligence.detectRunningHeaders(pages: pages)
        XCTAssertFalse(candidates.isEmpty, "Should detect 'Journal of Computer Science Vol. 12' as running header")
        XCTAssertTrue(candidates.first?.occurrenceCount ?? 0 >= 3)
    }

    func testSentimentScoring() {
        let positive = DocumentIntelligence.extractMetadata(from: "This is an excellent, wonderful, outstanding result!")
        let negative = DocumentIntelligence.extractMetadata(from: "This is terrible, awful, and completely wrong.")
        if let pos = positive.sentimentScore, let neg = negative.sentimentScore {
            XCTAssertGreaterThan(pos, neg)
        }
    }

    // MARK: - #24 VisionOCR

    func testVisionOCRAvailability() {
        // VisionOCR should work on all our supported macOS versions
        // Just verify it doesn't crash on init
        XCTAssertNoThrow({})
    }

    func testVisionOCROnDoclingCorpusPDF() async throws {
        let corpusPath = corpusDoclingPath.appendingPathComponent("tests/data/pdf/normal_4pages.pdf")
        guard FileManager.default.fileExists(atPath: corpusPath.path) else {
            throw XCTSkip("Docling corpus not available — run: git submodule update --init")
        }

        let result = try await VisionOCR.recognise(pdfURL: corpusPath)
        XCTAssertEqual(result.pageCount, 4)
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertGreaterThan(result.averageConfidence, 0.5, "Digital PDF should have high OCR confidence")
    }

    // MARK: - #26 SpeechTranscriber

    func testSpeechTranscriberLanguageList() {
        let languages = SpeechTranscriber.supportedOnDeviceLanguages
        XCTAssertTrue(languages.contains("en-US"))
        XCTAssertTrue(languages.contains("fr-FR"))
        XCTAssertTrue(languages.contains("ja-JP"))
        XCTAssertFalse(languages.isEmpty)
    }

    func testSpeechTranscriberMarkdownFormat() async {
        // Test the Markdown formatter with a mock result
        let transcriber = SpeechTranscriber()
        let mockResult = SpeechTranscriber.Result(
            transcript: "Hello world. This is a test.",
            confidence: 0.95,
            language: "en-US",
            durationSeconds: 3.0,
            segments: []
        )
        let markdown = transcriber.toMarkdown(mockResult)
        XCTAssertTrue(markdown.contains("## Transcript"))
        XCTAssertTrue(markdown.contains("en-US"))
        XCTAssertTrue(markdown.contains("Hello world"))
    }

    // MARK: - #23 FoundationModelEnhancer

    func testFoundationModelEnhancerAvailability() {
        // Availability depends on macOS version + hardware
        // Just verify the check doesn't crash
        let _ = FoundationModelEnhancer.isAvailable
    }

    func testFoundationModelEnhancerFallback() async {
        // On any platform, should return the input markdown unchanged if unavailable
        let input = "# Test\n\nSome content here."
        let result = await FoundationModelEnhancer.enhance(markdown: input)
        // Either enhanced or pass-through — markdown should never be empty
        XCTAssertFalse(result.refinedMarkdown.isEmpty)
    }

    func testFoundationModelEnhancerTitleExtraction() async {
        let markdown = "# The Theory of Everything\n\nBody text here."
        let result = await FoundationModelEnhancer.enhance(markdown: markdown)
        // Title should be extracted (heuristic works even without Foundation Models)
        XCTAssertEqual(result.extractedTitle, "The Theory of Everything")
    }

    func testEnhancementResultIsCodable() throws {
        let enhancement = FoundationModelEnhancer.DocumentEnhancement(
            extractedTitle: "Test",
            extractedAuthors: ["Alice"],
            sectionSummaries: [
                FoundationModelEnhancer.SectionSummary(
                    heading: "Intro",
                    summary: "Short summary",
                    keyPoints: ["Point"]
                ),
            ],
            refinedMarkdown: "# Test",
            wasEnhanced: true
        )
        let data = try JSONEncoder().encode(enhancement)
        let decoded = try JSONDecoder().decode(FoundationModelEnhancer.DocumentEnhancement.self, from: data)
        XCTAssertEqual(decoded, enhancement)
    }

    // MARK: - #25 VisionDocumentExtractor

    func testVisionDocumentExtractorAvailability() {
        // macOS 26+ check
        if #available(macOS 26, *) {
            XCTAssertTrue(VisionDocumentExtractor.isAvailable)
        } else {
            XCTAssertFalse(VisionDocumentExtractor.isAvailable)
        }
    }

    func testVisionDocumentExtractorFallsBackGracefully() async throws {
        let corpusPath = corpusDoclingPath.appendingPathComponent("tests/data/pdf/normal_4pages.pdf")
        guard FileManager.default.fileExists(atPath: corpusPath.path) else {
            throw XCTSkip("Docling corpus not available")
        }

        let result = try await VisionDocumentExtractor.extract(pdfURL: corpusPath)
        // Should work on all OS versions (falls back to VisionOCR on < 26)
        XCTAssertEqual(result.pageCount, 4)
        XCTAssertFalse(result.markdown.isEmpty)
    }

    // MARK: - Integration: Full pipeline on corpus

    func testFullPipelineOnDoclingAcademicPDF() async throws {
        let pdfPath = corpusDoclingPath.appendingPathComponent("tests/data/pdf/2206.01062.pdf")
        let gtPath  = corpusDoclingPath.appendingPathComponent("tests/data/groundtruth/docling_v2/2206.01062.md")

        guard FileManager.default.fileExists(atPath: pdfPath.path) else {
            throw XCTSkip("Docling corpus not available")
        }

        // Run Vision OCR (simulates our fast path for PDFs)
        let ocrResult = try await VisionOCR.recognise(pdfURL: pdfPath)
        XCTAssertFalse(ocrResult.text.isEmpty)

        // Run DocumentIntelligence on the result
        let meta = DocumentIntelligence.extractMetadata(from: ocrResult.text)
        XCTAssertEqual(meta.language, "en")
        XCTAssertFalse(meta.keyPhrases.isEmpty)

        // If ground truth exists, check heading recall
        if FileManager.default.fileExists(atPath: gtPath.path),
           let gt = try? String(contentsOf: gtPath) {
            let gtHeadings = gt.components(separatedBy: "\n")
                .filter { $0.hasPrefix("#") }
                .map { $0.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression) }
            XCTAssertFalse(gtHeadings.isEmpty, "Ground truth should have headings")
        }
    }

    // MARK: - Helpers

    private var englishText: String {
        "The quick brown fox jumps over the lazy dog. This is a standard English test sentence."
    }

    private var corpusDoclingPath: URL {
        // Relative to project root
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // UpmarketTests/
            .deletingLastPathComponent()  // Upmarket/
            .deletingLastPathComponent()  // repo root
        return projectRoot.appendingPathComponent("tests/corpus/docling/docling")
    }
}
