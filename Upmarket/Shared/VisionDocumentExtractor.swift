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

    /// The strip-and-stitch banding fallback overrides the page body with a reconstructed grid.
    /// Validated on the IDL corpus it does net harm: its stitch mis-groups cells and drops prose
    /// (it tanked klpb0135 and fnpd0075), and row-major reading order already recovers label↔value
    /// association without it. Disabled pending a stitch-quality fix; the banding functions and
    /// their unit tests remain so that work can resume against them.
    private static let tableBandingEnabled = false

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
            // Stage 2 text source — self-detected: born-digital pages (text layer, no full-page
            // image) resolve exact text from PDFKit; scans return nil and fall back to Vision OCR.
            let resolver = digitalTextResolver(for: page)
            let (md, t, l, tables, elementType, handwriting) = try await processImage(cgImage, textResolver: resolver)
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

    /// Stage 2 text source for a digital page: maps a Vision normalized line box into PDF space
    /// and returns the exact PDFKit text inside it, or nil for a page with no usable text layer
    /// (scanned), so callers fall back to Vision OCR. Returns nil text for empty regions too.
    /// A born-digital page draws its text as vectors; a scan is one full-page raster image with
    /// an (often worse) OCR text layer over it. Detect the scan by a single image XObject that
    /// covers most of the page — a far more reliable signal than text-layer length, which both
    /// kinds have. Validated on the IDL corpus (scans ≈2–4× page area) vs e-tickets (≈0.03).
    private static func pageIsRasterScan(_ page: PDFPage) -> Bool {
        guard let cg = page.pageRef, let dict = cg.dictionary else { return false }
        let box = page.bounds(for: .mediaBox)
        let pageArea = Double(box.width * box.height)
        guard pageArea > 0 else { return false }
        var res: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, "Resources", &res), let res else { return false }
        var xobj: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(res, "XObject", &xobj), let xobj else { return false }
        var maxFraction = 0.0
        CGPDFDictionaryApplyBlock(xobj, { _, value, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(value, .stream, &stream), let stream,
                  let sd = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(sd, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Image" else { return true }
            var w: CGPDFReal = 0, h: CGPDFReal = 0
            CGPDFDictionaryGetNumber(sd, "Width", &w); CGPDFDictionaryGetNumber(sd, "Height", &h)
            let estPoints = (Double(w) / 150.0 * 72.0) * (Double(h) / 150.0 * 72.0)  // assume ~150 dpi
            maxFraction = max(maxFraction, estPoints / pageArea)
            return true
        }, nil)
        return maxFraction >= 0.3
    }

    @available(macOS 26, *)
    private static func digitalTextResolver(for page: PDFPage) -> ((CGRect) -> String?)? {
        guard page.numberOfCharacters > 40, !pageIsRasterScan(page) else { return nil }  // scanned → OCR
        let pb = page.bounds(for: .mediaBox)
        guard pb.width > 0, pb.height > 0 else { return nil }
        return { nb in
            let r = CGRect(x: pb.minX + nb.minX * pb.width, y: pb.minY + nb.minY * pb.height,
                           width: nb.width * pb.width, height: nb.height * pb.height)
            let s = page.selection(for: r)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty == false) ? s : nil
        }
    }

    @available(macOS 26, *)
    private static func processImage(_ cgImage: CGImage, textResolver: ((CGRect) -> String?)? = nil) async throws -> (String, Int, Int, [TableRepair.StructuredTable], String?, Double) {
        let request = RecognizeDocumentsRequest()   // language correction is on by default
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
            // Body text, reconstructed row-major from line geometry (Vision's own order walks
            // multi-column layouts column-major; see rowMajorText).
            let body = rowMajorText(doc.text, resolver: textResolver).trimmingCharacters(in: .whitespacesAndNewlines)
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
            // Lists — Vision often classifies a table's bulleted label column as BOTH body text
            // and a list, emitting it twice. Skip a list whose words are already in the body;
            // keep genuine lists that live only in the list container.
            let bodyWords = Set(tokenize(body))
            for list in doc.lists {
                let items = list.items.map { textFromContainerBox($0.content) }
                if isDuplicatedInBody(items: items, bodyWords: bodyWords) { continue }
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
        if Self.tableBandingEnabled, tables == 0, looksTabular(bodyTextAll) {
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

    /// Reading order reconstructed from line geometry. Vision's own line order walks
    /// wide-gap multi-column layouts column-major — it emits a whole label column, then a
    /// detached value column — which severs label↔value association in tables and forms
    /// (validated on the IDL corpus: klpb0135's trial table, fnpd0075's four data-table
    /// pages). Group lines into rows by vertical band (centres within a shared y-span), then
    /// order rows top→bottom and lines left→right within each row. Single-column prose has one
    /// line per band, so it collapses to the natural top-to-bottom order unchanged.
    @available(macOS 26, *)
    private static func rowMajorText(_ text: DocumentObservation.Container.Text,
                                     resolver: ((CGRect) -> String?)? = nil) -> String {
        let lines: [(rect: CGRect, ocr: String)] = text.lines.compactMap { obs in
            guard let s = obs.topCandidates(1).first?.string, !s.isEmpty else { return nil }
            let b = obs.boundingRegion.boundingBox
            return (CGRect(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height), s)
        }
        guard !lines.isEmpty else { return "" }

        // Top→bottom (normalized space: y grows upward). A line joins the current row when its
        // vertical centre lies within the row anchor's span; otherwise it opens a new row.
        // Anchoring on the row's first (topmost) line stops a tall cell swallowing the next row.
        let ordered = lines.sorted { $0.rect.midY > $1.rect.midY }
        var rows: [[(rect: CGRect, ocr: String)]] = []
        for line in ordered {
            if let anchor = rows.last?.first,
               line.rect.midY <= anchor.rect.maxY, line.rect.midY >= anchor.rect.minY {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row -> String in
            let cells = row.sorted { $0.rect.minX < $1.rect.minX }
            // Scanned page: no text layer — use Vision's recognised text verbatim (unchanged).
            guard let resolver else { return cells.map(\.ocr).joined(separator: "  ") }
            // Digital page: pull EXACT text per cell from PDFKit. Snap each cell's left/right to
            // the gutter midpoint between neighbouring cells (outer edges padded by ~a glyph), so
            // the selection rect lands in whitespace and never clips the boundary glyph that
            // Vision's tight image-derived box would otherwise drop.
            let margin = (cells.map(\.rect.height).max() ?? 0.012) * 0.6
            return cells.enumerated().map { j, cell in
                let left = j == 0 ? cell.rect.minX - margin : (cells[j - 1].rect.maxX + cell.rect.minX) / 2
                let right = j == cells.count - 1 ? cell.rect.maxX + margin : (cell.rect.maxX + cells[j + 1].rect.minX) / 2
                let snapped = CGRect(x: left, y: cell.rect.minY, width: max(0, right - left), height: cell.rect.height)
                return resolver(snapped) ?? cell.ocr
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    private static func tokenize(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
    }

    /// True when most of a list's words already appear in the body — i.e. Vision emitted the
    /// same content as both text and a list (the bulleted label column of a table). Positionless
    /// so it generalises; short lists are kept (too little signal to call a duplicate).
    private static func isDuplicatedInBody(items: [String], bodyWords: Set<String>) -> Bool {
        let words = items.flatMap { tokenize($0) }
        guard words.count >= 3 else { return false }
        return Double(words.filter { bodyWords.contains($0) }.count) / Double(words.count) >= 0.7
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
