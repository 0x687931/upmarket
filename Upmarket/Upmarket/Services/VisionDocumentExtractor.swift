import Foundation
import Vision
import PDFKit

/// Structured document extraction using Vision's RecognizeDocumentsRequest (macOS 26+).
/// Extracts text WITH structure: paragraphs, tables (rows/columns/cells), lists.
/// Falls back to VisionOCR (VNRecognizeTextRequest) on macOS < 26.
struct VisionDocumentExtractor {

    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    struct Result {
        let markdown: String
        let pageCount: Int
        let tablesFound: Int
        let listsFound: Int
        let usedStructuredAPI: Bool
    }

    static func extract(pdfURL: URL, password: String? = nil) async throws -> Result {
        if #available(macOS 26, *) {
            return try await extractStructured(pdfURL: pdfURL, password: password)
        }
        let ocr = try await VisionOCR.recognise(pdfURL: pdfURL, password: password)
        return Result(markdown: ocr.text, pageCount: ocr.pageCount,
                     tablesFound: 0, listsFound: 0, usedStructuredAPI: false)
    }

    static func extract(imageURL: URL) async throws -> Result {
        if #available(macOS 26, *) {
            return try await extractImageStructured(imageURL: imageURL)
        }
        let ocr = try await VisionOCR.recognise(imageURL: imageURL)
        return Result(markdown: ocr.text, pageCount: 1,
                     tablesFound: 0, listsFound: 0, usedStructuredAPI: false)
    }

    // MARK: - macOS 26 structured extraction

    @available(macOS 26, *)
    private static func extractStructured(pdfURL: URL, password: String?) async throws -> Result {
        guard let document = PDFDocument(url: pdfURL) else { throw ExtractionError.cannotOpenPDF }
        if document.isLocked {
            guard let pwd = password, document.unlock(withPassword: pwd) else {
                throw ExtractionError.passwordRequired
            }
        }

        let pageCount = document.pageCount
        try VisionProcessingLimits.validatePageCount(pageCount)
        var pages: [String] = []
        var totalTables = 0; var totalLists = 0

        for i in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: i),
                  let cgImage = try autoreleasepool(invoking: { try renderPage(page) }) else { continue }
            let (md, t, l) = try await processImage(cgImage)
            if !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(md)
            }
            totalTables += t; totalLists += l
        }

        return Result(
            markdown: pages.joined(separator: "\n\n---\n\n"),
            pageCount: pageCount, tablesFound: totalTables,
            listsFound: totalLists, usedStructuredAPI: true
        )
    }

    @available(macOS 26, *)
    private static func extractImageStructured(imageURL: URL) async throws -> Result {
        guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ExtractionError.cannotReadImage
        }
        try VisionProcessingLimits.validateImagePixels(width: cg.width, height: cg.height)
        let (md, t, l) = try await processImage(cg)
        return Result(markdown: md, pageCount: 1, tablesFound: t, listsFound: l, usedStructuredAPI: true)
    }

    @available(macOS 26, *)
    private static func processImage(_ cgImage: CGImage) async throws -> (String, Int, Int) {
        let request = RecognizeDocumentsRequest()
        let handler = ImageRequestHandler(cgImage)
        let observations = try await handler.perform(request)

        var parts: [String] = []
        var tables = 0; var lists = 0

        for obs in observations {
            let doc = obs.document
            // Title
            if let title = doc.title {
                let t = textFromContainer(title).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { parts.append("## \(t)") }
            }
            // Body text
            let body = textFromContainer(doc.text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { parts.append(body) }
            // Tables
            for table in doc.tables {
                parts.append(tableToMarkdown(table))
                tables += 1
            }
            // Lists
            for list in doc.lists {
                parts.append(listToMarkdown(list))
                lists += 1
            }
        }

        return (parts.joined(separator: "\n\n"), tables, lists)
    }

    // MARK: - Container → Markdown converters

    /// Extract plain text from a Container.Text by joining all recognised lines.
    @available(macOS 26, *)
    private static func textFromContainer(_ text: DocumentObservation.Container.Text) -> String {
        text.lines
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    @available(macOS 26, *)
    private static func textFromContainerBox(_ container: DocumentObservation.Container) -> String {
        textFromContainer(container.text)
    }

    @available(macOS 26, *)
    private static func tableToMarkdown(_ table: DocumentObservation.Container.Table) -> String {
        guard !table.rows.isEmpty else { return "" }
        var lines: [String] = []
        for (i, row) in table.rows.enumerated() {
            let cells = row.map { textFromContainerBox($0.content).replacingOccurrences(of: "\n", with: " ") }
            lines.append("| " + cells.joined(separator: " | ") + " |")
            if i == 0 { lines.append("| " + cells.map { _ in "---" }.joined(separator: " | ") + " |") }
        }
        return lines.joined(separator: "\n")
    }

    @available(macOS 26, *)
    private static func listToMarkdown(_ list: DocumentObservation.Container.List) -> String {
        list.items.map { item in
            "- \(textFromContainerBox(item.content))"
        }.joined(separator: "\n")
    }

    // MARK: - PDF page renderer

    private static func renderPage(_ page: PDFPage) throws -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let size = try VisionProcessingLimits.renderSize(for: bounds, dpi: 150)
        let w = size.width; let h = size.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(w) / bounds.width, y: CGFloat(h) / bounds.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        page.draw(with: .mediaBox, to: ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    enum ExtractionError: LocalizedError {
        case cannotOpenPDF, passwordRequired, cannotReadImage
        var errorDescription: String? {
            switch self {
            case .cannotOpenPDF:    return "Upmarket couldn't open this document."
            case .passwordRequired: return "This PDF is password-protected."
            case .cannotReadImage:  return "Upmarket couldn't read this image."
            }
        }
    }
}
