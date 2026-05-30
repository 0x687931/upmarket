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
        var lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

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
