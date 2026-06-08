import Foundation
import NaturalLanguage

struct MarkdownQualityScorer {
    struct Score: Equatable {
        let overall: Double
        let languageConfidence: Double
        let coverage: Double
        let structure: Double
        let artifactPenalty: Double
        let duplicationPenalty: Double
        let imageTextAgreement: Double?
        let reasons: [String]
    }

    static func score(
        markdown: String,
        pages: Int,
        classifierEvidence: NativeDocumentClassifier.Evidence? = nil,
        imageText: String? = nil,
        imageTextConfidence: Float? = nil
    ) -> Score {
        let normalized = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return Score(
                overall: 0,
                languageConfidence: 0,
                coverage: 0,
                structure: 0,
                artifactPenalty: 1,
                duplicationPenalty: 1,
                imageTextAgreement: imageText == nil ? nil : 0,
                reasons: ["empty output"]
            )
        }

        let language = languageConfidence(normalized)
        let coverage = coverageScore(markdown: normalized, pages: pages, evidence: classifierEvidence)
        let structure = structureScore(markdown: normalized, evidence: classifierEvidence)
        let artifactPenalty = artifactPenalty(normalized)
        let duplicationPenalty = duplicationPenalty(normalized)
        let agreement = imageText.map { textAgreement(candidate: normalized, reference: $0) }
        let confidence = imageTextConfidence.map { max(0, min(1, Double($0))) }

        var weighted: [(Double, Double)] = [
            (language, 0.20),
            (coverage, 0.30),
            (structure, 0.20),
            (1.0 - artifactPenalty, 0.15),
            (1.0 - duplicationPenalty, 0.15),
        ]
        if let agreement {
            weighted.append((agreement, 0.18))
        }
        if let confidence {
            weighted.append((confidence, 0.07))
        }

        let totalWeight = weighted.reduce(0) { $0 + $1.1 }
        let overall = weighted.reduce(0) { $0 + ($1.0 * $1.1) } / max(totalWeight, 0.01)

        return Score(
            overall: max(0, min(1, overall)),
            languageConfidence: language,
            coverage: coverage,
            structure: structure,
            artifactPenalty: artifactPenalty,
            duplicationPenalty: duplicationPenalty,
            imageTextAgreement: agreement,
            reasons: reasons(
                language: language,
                coverage: coverage,
                structure: structure,
                artifactPenalty: artifactPenalty,
                duplicationPenalty: duplicationPenalty,
                agreement: agreement
            )
        )
    }

    static func best(_ candidates: [(label: String, output: ConversionOutput, score: Score)]) -> (label: String, output: ConversionOutput, score: Score)? {
        candidates.max { lhs, rhs in
            if lhs.score.overall == rhs.score.overall {
                return lhs.output.markdown.count < rhs.output.markdown.count
            }
            return lhs.score.overall < rhs.score.overall
        }
    }

    private static func languageConfidence(_ text: String) -> Double {
        let sample = String(text.prefix(8000))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.languageHypotheses(withMaximum: 1).values.first.map { max(0, min(1, $0)) } ?? 0.35
    }

    private static func coverageScore(
        markdown: String,
        pages: Int,
        evidence: NativeDocumentClassifier.Evidence?
    ) -> Double {
        let wordCount = markdown.split { $0.isWhitespace }.count
        let pageCount = max(pages, evidence?.pageCount ?? 1, 1)
        let wordsPerPage = Double(wordCount) / Double(pageCount)

        var score = min(1.0, wordsPerPage / 180.0)
        if let evidence {
            let expectedCharacters = evidence.averageDigitalTextCharactersPerPage * max(evidence.sampledPages, 1)
            if expectedCharacters > 0 {
                let ratio = Double(markdown.count) / Double(expectedCharacters)
                let ratioScore = ratio < 1 ? ratio : max(0, 1.25 - min(ratio - 1, 1.25))
                score = max(score, min(1, ratioScore))
            }
        }
        if pages > 1 && markdown.contains("\n\n---\n\n") {
            score = min(1, score + 0.08)
        }
        return max(0, min(1, score))
    }

    private static func structureScore(markdown: String, evidence: NativeDocumentClassifier.Evidence?) -> Double {
        let lines = markdown.components(separatedBy: .newlines)
        let headingCount = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.count
        let listCount = lines.filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- ") || trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
        }.count
        let tableCount = lines.filter {
            $0.range(of: #"^\|[\s\-|:]+\|$"#, options: .regularExpression) != nil
        }.count

        var score = 0.45
        if headingCount > 0 { score += 0.18 }
        if listCount > 0 { score += 0.10 }
        if tableCount > 0 { score += 0.22 }
        if markdown.contains("```") { score += 0.08 }

        if evidence?.hasTableLikeText == true && tableCount == 0 {
            score -= 0.20
        }
        if evidence?.isLikelyFigureText == true && markdown.contains("```") {
            score += 0.14
        }
        return max(0, min(1, score))
    }

    private static func artifactPenalty(_ markdown: String) -> Double {
        var artifacts = 0
        artifacts += markdown.filter { $0 == "\u{fffd}" }.count
        artifacts += markdown.filter { $0 == "\u{00ad}" }.count
        artifacts += matches(in: markdown, pattern: #"\n\d{1,3}\n"#)
        artifacts += matches(in: markdown, pattern: #"[A-Za-z]-\s+[a-z]"#)
        // Exclude - | = and space which repeat legitimately in Markdown tables/rules
        artifacts += matches(in: markdown, pattern: #"([^\-|= \t])\1{8,}"#)
        // Rate-based threshold: normalise by word count so long documents with
        // a few PDF line-wrap hyphens don't score the same as short documents
        // with pervasive encoding errors. Cap at 1 artifact per 50 words = 1.0.
        let words = max(1, markdown.split(whereSeparator: \.isWhitespace).count)
        let rate = Double(artifacts) / Double(words)
        return min(1.0, rate * 50.0)
    }

    private static func duplicationPenalty(_ markdown: String) -> Double {
        let lines = markdown.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 8 }
        guard lines.count > 4 else { return 0 }
        let repeated = Dictionary(grouping: lines, by: { $0 }).values
            .map(\.count)
            .filter { $0 > 1 }
            .reduce(0, +)
        return min(1.0, Double(repeated) / Double(lines.count))
    }

    private static func textAgreement(candidate: String, reference: String) -> Double {
        let candidateTokens = tokenSet(candidate)
        let referenceTokens = tokenSet(reference)
        guard !candidateTokens.isEmpty, !referenceTokens.isEmpty else { return 0 }
        let overlap = candidateTokens.intersection(referenceTokens).count
        return Double(overlap) / Double(referenceTokens.count)
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
    }

    private static func matches(in text: String, pattern: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))
            .map { regex in
                regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            } ?? 0
    }

    private static func reasons(
        language: Double,
        coverage: Double,
        structure: Double,
        artifactPenalty: Double,
        duplicationPenalty: Double,
        agreement: Double?
    ) -> [String] {
        var result: [String] = []
        if language < 0.45 { result.append("low language confidence") }
        if coverage < 0.45 { result.append("low coverage") }
        if structure < 0.45 { result.append("low structure") }
        if artifactPenalty > 0.25 { result.append("extraction artifacts") }
        if duplicationPenalty > 0.25 { result.append("duplicate text") }
        if let agreement, agreement < 0.35 { result.append("low image-text agreement") }
        return result
    }
}
