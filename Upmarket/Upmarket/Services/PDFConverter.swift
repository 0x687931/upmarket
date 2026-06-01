import Foundation
import PDFKit

/// Fast PDF→Markdown using Apple's PDFKit.
/// Zero download, zero dependency, built into every Mac.
/// Quality: excellent for digital PDFs. Falls back gracefully for scanned.
struct PDFConverter {

    struct Result {
        let markdown: String
        let pageCount: Int
        let isLikelyScanned: Bool  // low text → suggest Enhanced
    }

    static func convert(url: URL, password: String? = nil) throws -> Result {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.cannotOpen
        }

        // Handle password-protected PDFs
        if document.isLocked {
            if let password, document.unlock(withPassword: password) {
                // unlocked — continue
            } else {
                throw ConversionError.passwordRequired
            }
        }

        let pageCount = document.pageCount
        var pages: [String] = []
        var totalChars = 0

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let text = page.string ?? ""
            totalChars += text.count

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            // Convert page to structured markdown
            let md = pageToMarkdown(page: page, text: text)
            pages.append(md)
        }

        let markdown = pages.joined(separator: "\n\n---\n\n")

        // Low text density suggests scanned document
        let avgCharsPerPage = pageCount > 0 ? totalChars / pageCount : 0
        let isLikelyScanned = avgCharsPerPage < 100 && pageCount > 0

        return Result(markdown: markdown, pageCount: pageCount, isLikelyScanned: isLikelyScanned)
    }

    // MARK: - Private

    private static func pageToMarkdown(page: PDFPage, text: String) -> String {
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if isLikelyFigureText(lines) {
            return figureTextMarkdown(lines)
        }

        // Heuristic: detect headings by font size via annotations
        // PDFKit doesn't expose font sizes directly, so we use line length + position heuristics
        var result: [String] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Short lines at start of page that aren't sentences are likely headings
            let isLikelyHeading = trimmed.count < 80
                && !trimmed.hasSuffix(".")
                && !trimmed.hasSuffix(",")
                && i < 3

            if isLikelyHeading && i == 0 {
                result.append("## \(trimmed)")
            } else {
                result.append(trimmed)
            }
        }

        return result.joined(separator: "\n")
    }

    private static func isLikelyFigureText(_ lines: [String]) -> Bool {
        guard !lines.isEmpty, lines.count <= 14 else { return false }
        let joined = lines.joined(separator: " ")
        let words = joined.split { $0.isWhitespace }
        guard words.count <= 24 else { return false }

        let numericLines = lines.filter { line in
            line.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil
        }.count
        let sentenceLines = lines.filter { $0.hasSuffix(".") || $0.hasSuffix(":") }.count
        let hasAxisLikeText = joined.contains("[") || joined.contains("]") || joined.contains("/") || joined.contains("MeV")

        return sentenceLines == 0 && (numericLines >= 3 || hasAxisLikeText)
    }

    private static func figureTextMarkdown(_ lines: [String]) -> String {
        let repaired = repairSingleCharacterLabels(lines)
        return """
        Extracted figure text:

        ```text
        \(repaired.joined(separator: "\n"))
        ```
        """
    }

    private static func repairSingleCharacterLabels(_ lines: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if index + 1 < lines.count,
               line.count == 1,
               lines[index + 1].count == 1,
               line.rangeOfCharacter(from: .letters) != nil,
               lines[index + 1].rangeOfCharacter(from: .letters) != nil {
                result.append(line + lines[index + 1])
                index += 2
            } else {
                result.append(line)
                index += 1
            }
        }
        return result
    }

    enum ConversionError: LocalizedError {
        case cannotOpen
        case passwordRequired

        var errorDescription: String? {
            switch self {
            case .cannotOpen:       return "Upmarket couldn't open this PDF."
            case .passwordRequired: return "This PDF is password-protected."
            }
        }
    }
}
