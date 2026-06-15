import Foundation

/// Parses the SpreadsheetML parts of an `.xlsx` into a `MarkdownDoc`: each
/// worksheet becomes a level-2 heading followed by a GitHub-flavored table.
///
/// Shape of the package: `xl/workbook.xml` lists sheets (by relationship id),
/// `xl/sharedStrings.xml` holds the deduplicated string pool, and each
/// `xl/worksheets/sheetN.xml` holds rows of typed cells referencing that pool.
public struct SpreadsheetParser {
    private let package: OPCPackage
    private var sharedStrings: [String] = []
    private var cellXfNumFmtIds: [Int] = []        // cellXfs index -> numFmtId
    private var customFormats: [Int: String] = [:] // numFmtId (>=164) -> format code
    private var uses1904Dates = false

    public init(package: OPCPackage) { self.package = package }

    // MARK: - Schema vocabulary

    /// `ST_CellType` values — derived from the generated `CellType` enum, which
    /// xsdgen emits from sml.xsd. (See SchemaGenerated.swift.)
    static var cellTypes: Set<String> { Set(CellType.allCases.map(\.rawValue)) }

    public mutating func parse() throws -> MarkdownDoc {
        try loadSharedStrings()
        try loadStyles()
        guard let workbook = try package.xmlRoot("xl/workbook.xml") else {
            return MarkdownDoc(blocks: [])
        }
        uses1904Dates = Self.boolAttr(workbook.firstChild("workbookPr")?.attr("date1904"))
        let rels = try package.relationships(forPart: "xl/workbook.xml")

        var blocks: [Block] = []
        let sheetsParent = workbook.firstChild("sheets") ?? workbook
        for sheet in sheetsParent.childElements("sheet") {
            let name = sheet.attr("name") ?? "Sheet"
            guard let rId = sheet.relationshipID(), let target = rels[rId] else { continue }
            let partPath = package.resolve(target: target, relativeTo: "xl/workbook.xml")
            guard let ws = try package.xmlRoot(partPath) else { continue }

            blocks.append(.paragraph(Paragraph(text: name, headingLevel: 2)))
            if let table = worksheetTable(ws) {
                blocks.append(.table(table))
            }
        }
        return MarkdownDoc(blocks: blocks)
    }

    // MARK: - Shared strings

    private mutating func loadSharedStrings() throws {
        guard let root = try package.xmlRoot("xl/sharedStrings.xml") else { return }
        var totalBytes = 0
        for si in root.childElements("si") {
            guard sharedStrings.count < ParserLimits.maxSharedStrings else {
                throw ParserLimitError.exceeded("shared string count")
            }
            let text = concatenatedText(in: si)
            totalBytes += text.utf8.count
            guard text.utf8.count <= ParserLimits.maxSharedStringLength,
                  totalBytes <= ParserLimits.maxSharedStringBytes else {
                throw ParserLimitError.exceeded("shared string bytes")
            }
            sharedStrings.append(text)
        }
    }

    // MARK: - Styles (number formats)

    private mutating func loadStyles() throws {
        guard let root = try package.xmlRoot("xl/styles.xml") else { return }
        if let numFmts = root.firstChild("numFmts") {
            for nf in numFmts.childElements("numFmt") {
                if let id = nf.attr("numFmtId").flatMap({ Int($0) }), let code = nf.attr("formatCode") {
                    customFormats[id] = code
                }
            }
        }
        if let cellXfs = root.firstChild("cellXfs") {
            cellXfNumFmtIds = cellXfs.childElements("xf").map { Int($0.attr("numFmtId") ?? "0") ?? 0 }
        }
    }

    /// Resolve a cell's `s` (cellXfs index) to its (numFmtId, custom code).
    private func numberFormat(forStyle s: String?) -> (id: Int, code: String?) {
        guard let s, let idx = Int(s), cellXfNumFmtIds.indices.contains(idx) else { return (0, nil) }
        let id = cellXfNumFmtIds[idx]
        return (id, customFormats[id])
    }

    /// Concatenate every descendant `<t>` text (handles rich-text `<r><t>` runs).
    private func concatenatedText(in element: XMLElement) -> String {
        var text = ""
        for case let child as XMLElement in element.children ?? [] {
            if child.localName == "t" { text += child.stringValue ?? "" }
            else { text += concatenatedText(in: child) }
        }
        return text
    }

    // MARK: - Worksheet → table

    private func worksheetTable(_ worksheet: XMLElement) -> Table? {
        guard let sheetData = worksheet.firstChild("sheetData") else { return nil }

        var rows: [Int: [Int: String]] = [:]   // row index -> column index -> text
        var fallbackRow = 0
        for row in sheetData.childElements("row") {
            let rowIndex = row.attr("r").flatMap { Int($0) }.map { max(0, $0 - 1) } ?? fallbackRow
            fallbackRow += 1
            guard rowIndex >= 0, rowIndex < ParserLimits.excelMaxRows,
                  rows.count < ParserLimits.maxMarkdownTableRows else { continue }
            var cells: [Int: String] = [:]
            for cell in row.childElements("c") {
                guard let col = Self.columnIndex(fromRef: cell.attr("r") ?? "") else { continue }
                let text = cellText(cell)
                if !text.isEmpty { cells[col] = text }
            }
            if !cells.isEmpty { rows[rowIndex] = cells }
        }
        return SpreadsheetTableBuilder.table(from: rows)
    }

    /// Resolve a cell's display text per its `t` (cell type), using the
    /// generated `CellType` enum.
    private func cellText(_ cell: XMLElement) -> String {
        switch CellType(rawValue: cell.attr("t") ?? "n") {
        case .s:
            if let idx = cell.firstChild("v")?.stringValue.flatMap({ Int($0) }),
               sharedStrings.indices.contains(idx) {
                return sharedStrings[idx]
            }
            return ""
        case .inlineStr:
            return cell.firstChild("is").map { concatenatedText(in: $0) } ?? ""
        case .b:
            return (cell.firstChild("v")?.stringValue == "1") ? "TRUE" : "FALSE"
        default: // n (number), str (formula string), e (error), or unknown
            let raw = cell.firstChild("v")?.stringValue ?? ""
            let type = cell.attr("t")
            if type == "str" || type == "e" { return raw }   // text/error — leave as-is
            guard let value = Double(raw) else { return raw } // numeric → apply number format
            let fmt = numberFormat(forStyle: cell.attr("s"))
            return ExcelNumberFormat.format(value: value, numFmtId: fmt.id, code: fmt.code,
                                            date1904: uses1904Dates)
        }
    }

    /// "B12" -> 1 (0-based). Letters only; ignores the row number.
    static func columnIndex(fromRef ref: String) -> Int? {
        var index = 0
        var sawLetter = false
        for ch in ref {
            guard let scalar = ch.asciiValue else { return nil }
            let upper: UInt8
            if scalar >= 65 && scalar <= 90 { upper = scalar }
            else if scalar >= 97 && scalar <= 122 { upper = scalar - 32 }
            else { break }
            sawLetter = true
            guard index <= (Int.max - 26) / 26 else { return nil }
            index = index * 26 + Int(upper - 64) // A=1
            guard index <= ParserLimits.excelMaxColumns else { return nil }
        }
        guard sawLetter, index >= 1, index <= ParserLimits.excelMaxColumns else { return nil }
        return index - 1
    }

    private static func boolAttr(_ value: String?) -> Bool {
        guard let value else { return false }
        return value == "1" || value.lowercased() == "true"
    }
}
