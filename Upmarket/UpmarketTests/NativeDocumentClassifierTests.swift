import XCTest
import AppKit
import CoreText
@testable import Upmarket

final class NativeDocumentClassifierTests: XCTestCase {
    func testScannedEvidenceRoutesToVisionWhenAvailable() {
        let evidence = NativeDocumentClassifier.Evidence(
            pageCount: 2,
            sampledPages: 2,
            averageDigitalTextCharactersPerPage: 12,
            averageLinesPerSampledPage: 4,
            shortLineRatio: 0.6,
            numericLineRatio: 0,
            hasAxisLikeText: false,
            hasRTLText: false,
            hasTableLikeText: false,
            visionTextRecognitionAvailable: true,
            coreMLAvailable: true,
            visionObservedTextLines: 20,
            visionAverageConfidence: 0.72
        )

        let classification = NativeDocumentClassifier.recommend(from: evidence)

        XCTAssertEqual(classification.recommendedPathway, .visionOCR)
        XCTAssertEqual(classification.bucket, .scannedOrUnknown)
        XCTAssertEqual(classification.complexityAdvice.recommendation, .aiRequired)
        XCTAssertTrue(classification.shouldUseNativeFirst)
    }

    func testUnavailableVisionDoesNotRouteToVisionOCR() {
        let evidence = NativeDocumentClassifier.Evidence(
            pageCount: 2,
            sampledPages: 2,
            averageDigitalTextCharactersPerPage: 12,
            averageLinesPerSampledPage: 4,
            shortLineRatio: 0.6,
            numericLineRatio: 0,
            hasAxisLikeText: false,
            hasRTLText: false,
            hasTableLikeText: false,
            visionTextRecognitionAvailable: false,
            coreMLAvailable: false,
            visionObservedTextLines: 0,
            visionAverageConfidence: 0
        )

        let classification = NativeDocumentClassifier.recommend(from: evidence)

        XCTAssertNotEqual(classification.recommendedPathway, .visionOCR)
    }

    func testComplexLayoutRoutesToEnhanced() {
        let evidence = NativeDocumentClassifier.Evidence(
            pageCount: 4,
            sampledPages: 3,
            averageDigitalTextCharactersPerPage: 2400,
            averageLinesPerSampledPage: 80,
            shortLineRatio: 0.62,
            numericLineRatio: 0.05,
            hasAxisLikeText: false,
            hasRTLText: false,
            hasTableLikeText: true,
            visionTextRecognitionAvailable: true,
            coreMLAvailable: true,
            visionObservedTextLines: 70,
            visionAverageConfidence: 0.81
        )

        let classification = NativeDocumentClassifier.recommend(from: evidence)

        XCTAssertEqual(classification.recommendedPathway, .enhanced)
        XCTAssertEqual(classification.bucket, .digitalComplex)
        XCTAssertEqual(classification.complexityAdvice.recommendation, .aiRecommended)
        XCTAssertFalse(classification.shouldUseNativeFirst)
    }

    func testDigitalTextRoutesToNativeBucket() {
        let evidence = NativeDocumentClassifier.Evidence(
            pageCount: 3,
            sampledPages: 3,
            averageDigitalTextCharactersPerPage: 1800,
            averageLinesPerSampledPage: 28,
            shortLineRatio: 0.2,
            numericLineRatio: 0.02,
            hasAxisLikeText: false,
            hasRTLText: false,
            hasTableLikeText: false,
            visionTextRecognitionAvailable: true,
            coreMLAvailable: true,
            visionObservedTextLines: 25,
            visionAverageConfidence: 0.8
        )

        let classification = NativeDocumentClassifier.recommend(from: evidence)

        XCTAssertEqual(classification.recommendedPathway, .pdfKit)
        XCTAssertEqual(classification.bucket, .native)
        XCTAssertEqual(classification.complexityAdvice.recommendation, .basic)
        XCTAssertTrue(classification.shouldUseNativeFirst)
    }

