import Foundation

struct PDFCandidateBudget: Sendable {
    nonisolated static let `default` = PDFCandidateBudget()

    let maximumFullFanoutPages: Int
    let maximumSecondaryPages: Int
    let acceptBasicScore: Double

    init(
        maximumFullFanoutPages: Int = 12,
        maximumSecondaryPages: Int = VisionProcessingLimits.maximumOCRPages,
        acceptBasicScore: Double = 0.82
    ) {
        self.maximumFullFanoutPages = maximumFullFanoutPages
        self.maximumSecondaryPages = maximumSecondaryPages
        self.acceptBasicScore = acceptBasicScore
    }

    func allowsFullFanout(evidence: NativeDocumentClassifier.Evidence?) -> Bool {
        (evidence?.pageCount ?? 1) <= maximumFullFanoutPages
    }

    func shouldRunSecondary(
        afterBasic output: ConversionOutput,
        evidence: NativeDocumentClassifier.Evidence?,
        secondary: ConversionRunner.PDFSecondaryCandidate
    ) -> Bool {
        let pageCount = evidence?.pageCount ?? output.pages
        guard pageCount <= maximumSecondaryPages else { return false }

        switch secondary {
        case .imageText:
            if evidence?.isLikelyScanned == true { return true }
        case .advanced, .all:
            break
        }

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
