import Foundation
import NaturalLanguage

/// Structures raw PDF text blocks into clean Markdown using Apple's NaturalLanguage framework.
/// Runs on-device via the Neural Engine — no download, no network, all Apple Silicon optimised.
///
/// Responsibilities:
/// - Sentence boundary detection (NLTokenizer)
/// - Paragraph reconstruction from fragmented PDF lines
/// - Language detection (NLLanguageRecognizer)
/// - Heading confidence scoring (heuristics informed by NL token types)
///
/// Does NOT use font sizes — that is the Python postprocessor's job.
/// This layer operates on already-extracted text to improve structure.
struct TextStructurer {

    // MARK: - Public API

    struct Input {
        let rawMarkdown: String     // output from pdfium postprocessor
        let detectedLanguage: String?  // ISO 639-1 from analyser
    }

    struct Output {
        let markdown: String
        let detectedLanguage: String
        let sentenceCount: Int
        let paragraphCount: Int
    }

    /// Refine pdfium markdown output using NaturalLanguage.
    /// Input is already-structured markdown; this improves sentence/paragraph quality.
    static func refine(_ input: Input) -> Output {
        let text = input.rawMarkdown

        // Detect document language if not already known
        let language = input.detectedLanguage ?? detectLanguage(text)

        // Split into blocks (headings stay as-is, body text gets NL treatment)
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var bodyBuffer: [String] = []
        var totalSentences = 0
        var totalParagraphs = 0

        func flushBuffer() {
            guard !bodyBuffer.isEmpty else { return }
            let joined = bodyBuffer.joined(separator: " ")
            let (sentences, structured) = restructureParagraph(joined, language: language)
            totalSentences += sentences
            totalParagraphs += 1
            output.append(structured)
            bodyBuffer.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushBuffer()
                continue
            }

            // Preserve headings and dividers unchanged
            if trimmed.hasPrefix("#") || trimmed == "---" {
                flushBuffer()
                output.append(trimmed)
                continue
            }

            // Accumulate body text
            bodyBuffer.append(trimmed)
        }
        flushBuffer()

        let result = output
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Output(
            markdown: result,
            detectedLanguage: language,
            sentenceCount: totalSentences,
            paragraphCount: totalParagraphs
        )
    }

    // MARK: - Language Detection

    static func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        let sample = String(text.prefix(2000))
        recognizer.processString(sample)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    // MARK: - Paragraph Restructuring

    /// Use NLTokenizer to find sentence boundaries, then reflow into clean paragraphs.
    private static func restructureParagraph(
        _ text: String,
        language: String
    ) -> (sentenceCount: Int, markdown: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (0, "")
        }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(NLLanguage(rawValue: language))
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        // Rejoin sentences into clean paragraph
        let paragraph = sentences.joined(separator: " ")
        return (sentences.count, paragraph)
    }
}
