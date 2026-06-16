import Foundation
import PDFKit

/// Fast PDF→Markdown using Apple's PDFKit.
/// Zero download, zero dependency, built into every Mac.
/// Quality: excellent for digital PDFs. Falls back gracefully for scanned.
struct PDFConverter {

    struct Limits {
        let maximumPages: Int
        let maximumPageSidePoints: CGFloat
        let maximumPageAreaPoints: CGFloat

        static let nativePDFKit = Limits(
            maximumPages: VisionProcessingLimits.maximumPDFKitPages,
            maximumPageSidePoints: VisionProcessingLimits.maximumPDFPageSidePoints,
            maximumPageAreaPoints: VisionProcessingLimits.maximumPDFPageAreaPoints
        )
    }

    struct Result {
        let markdown: String
        let pageCount: Int
        let isLikelyScanned: Bool  // low text → suggest Enhanced
    }

    static func convert(url: URL, password: String? = nil, limits: Limits = .nativePDFKit) throws -> Result {
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
        try VisionProcessingLimits.validatePDFKitPageCount(pageCount, maximum: limits.maximumPages)

        var markdown = ""
        var totalChars = 0

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            try VisionProcessingLimits.validatePDFPageBounds(
                page.bounds(for: .mediaBox),
                maximumSide: limits.maximumPageSidePoints,
                maximumArea: limits.maximumPageAreaPoints
            )
            let text = cleanText(page.string ?? "")
            totalChars += text.count

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            let md = pageToMarkdown(page: page, text: text)
            if !markdown.isEmpty {
                markdown += "\n\n---\n\n"
            }
            markdown += md
        }

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

        let result = lines.map { headingMarkup(for: $0) ?? $0 }
        return result.joined(separator: "\n")
    }

    // Numbered section heading, e.g. "1 Executive Summary", "2.1 Overview", "3.3 Financials".
    // Requires a capital after the number so body list items like "1. we did x" don't match.
    private static let numberedHeading = try! NSRegularExpression(pattern: #"^(\d+(?:\.\d+)*)\.?\s+[A-Z]"#)
    private static let dotLeaders = try! NSRegularExpression(pattern: #"\.{4,}"#)

    /// Markdown heading markup for `line` if it looks like a section heading, else nil.
    /// Levels follow section depth (depth 1 → `##`, 2 → `###`, …); cover-page ALL-CAPS
    /// banners become a single `#`. Table-of-contents rows (dot leaders) are never headings.
    private static func headingMarkup(for line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        // Skip ToC entries and sentence-like / long lines.
        if dotLeaders.firstMatch(in: line, range: range) != nil { return nil }
        if line.count > 80 || line.hasSuffix(".") || line.hasSuffix(",") || line.hasSuffix(";") { return nil }

        if let match = numberedHeading.firstMatch(in: line, range: range),
           let numbers = Range(match.range(at: 1), in: line) {
            let depth = line[numbers].split(separator: ".").count
            return String(repeating: "#", count: min(depth + 1, 6)) + " " + line
        }

        // Cover-page / banner lines in all caps (e.g. "CAPSTONE").
        let letters = line.filter(\.isLetter)
        if letters.count >= 2, letters.allSatisfy(\.isUppercase) {
            return "# " + line
        }
        return nil
    }

    /// PDFKit glyph spacing often inserts a space after an intra-word hyphen ("start- up").
    /// Collapse `<letter>- <letter>` → `<letter>-<letter>`; spaced em-dashes (" - ", "—")
    /// used as punctuation are left untouched (they have a space *before* the dash too).
    private static let hyphenSpacing = try! NSRegularExpression(pattern: #"(?<=[A-Za-z])-[ \t]+(?=[A-Za-z])"#)
    private static func cleanText(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return hyphenSpacing.stringByReplacingMatches(in: text, range: range, withTemplate: "-")
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
