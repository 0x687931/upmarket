import Foundation
import NaturalLanguage

/// Extracts structured intelligence from document text using NaturalLanguage framework.
/// All processing is on-device, no network, works on all supported macOS versions.
///
/// Single responsibility: given plain text, return structured metadata and annotations.
/// Does NOT modify the Markdown — that is TextStructurer's job.
struct DocumentIntelligence {

    // MARK: - Output types

    struct Metadata {
        var title: String?
        var authors: [String]
        var organisations: [String]
        var locations: [String]
        var language: String
        var estimatedReadingMinutes: Int
        var sentimentScore: Double?      // -1.0 (negative) to 1.0 (positive)
        var keyPhrases: [String]
        var documentType: DocumentType
    }

    enum DocumentType: String {
        case academic      = "academic"
        case business      = "business"
        case technical     = "technical"
        case legal         = "legal"
        case news          = "news"
        case general       = "general"
    }

    struct HeadingAnnotation {
        let text: String
        let confidence: Double    // 0.0-1.0 — how confident we are it's a heading
        let level: Int            // 1, 2, or 3
        let isNounPhrase: Bool
        let hasVerb: Bool
    }

    struct RunningHeaderCandidate {
        let text: String
        let occurrenceCount: Int  // appears on N pages
        let similarityScore: Double
    }

    // MARK: - Public API

    /// Extract document metadata from the full text.
    static func extractMetadata(from text: String) -> Metadata {
        let language = detectLanguage(text)
        let sample = String(text.prefix(8000))

        return Metadata(
            title: extractTitle(from: sample),
            authors: extractEntities(from: sample, tag: .personalName),
            organisations: extractEntities(from: sample, tag: .organizationName),
            locations: extractEntities(from: sample, tag: .placeName),
            language: language,
            estimatedReadingMinutes: estimateReadingTime(text),
            sentimentScore: analyseSentiment(sample),
            keyPhrases: extractKeyPhrases(from: sample, language: language),
            documentType: classifyDocumentType(sample)
        )
    }

    /// Score a text block's confidence as a heading using POS analysis.
    /// Headings are typically noun phrases without main verbs.
    static func headingConfidence(for text: String, language: String) -> HeadingAnnotation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return HeadingAnnotation(text: trimmed, confidence: 0, level: 0,
                                     isNounPhrase: false, hasVerb: false)
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.setLanguage(NLLanguage(rawValue: language), range: trimmed.startIndex..<trimmed.endIndex)
        tagger.string = trimmed

