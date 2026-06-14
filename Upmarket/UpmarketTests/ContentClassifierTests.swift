import XCTest
@testable import Upmarket

/// Tests ContentClassifier routing using real corpus fixtures.
/// Fixtures live in tests/corpus (a git submodule); tests are skipped if not present.
final class ContentClassifierTests: XCTestCase {

    // MARK: - Helpers

    /// Resolve the corpus data directory from the source file location at compile time.
    /// #file gives the absolute path of this source file in the checkout, which is
    /// accessible at test runtime since the Upmarket tests run outside the app sandbox.
    private let corpusRoot: URL = {
        // Walk up from this file: ContentClassifierTests.swift
        // → UpmarketTests/ → Upmarket/ → (repo root) → tests/corpus/...
        let sourceFile = URL(fileURLWithPath: #file)
        let repoRoot = sourceFile
            .deletingLastPathComponent() // UpmarketTests
            .deletingLastPathComponent() // Upmarket
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("tests/corpus/docling/docling/tests/data")
    }()

    private func corpusURL(_ relativePath: String) -> URL {
        corpusRoot.appendingPathComponent(relativePath)
    }

    private func skipIfMissing(_ url: URL, file: StaticString = #file, line: UInt = #line) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTSkip("Corpus fixture not found: \(url.lastPathComponent)")
            return true
        }
        return false
    }

    // MARK: - Multi-page TIFF

    func testMultiPageTIFFClassifiedAsScannedDocument() async throws {
        let url = corpusURL("tiff/2206.01062.tif")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: 2206.01062.tif")
        }

        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: false,
            supportsAI: false
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.kind, .scannedDocument,
            "Multi-page TIFF must be classified as scanned document regardless of content")
        XCTAssertGreaterThan(classification.frameCount, 1,
            "Must detect multiple frames in multi-page TIFF")
        XCTAssertTrue(classification.hasExtractableText)
    }

    // MARK: - Document page image

    func testDocumentPagePNGClassifiedAsScannedDocument() async throws {
        let url = corpusURL("2305.03393v1-pg9-img.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: 2305.03393v1-pg9-img.png")
        }

        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: false,
            supportsAI: false
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.kind, .scannedDocument,
            "Dense-text document page PNG must classify as scanned document")
        XCTAssertTrue(classification.hasExtractableText)
        XCTAssertEqual(classification.recommendedPathway, .visionOCR,
            "Without AI, scanned document must recommend Vision OCR")
    }

    func testDocumentPagePNGWithAIRecommendsAIPathway() async throws {
        let url = corpusURL("2305.03393v1-pg9-img.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: 2305.03393v1-pg9-img.png")
        }

        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: true,
            supportsAI: true
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.kind, .scannedDocument)
        XCTAssertEqual(classification.requiredTier, .ai,
            "Scanned document with AI available must require AI tier")
        XCTAssertEqual(classification.recommendedPathway, .ai)
    }

    // MARK: - Table crop image

    func testTableCropPNGClassifiedAsScannedDocument() async throws {
        let url = corpusURL("2305.03393v1-table_crop.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: 2305.03393v1-table_crop.png")
        }

        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: false,
            supportsAI: false
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.kind, .scannedDocument,
            "Table image with dense text must classify as scanned document")
        XCTAssertTrue(classification.hasExtractableText)
    }

    // MARK: - Diagram image (no text)

    func testDiagramPNGWithNoTextClassifiedAsPhotoOrArtwork() async throws {
        let url = corpusURL("latex/1706.03762/Figures/ModalNet-19.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: ModalNet-19.png")
        }

        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: false,
            supportsAI: false
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.kind, .photoOrArtwork,
            "Architecture diagram with no text must classify as photo/artwork → metadata only")
        XCTAssertFalse(classification.hasExtractableText)
        XCTAssertEqual(classification.recommendedPathway, .metadata)
        XCTAssertEqual(classification.requiredTier, .native)
    }

    // MARK: - WebP document

    func testWebPDocumentClassifiedAsScannedDocument() async throws {
        let url = corpusURL("webp/webp-test.webp")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: webp-test.webp")
        }

        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: false,
            supportsAI: false
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.kind, .scannedDocument,
            "WebP image containing readable text must classify as scanned document")
        XCTAssertTrue(classification.hasExtractableText)
    }

    // MARK: - Structured document formats

    func testDOCXClassifiedAsStructuredDocument() async throws {
        let url = corpusURL("docx/word_sample.docx")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: word_sample.docx")
        }

        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: true,
            supportsAI: false
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.kind, .structuredDocument,
            "DOCX must classify as a structured document")
        // DOCX is a Basic-tier format (AppTier.requiredTier(for: .docx) == .basic) and has a
        // native in-process engine, so it must route to the native capability — no Enhanced
        // runtime — even when the runtime is available.
        XCTAssertEqual(classification.requiredTier, .native)
        XCTAssertEqual(classification.recommendedPathway, .nativeOffice)
    }

    func testHTMLClassifiedAsNativeRegardlessOfRuntime() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("classifier-\(UUID().uuidString).html")
        try "<html><body><h1>Hi</h1><p>Body</p></body></html>".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        // HTML converts in-process: it must route native even when the advanced runtime is
        // absent, so it stays available in the Basic tier with nothing to download.
        for runtimeAvailable in [true, false] {
            let result = await ContentClassifier.classify(
                fileURL: url,
                supportsAdvancedRuntime: runtimeAvailable,
                supportsAI: false
            )
            let classification = try XCTUnwrap(result)
            XCTAssertEqual(classification.requiredTier, .native,
                "HTML must never require the Enhanced runtime (runtimeAvailable=\(runtimeAvailable))")
            XCTAssertEqual(classification.recommendedPathway, .nativeHTML)
        }
    }

    // MARK: - Entitlement tier mapping

    func testScannedDocumentWithNoAISupportReturnsBasicTier() async throws {
        let url = corpusURL("2305.03393v1-pg9-img.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: 2305.03393v1-pg9-img.png")
        }

        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: false,
            supportsAI: false   // AI not available
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.kind, .scannedDocument)
        XCTAssertEqual(classification.requiredTier, .native,
            "When AI not available, scanned doc tier falls back to native (Vision OCR)")
        XCTAssertEqual(classification.recommendedPathway, .visionOCR)
    }

    func testPhotoOrArtworkAlwaysRequiresBasicTier() async throws {
        let url = corpusURL("latex/1706.03762/Figures/ModalNet-19.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Corpus fixture not found: ModalNet-19.png")
        }

        // Even with Pro+AI, diagram gets basic/metadata
        let result = await ContentClassifier.classify(
            fileURL: url,
            supportsAdvancedRuntime: true,
            supportsAI: true
        )

        let classification = try XCTUnwrap(result)
        XCTAssertEqual(classification.requiredTier, .native)
        XCTAssertEqual(classification.recommendedPathway, .metadata)
    }
}
