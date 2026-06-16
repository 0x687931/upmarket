import Foundation

struct PDFCandidateBudget: Sendable {
    nonisolated static let `default` = PDFCandidateBudget()

    let maximumSecondaryPages: Int
    let acceptBasicScore: Double

    init(
        maximumSecondaryPages: Int = VisionProcessingLimits.maximumOCRPages,
        acceptBasicScore: Double = 0.82
    ) {
        self.maximumSecondaryPages = maximumSecondaryPages
        self.acceptBasicScore = acceptBasicScore
    }

    /// Whether to run the Apple Vision secondary candidate after the PDFKit baseline.
    func shouldRunSecondary(
        afterBasic output: ConversionOutput,
        evidence: NativeDocumentClassifier.Evidence?
    ) -> Bool {
        let pageCount = evidence?.pageCount ?? output.pages
        guard pageCount <= maximumSecondaryPages else { return false }

        if evidence?.isLikelyScanned == true { return true }

        if evidence?.hasRTLText == true || evidence?.hasMixedLanguages == true || evidence?.hasTableLikeText == true {
            return true
        }

        let score = MarkdownQualityScorer.score(
            markdown: output.markdown,
            pages: output.pages,
            classifierEvidence: evidence
        )
        return score.overall < acceptBasicScore
    }
}