        var nouns = 0, verbs = 0, adjectives = 0, total = 0

        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex,
                             unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            guard let tag else { return true }
            total += 1
            switch tag {
            case .noun, .pronoun:            nouns += 1
            case .verb:                      verbs += 1
            case .adjective, .adverb:        adjectives += 1
            default: break
            }
            return true
        }

        guard total > 0 else {
            return HeadingAnnotation(text: trimmed, confidence: 0.5, level: 1,
                                     isNounPhrase: false, hasVerb: false)
        }

        let hasVerb     = verbs > 0
        let isNounPhrase = nouns > 0 && verbs == 0

        // Confidence: high for short noun phrases, low for sentences with verbs
        var confidence: Double = 0.5
        if isNounPhrase && trimmed.count < 60 { confidence += 0.3 }
        if hasVerb { confidence -= 0.3 }
        if trimmed.count > 100 { confidence -= 0.2 }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix(",") { confidence -= 0.2 }
        if trimmed.first?.isUppercase == true { confidence += 0.1 }
        confidence = max(0.0, min(1.0, confidence))

        // Level: shorter + higher confidence = higher level heading
        let level: Int
        if confidence > 0.7 && trimmed.count < 40 { level = 1 }
        else if confidence > 0.5 && trimmed.count < 80 { level = 2 }
        else { level = 3 }

        return HeadingAnnotation(
            text: trimmed, confidence: confidence, level: level,
            isNounPhrase: isNounPhrase, hasVerb: hasVerb
        )
    }

    /// Detect running headers/footers by finding near-duplicate text across pages.
    /// Input: array of per-page text. Returns candidates to remove.
    static func detectRunningHeaders(pages: [String]) -> [RunningHeaderCandidate] {
        guard pages.count > 2 else { return [] }

        // Extract first and last lines of each page as candidates
        var lineFrequency: [String: Int] = [:]
        for pageText in pages {
            let lines = pageText.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count > 3 && $0.count < 120 }
            // Check first 2 and last 2 lines (where headers/footers live)
            let candidates = Array(lines.prefix(2)) + Array(lines.suffix(2))
            for line in candidates {
                lineFrequency[line, default: 0] += 1
            }
        }

        // Lines appearing on 3+ pages are likely running headers
        let threshold = max(3, pages.count / 3)
        return lineFrequency
            .filter { $0.value >= threshold }
            .map { RunningHeaderCandidate(
                text: $0.key,
                occurrenceCount: $0.value,
                similarityScore: Double($0.value) / Double(pages.count)
            )}
            .sorted { $0.occurrenceCount > $1.occurrenceCount }
    }

    // MARK: - Private

    private static func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    private static func extractEntities(from text: String, tag: NLTag) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var entities: [String] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .joinNames]) { foundTag, range in
            if foundTag == tag {
                let entity = String(text[range]).trimmingCharacters(in: .whitespaces)
                if entity.count > 2 && !entities.contains(entity) {
                    entities.append(entity)
                }
            }
            return true
        }
        return Array(entities.prefix(10))
    }

    private static func extractTitle(from text: String) -> String? {
        // Title is typically the first substantial line that looks like a heading
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines.prefix(5) {
            // Skip Markdown heading markers for the value
            let clean = line.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            if clean.count > 5 && clean.count < 200 && !clean.hasSuffix(".") {
                return clean
            }
        }
        return nil
    }

    private static func estimateReadingTime(_ text: String) -> Int {
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        return max(1, wordCount / 200)  // average 200 words/minute
    }

    private static func analyseSentiment(_ text: String) -> Double? {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        var scores: [Double] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .paragraph, scheme: .sentimentScore) { tag, _ in
            if let tag, let score = Double(tag.rawValue) {
                scores.append(score)
            }
            return true
        }

        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private static func extractKeyPhrases(from text: String, language: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.setLanguage(NLLanguage(rawValue: language), range: text.startIndex..<text.endIndex)
        tagger.string = text

        // Extract noun phrases (consecutive nouns/adjectives)
        var phrases: [String] = []
        var currentPhrase: [String] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let word = String(text[range])
            switch tag {
            case .noun, .adjective:
                currentPhrase.append(word)
            default:
                if currentPhrase.count >= 2 {
                    let phrase = currentPhrase.joined(separator: " ")
                    if !phrases.contains(phrase) { phrases.append(phrase) }
                }
                currentPhrase.removeAll()
            }
            return true
        }

        return Array(phrases.prefix(10))
    }

    private static func classifyDocumentType(_ text: String) -> DocumentType {
        let lower = text.lowercased()
        let indicators: [(DocumentType, [String])] = [
            (.academic,  ["abstract", "introduction", "methodology", "references", "doi:", "arxiv"]),
            (.legal,     ["whereas", "hereinafter", "plaintiff", "defendant", "court", "jurisdiction"]),
            (.business,  ["revenue", "quarterly", "fiscal year", "shareholders", "balance sheet"]),
            (.technical, ["installation", "configuration", "api", "endpoint", "parameters", "syntax"]),
            (.news,      ["reported", "according to", "said in a statement", "press release"]),
        ]

        var scores: [(DocumentType, Int)] = indicators.map { type, words in
            (type, words.filter { lower.contains($0) }.count)
        }
        scores.sort { $0.1 > $1.1 }

        return scores.first?.1 ?? 0 > 1 ? scores.first!.0 : .general
    }
}