    func testDigitalPDFReportsDetectedLanguageFromPDFKitTextLayer() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketLanguageClassifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }
        let pdfURL = workspace.appendingPathComponent("french.pdf")
        try writePDF(
            to: pdfURL,
            text: """
            Ceci est un document en francais. Le rapport explique la qualite de conversion,
            la structure du texte et les resultats attendus pour plusieurs pages numeriques.
            Cette phrase donne assez de contexte pour la detection automatique de la langue.
            """
        )

        let classification = try await NativeDocumentClassifier.classify(
            pdfURL: pdfURL,
            capabilities: .unavailable
        )

        XCTAssertEqual(classification.recommendedPathway, .pdfKit)
        XCTAssertEqual(classification.evidence.detectedLanguage, "fr")
        XCTAssertGreaterThan(classification.evidence.languageConfidence, 0.2)
        XCTAssertEqual(classification.evidence.detectedLanguages, ["fr"])
        XCTAssertEqual(classification.complexityAdvice.detectedLanguage, "fr")
    }

    func testLargeDigitalPDFReportsRenderNormalizationWithoutForcingAI() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketLargePageClassifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }
        let pdfURL = workspace.appendingPathComponent("large-page.pdf")
        try writePDF(
            to: pdfURL,
            text: """
            This is a clean digital document with a very large page size. The text layer is still
            available, so the classifier should keep the basic native path and only record that
            sampled image rendering needs bounded preprocessing before OCR.
            """,
            mediaBox: CGRect(x: 0, y: 0, width: 4_000, height: 4_000),
            startY: 3_800
        )

        let classification = try await NativeDocumentClassifier.classify(
            pdfURL: pdfURL,
            capabilities: .unavailable
        )

        XCTAssertEqual(classification.recommendedPathway, .pdfKit)
        XCTAssertEqual(classification.evidence.sampledPagesRequiringRenderDownscale, 1)
        XCTAssertTrue(classification.evidence.needsImageNormalization)
        XCTAssertTrue(classification.evidence.preprocessingHints.contains("bounded image render"))
    }

    func testMixedPageLanguagesAreRecordedWithoutForcingAI() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketMixedLanguageClassifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }
        let pdfURL = workspace.appendingPathComponent("mixed-language.pdf")
        try writePDF(
            to: pdfURL,
            pages: [
                """
                This English page describes revenue recognition, reporting controls, operating
                expenses, and cash conversion. The language should be detected as English.
                """,
                """
                Ceci est une page en francais qui decrit la qualite de conversion, la structure
                du texte et les resultats attendus pour le rapport financier.
                """
            ]
        )

        let classification = try await NativeDocumentClassifier.classify(
            pdfURL: pdfURL,
            capabilities: .unavailable
        )

        XCTAssertEqual(classification.recommendedPathway, .pdfKit)
        XCTAssertTrue(classification.evidence.detectedLanguages.contains("en"))
        XCTAssertTrue(classification.evidence.detectedLanguages.contains("fr"))
        XCTAssertTrue(classification.evidence.hasMixedLanguages)
        XCTAssertTrue(classification.evidence.preprocessingHints.contains("preserve mixed-language text"))
    }

    func testVisionMultiColumnSignalRoutesToEnhanced() {
        let evidence = NativeDocumentClassifier.Evidence(
            pageCount: 2,
            sampledPages: 2,
            averageDigitalTextCharactersPerPage: 1400,
            averageLinesPerSampledPage: 30,
            shortLineRatio: 0.2,
            numericLineRatio: 0.02,
            hasAxisLikeText: false,
            hasRTLText: false,
            hasTableLikeText: false,
            visionTextRecognitionAvailable: true,
            coreMLAvailable: true,
            visionObservedTextLines: 36,
            visionAverageConfidence: 0.88,
            visionPagesWithText: 2,
            visionTextBoxCount: 36,
            visionEstimatedColumns: 2
        )

        let classification = NativeDocumentClassifier.recommend(from: evidence)

        XCTAssertEqual(classification.recommendedPathway, .enhanced)
        XCTAssertTrue(classification.reasons.contains("multi-column layout"))
        XCTAssertTrue(classification.evidence.preprocessingHints.contains("preserve multi-column layout"))
    }

    func testScannedImageNormalizationSignalRoutesToVisionOCR() {
        let evidence = NativeDocumentClassifier.Evidence(
            pageCount: 1,
            sampledPages: 1,
            averageDigitalTextCharactersPerPage: 10,
            averageLinesPerSampledPage: 1,
            shortLineRatio: 1,
            numericLineRatio: 0,
            hasAxisLikeText: false,
            hasRTLText: false,
            hasTableLikeText: false,
            visionTextRecognitionAvailable: true,
            coreMLAvailable: true,
            visionObservedTextLines: 18,
            visionAverageConfidence: 0.74,
            sampledPagesRequiringRenderDownscale: 1,
            visionPagesWithText: 1,
            visionTextBoxCount: 18,
            visionDocumentRectanglePages: 1,
            visionAverageDocumentSkewDegrees: 3.5
        )

        let classification = NativeDocumentClassifier.recommend(from: evidence)

        XCTAssertEqual(classification.recommendedPathway, .visionOCR)
        XCTAssertTrue(classification.reasons.contains("image normalization available"))
        XCTAssertTrue(classification.evidence.preprocessingHints.contains("crop or deskew document image"))
    }

    func testBasicPDFKitRecommendationDoesNotShowAILanguageWarning() {
        let advice = ComplexityAdvice(
            recommendation: .basic,
            score: 70,
            reasons: ["digital text"],
            detectedLanguage: "zh"
        )

        XCTAssertNil(advice.languageQualityWarning)
    }

    func testAdvancedRecommendationStillShowsLanguageWarning() {
        let advice = ComplexityAdvice(
            recommendation: .aiRecommended,
            score: 78,
            reasons: ["table-like text"],
            detectedLanguage: "zh"
        )

        XCTAssertNotNil(advice.languageQualityWarning)
    }

    func testCorpusPDFClassifiesWithFrameworksUnavailable() async throws {
        let pdfURL = corpusDoclingPath.appendingPathComponent("tests/data/pdf/normal_4pages.pdf")
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            throw XCTSkip("Docling corpus not available")
        }

        let classification = try await NativeDocumentClassifier.classify(
            pdfURL: pdfURL,
            capabilities: .unavailable
        )

        XCTAssertFalse(classification.evidence.visionTextRecognitionAvailable)
        XCTAssertFalse(classification.evidence.coreMLAvailable)
        XCTAssertNotEqual(classification.recommendedPathway, .visionOCR)
        XCTAssertGreaterThan(classification.evidence.pageCount, 0)
    }

    private var corpusDoclingPath: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tests/corpus/docling/docling")
    }

    private func writePDF(
        to url: URL,
        text: String,
        mediaBox: CGRect = CGRect(x: 0, y: 0, width: 500, height: 320),
        startY: Int = 250
    ) throws {
        try writePDF(to: url, pages: [text], mediaBox: mediaBox, startY: startY)
    }

    private func writePDF(
        to url: URL,
        pages: [String],
        mediaBox: CGRect = CGRect(x: 0, y: 0, width: 500, height: 320),
        startY: Int = 250
    ) throws {
        var pageBox = mediaBox
        guard let context = CGContext(url as CFURL, mediaBox: &pageBox, nil) else {
            throw NSError(domain: "NativeDocumentClassifierTests", code: 1)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]
        for page in pages {
            context.beginPDFPage(nil)
            var y = startY
            for line in page.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
                context.textPosition = CGPoint(x: 40, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes)), context)
                y -= 28
            }
            context.endPDFPage()
        }
        context.closePDF()
    }
}
