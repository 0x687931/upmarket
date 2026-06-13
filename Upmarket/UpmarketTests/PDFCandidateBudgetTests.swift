import XCTest
@testable import Upmarket

final class PDFCandidateBudgetTests: XCTestCase {
    func testAcceptsStrongDigitalPDFKitOutputWithoutSecondaryPath() {
        let budget = PDFCandidateBudget(
            maximumFullFanoutPages: 12,
            maximumSecondaryPages: 80,
            acceptBasicScore: 0.10
        )
        let output = ConversionOutput(
            markdown: """
            # Quarterly Report

            Revenue increased across every operating region. The balance sheet remains strong, operating cash flow improved, and forecast demand supports the next quarter.
            """,
            pages: 1,
            format: "PDF",
            title: "Report",
            pipeline: .fast,
            selectedPathway: .pdfKit
        )

        XCTAssertFalse(budget.shouldRunSecondary(
            afterBasic: output,
            evidence: Self.digitalEvidence(pageCount: 1),
            secondary: .advanced(useAI: false)
        ))
    }

    func testRunsSecondaryForScannedEvidenceWithinBudget() {
        let budget = PDFCandidateBudget(maximumSecondaryPages: 80)
        let output = ConversionOutput(
            markdown: "",
            pages: 3,
            format: "PDF",
            title: "Scan",
            pipeline: .fast,
            selectedPathway: .pdfKit
        )

        XCTAssertTrue(budget.shouldRunSecondary(
            afterBasic: output,
            evidence: Self.scannedEvidence(pageCount: 3),
            secondary: .imageText
        ))
    }

    func testRejectsSecondaryWhenPageBudgetIsExceeded() {
        let budget = PDFCandidateBudget(maximumSecondaryPages: 2)
        let output = ConversionOutput(
            markdown: "",
            pages: 3,
            format: "PDF",
            title: "Large Scan",
            pipeline: .fast,
            selectedPathway: .pdfKit
        )

        XCTAssertFalse(budget.shouldRunSecondary(
            afterBasic: output,
            evidence: Self.scannedEvidence(pageCount: 3),
            secondary: .imageText
        ))
    }

    func testFullFanoutIsPageBounded() {
        let budget = PDFCandidateBudget(maximumFullFanoutPages: 4)

        XCTAssertTrue(budget.allowsFullFanout(evidence: Self.scannedEvidence(pageCount: 4)))
        XCTAssertFalse(budget.allowsFullFanout(evidence: Self.scannedEvidence(pageCount: 5)))
    }

    private static func digitalEvidence(pageCount: Int) -> NativeDocumentClassifier.Evidence {
        NativeDocumentClassifier.Evidence(
            pageCount: pageCount,
            sampledPages: 1,
            averageDigitalTextCharactersPerPage: 1_200,
            averageLinesPerSampledPage: 30,
            shortLineRatio: 0.1,
            numericLineRatio: 0.05,
            hasAxisLikeText: false,
            hasRTLText: false,
            hasTableLikeText: false,
            visionTextRecognitionAvailable: true,
            coreMLAvailable: true,
            visionObservedTextLines: 30,
            visionAverageConfidence: 0.95
        )
    }

    private static func scannedEvidence(pageCount: Int) -> NativeDocumentClassifier.Evidence {
        NativeDocumentClassifier.Evidence(
            pageCount: pageCount,
            sampledPages: 1,
            averageDigitalTextCharactersPerPage: 0,
            averageLinesPerSampledPage: 0,
            shortLineRatio: 0,
            numericLineRatio: 0,
            hasAxisLikeText: false,
            hasRTLText: false,
            hasTableLikeText: false,
            visionTextRecognitionAvailable: true,
            coreMLAvailable: true,
            visionObservedTextLines: 0,
            visionAverageConfidence: 0
        )
    }
}
