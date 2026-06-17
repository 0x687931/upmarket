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
        let structuredTables: [TableRepair.StructuredTable]
        let documentElementType: String?
        let handwritingRatio: Double
        let containsHandwriting: Bool
    }

    static func extract(pdfURL: URL, password: String? = nil) async throws -> Result {
        if #available(macOS 26, *) {
            return try await extractStructured(pdfURL: pdfURL, password: password)
        }
        let ocr = try await VisionOCR.recognise(pdfURL: pdfURL, password: password)
        return Result(markdown: ocr.text, pageCount: ocr.pageCount,
                     tablesFound: 0, listsFound: 0, usedStructuredAPI: false,
                     structuredTables: [], documentElementType: nil,
                     handwritingRatio: ocr.handwritingRatio,
                     containsHandwriting: ocr.containsSignificantHandwriting)
    }

    static func extract(imageURL: URL) async throws -> Result {
        if #available(macOS 26, *) {
            return try await extractImageStructured(imageURL: imageURL)
        }
        let ocr = try await VisionOCR.recognise(imageURL: imageURL)
        return Result(markdown: ocr.text, pageCount: 1,
                     tablesFound: 0, listsFound: 0, usedStructuredAPI: false,
                     structuredTables: [], documentElementType: nil,
                     handwritingRatio: ocr.handwritingRatio,
                     containsHandwriting: ocr.containsSignificantHandwriting)
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
        var allStructuredTables: [TableRepair.StructuredTable] = []
        var documentElementType: String? = nil
        var handwritingSum: Double = 0
        var handwritingCount = 0

        for i in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: i),
                  let cgImage = try autoreleasepool(invoking: { try renderPage(page) }) else { continue }
            let (md, t, l, tables, elementType, handwriting) = try await processImage(cgImage)
            if !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(md)
            }
            totalTables += t; totalLists += l
            allStructuredTables.append(contentsOf: tables)
            if documentElementType == nil, let et = elementType {
                documentElementType = et
            }
            handwritingSum += handwriting
            handwritingCount += 1
        }

        let handwritingRatio = handwritingCount == 0 ? 0.0 : handwritingSum / Double(handwritingCount)
        let containsHandwriting = handwritingRatio > 0.30

        return Result(
            markdown: pages.joined(separator: "\n\n---\n\n"),
            pageCount: pageCount, tablesFound: totalTables,
            listsFound: totalLists, usedStructuredAPI: true,
            structuredTables: allStructuredTables,
            documentElementType: documentElementType,
            handwritingRatio: handwritingRatio,
            containsHandwriting: containsHandwriting
        )
    }

    @available(macOS 26, *)
    private static func extractImageStructured(imageURL: URL) async throws -> Result {
        guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ExtractionError.cannotReadImage
        }
        try VisionProcessingLimits.validateImagePixels(width: cg.width, height: cg.height)
        let (md, t, l, tables, elementType, handwriting) = try await processImage(cg)
        return Result(markdown: md, pageCount: 1, tablesFound: t, listsFound: l, usedStructuredAPI: true,
                     structuredTables: tables, documentElementType: elementType,
                     handwritingRatio: handwriting, containsHandwriting: handwriting > 0.30)
    }

    @available(macOS 26, *)
    private static func processImage(_ cgImage: CGImage) async throws -> (String, Int, Int, [TableRepair.StructuredTable], String?, Double) {
        let request = RecognizeDocumentsRequest()
        let handler = ImageRequestHandler(cgImage)
        let observations = try await handler.perform(request)

        var parts: [String] = []
        var tables = 0; var lists = 0
        var structuredTables: [TableRepair.StructuredTable] = []
        var elementType: String? = nil
        var handwritingSum: Double = 0
        var bodyTextAll = ""
        var bodyParts: [String] = []

        for obs in observations {
            let doc = obs.document

            // Capture element type (semantic classification) - from observation if available
            if elementType == nil {
                // Note: elementType may not be directly accessible depending on Vision framework version
                // Will check if the property is exposed in this macOS version
                elementType = nil  // Placeholder - actual property path TBD from Apple docs
            }

            // Title
            if let title = doc.title {
                let t = textFromContainer(title).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { parts.append("## \(t)") }
            }
            // Body text
            let body = textFromContainer(doc.text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { parts.append(body); bodyParts.append(body); bodyTextAll += "\n" + body }
            // Tables
            for table in doc.tables {
                parts.append(tableToMarkdown(table))
                tables += 1
                // Extract structured table for repair capability
                if let structured = extractStructuredTable(table) {
                    structuredTables.append(structured)
                }
            }
            // Lists
            for list in doc.lists {
                parts.append(listToMarkdown(list))
                lists += 1
            }

            // Estimate handwriting from document content
            // (placeholder - document-level handwriting estimation would require access to rendering data)
            handwritingSum += 0.0
        }

        // ponytail: Vision misses TALL tables (validated on FinTabNet n=200: it fails to detect
        // ~40% of tables, all row-count-bound, not resolution-bound). Fallback — slice the image
        // into overlapping horizontal strips, re-run Vision per strip, stitch the cell grids back.
        // Gated on "no table detected but the page reads as numeric/columnar" so prose pages don't
        // pay the extra Vision passes. Tighten via NativeDocumentClassifier if it ever bands prose.
        if tables == 0, looksTabular(bodyTextAll) {
            for st in try await extractTablesByBanding(cgImage) {
                parts.append(gridToMarkdown(st.rows))
                tables += 1
                structuredTables.append(st)
            }
            // The banded table IS the page content — drop the duplicate body-text prose.
            if tables > 0 { parts.removeAll { bodyParts.contains($0) } }
        }

        // Average handwriting across observations
        let avgHandwriting = observations.isEmpty ? 0.0 : handwritingSum / Double(observations.count)

        return (parts.joined(separator: "\n\n"), tables, lists, structuredTables, elementType, avgHandwriting)
    }

    // MARK: - Banding fallback for tall tables

    /// Slice the image into overlapping horizontal strips (Vision detects short tables reliably),
    /// run RecognizeDocumentsRequest per strip, and stitch the per-strip cell grids back together.
    @available(macOS 26, *)
    private static func extractTablesByBanding(_ cgImage: CGImage) async throws -> [TableRepair.StructuredTable] {
        // ponytail: 200px strips / 110px overlap tuned on FinTabNet table crops (n=200). These are
        // absolute pixels; revisit if page-scale renders shift the rows-per-strip much off ~6.
        let bandHeight = 200, overlap = 110, step = bandHeight - overlap
        let h = cgImage.height
        var bandGrids: [[[String]]] = []
        var top = 0
        while top < h {
            try Task.checkCancellation()
            let rect = CGRect(x: 0, y: top, width: cgImage.width, height: min(bandHeight, h - top))
            if let band = cgImage.cropping(to: rect) {
                let obs = try await ImageRequestHandler(band).perform(RecognizeDocumentsRequest())
                if let grid = biggestTableGrid(obs) { bandGrids.append(grid) }
            }
            if top + bandHeight >= h { break }
            top += step
        }
        let stitched = stitchGrids(bandGrids)
        return stitched.isEmpty ? [] : [TableRepair.StructuredTable(rows: stitched)]
    }

    /// The table with the most cells across all observations in a strip, as a row-major grid.
    @available(macOS 26, *)
    private static func biggestTableGrid(_ observations: [DocumentObservation]) -> [[String]]? {
        var best: [[String]]? = nil
        var bestCells = 0
        for obs in observations {
            for table in obs.document.tables {
                let grid = table.rows.map { row in
                    row.map { textFromContainerBox($0.content).replacingOccurrences(of: "\n", with: " ") }
                }
                let cells = grid.reduce(0) { $0 + $1.count }
                if cells > bestCells { bestCells = cells; best = grid }
            }
        }
        return best
    }

    /// Concatenate strip grids top-to-bottom, dropping rows that duplicate the previous strip's
    /// tail (the overlap region), then normalize every row to the modal column count.
    static func stitchGrids(_ grids: [[[String]]]) -> [[String]] {
        var result: [[String]] = []
        for rows in grids where !rows.isEmpty {
            var skip = 0
            var k = min(result.count, rows.count, 4)
            while k > 0 {
                let tail = Array(result.suffix(k)), head = Array(rows.prefix(k))
                if zip(tail, head).allSatisfy({ rowsEqual($0, $1) }) { skip = k; break }
                k -= 1
            }
            result.append(contentsOf: rows.dropFirst(skip))
        }
        guard !result.isEmpty else { return [] }
        let modal = modalCount(result.map { $0.count })
        var out: [[String]] = []
        for row in result {
            if row.count == modal { out.append(row) }
            else if row.count < modal { out.append(row + Array(repeating: "", count: modal - row.count)) }
            // rows with too many columns are strip-edge artifacts -> dropped
        }
        // Drop consecutive rows sharing a non-empty first-column key: overlap dupes
        // whose OCR differed across strips slip past the exact suffix/prefix match.
        var deduped: [[String]] = []
        for row in out {
            if let last = deduped.last, rowsEqual(last, row) { continue }
            deduped.append(row)
        }
        return deduped.isEmpty ? result : deduped
    }

    private static func rowNorm(_ row: [String]) -> String {
        row.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "|")
    }

    /// Two rows are "the same" if their normalized text matches, OR they share a
    /// non-empty first-column key (the row label) — robust to OCR drift across strips.
    private static func rowsEqual(_ a: [String], _ b: [String]) -> Bool {
        if rowNorm(a) == rowNorm(b) { return true }
        let ka = a.first?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kb = b.first?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !ka.isEmpty && ka == kb
    }

    private static func modalCount(_ counts: [Int]) -> Int {
        var freq: [Int: Int] = [:]
        for c in counts { freq[c, default: 0] += 1 }
        return freq.max { $0.value < $1.value }?.key ?? 0
    }

    private static func gridToMarkdown(_ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        var lines: [String] = []
        for (i, row) in rows.enumerated() {
            lines.append("| " + row.joined(separator: " | ") + " |")
            if i == 0 { lines.append("| " + row.map { _ in "---" }.joined(separator: " | ") + " |") }
        }
        return lines.joined(separator: "\n")
    }

    /// Cheap "this page is a numeric/columnar table" signal: enough lines, many with ≥2 digit runs.
    /// ponytail: targets the validated financial-table case; widen if sparse/text tables get missed.
    private static func looksTabular(_ text: String) -> Bool {
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 6 else { return false }
        let columnar = lines.filter { line in
            line.split(whereSeparator: { !$0.isNumber }).filter { !$0.isEmpty }.count >= 2
        }
        return Double(columnar.count) / Double(lines.count) >= 0.3
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

    /// Extract structured table data for auto-repair capability
    @available(macOS 26, *)
    private static func extractStructuredTable(_ table: DocumentObservation.Container.Table) -> TableRepair.StructuredTable? {
        guard !table.rows.isEmpty else { return nil }

        var rows: [[String]] = []
        for row in table.rows {
            var cellStrings: [String] = []
            for cell in row {
                let content = textFromContainerBox(cell.content)
                cellStrings.append(content)
            }
            rows.append(cellStrings)
        }

        guard !rows.isEmpty else { return nil }
        return TableRepair.StructuredTable(rows: rows)
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
