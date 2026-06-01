import XCTest
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
        XCTAssertFalse(classification.shouldUseNativeFirst)
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
}
