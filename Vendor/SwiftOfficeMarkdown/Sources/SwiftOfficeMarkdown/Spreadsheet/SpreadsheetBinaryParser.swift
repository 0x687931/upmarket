import Foundation

/// Parses binary `.xlsb` (BIFF12) spreadsheet parts into a `MarkdownDoc` —
/// identical output to the XML `SpreadsheetParser`, just a different on-disk
/// encoding. Implemented from [MS-XLSB]: `xl/workbook.bin` lists sheets,
/// `xl/sharedStrings.bin` holds the string pool, each `xl/worksheets/*.bin`
/// holds rows of typed cell records.
struct SpreadsheetBinaryParser {
    private let package: OPCPackage

    init(package: OPCPackage) { self.package = package }

    /// Record type numbers ([MS-XLSB] §2.3 Record Enumeration).
    private enum Rec {
        static let bundleSh = 156, beginSst = 159, sstItem = 19, rowHdr = 0
        static let cellBlank = 1, cellRk = 2, cellError = 3, cellBool = 4
        static let cellReal = 5, cellSt = 6, cellIsst = 7, cellRString = 62
        static let fmt = 44, xf = 47, beginCellXFs = 617      // styles (number formats)
        static let wbProp = 153
    }

    private struct Styles { var fmtIds: [Int] = []; var custom: [Int: String] = [:] }
    private struct WorkbookInfo { var sheets: [SheetRef] = []; var date1904 = false }

    func parse() throws -> MarkdownDoc {
        let sst = try sharedStrings()
        let styles = try loadStyles()
        let workbook = try workbookInfo()
        var blocks: [Block] = []
        for sheet in workbook.sheets {
            blocks.append(.paragraph(Paragraph(text: sheet.name, headingLevel: 2)))
            if let table = try worksheetTable(part: sheet.part, sst: sst, styles: styles,
                                              date1904: workbook.date1904) {
                blocks.append(.table(table))
            }
        }
        return MarkdownDoc(blocks: blocks)
    }

    /// `xl/styles.bin` → BrtFmt custom format codes + the cell XFs' format ids.
    private func loadStyles() throws -> Styles {
        guard let data = try package.part("xl/styles.bin") else { return Styles() }
        var reader = BIFF12Reader(data)
        var styles = Styles()
        var inCellXFs = false
        while let rec = reader.next() {
            switch rec.type {
            case Rec.fmt:
                var p = BIFF12Payload(rec.payload)
                let ifmt = p.u16()
                styles.custom[ifmt] = p.xlWideString()
            case Rec.beginCellXFs:
                inCellXFs = true
            case Rec.xf where inCellXFs:
                var p = BIFF12Payload(rec.payload)
                p.skip(2)                       // ixfeParent
                styles.fmtIds.append(p.u16())   // iFmt
            default:
                break
            }
        }
        return styles
    }

    private struct SheetRef { let name: String; let part: String }

    /// `xl/workbook.bin` → BrtBundleSh records (sheet name + relationship id).
    private func workbookInfo() throws -> WorkbookInfo {
        guard let data = try package.part("xl/workbook.bin") else { return WorkbookInfo() }
        let rels = try package.relationships(forPart: "xl/workbook.bin")
        var reader = BIFF12Reader(data)
        var result = WorkbookInfo()
        while let rec = reader.next() {
            switch rec.type {
            case Rec.wbProp:
                var p = BIFF12Payload(rec.payload)
                result.date1904 = (p.u32() & 0x0000_0001) != 0
            case Rec.bundleSh:
                var p = BIFF12Payload(rec.payload)
                p.skip(8)                                  // hsState(4) + iTabID(4)
                let relId = p.xlNullableWideString()       // strRelID
                let name = p.xlWideString()                // strName
                guard let relId, let target = rels[relId] else { continue }
                result.sheets.append(SheetRef(name: name,
                                              part: package.resolve(target: target, relativeTo: "xl/workbook.bin")))
            default:
                break
            }
        }
        return result
    }

    /// `xl/sharedStrings.bin` → BrtSSTItem records (each a RichStr).
    private func sharedStrings() throws -> [String] {
        guard let data = try package.part("xl/sharedStrings.bin") else { return [] }
        var reader = BIFF12Reader(data)
        var result: [String] = []
        var totalBytes = 0
        while let rec = reader.next() {
            if rec.type == Rec.sstItem {
                guard result.count < ParserLimits.maxSharedStrings else {
                    throw ParserLimitError.exceeded("shared string count")
                }
                var p = BIFF12Payload(rec.payload)
                let text = p.richStr()
                totalBytes += text.utf8.count
                guard text.utf8.count <= ParserLimits.maxSharedStringLength,
                      totalBytes <= ParserLimits.maxSharedStringBytes else {
                    throw ParserLimitError.exceeded("shared string bytes")
                }
                result.append(text)
            }
        }
        return result
    }

    /// A worksheet part → a GFM table (rows of cells, BrtRowHdr sets the row).
    private func worksheetTable(part: String, sst: [String], styles: Styles, date1904: Bool) throws -> Table? {
        guard let data = try package.part(part) else { return nil }
        var reader = BIFF12Reader(data)
        var rows: [Int: [Int: String]] = [:]
        var currentRow = 0

        while let rec = reader.next() {
            switch rec.type {
            case Rec.rowHdr:
                var p = BIFF12Payload(rec.payload)
                currentRow = Int(p.u32())
                if currentRow < 0 || currentRow >= ParserLimits.excelMaxRows { currentRow = -1 }
            case Rec.cellIsst, Rec.cellRk, Rec.cellReal, Rec.cellSt,
                 Rec.cellRString, Rec.cellBool, Rec.cellError, Rec.cellBlank:
                guard currentRow >= 0, rows.count < ParserLimits.maxMarkdownTableRows else { continue }
                var p = BIFF12Payload(rec.payload)
                let col = Int(p.u32())                       // Cell.column ([MS-XLSB] §2.5.10)
                guard col >= 0, col < ParserLimits.excelMaxColumns else { continue }
                let iStyleRef = Int(p.u32() & 0x00FF_FFFF)   // iStyleRef (24 bits) + flags (8)
                let text = cellText(type: rec.type, payload: &p, sst: sst, iStyleRef: iStyleRef,
                                    styles: styles, date1904: date1904)
                if !text.isEmpty {
                    rows[currentRow, default: [:]][col] = text
                }
            default:
                break
            }
        }

        return SpreadsheetTableBuilder.table(from: rows)
    }

    private func cellText(type: Int, payload p: inout BIFF12Payload, sst: [String],
                          iStyleRef: Int, styles: Styles, date1904: Bool) -> String {
        switch type {
        case Rec.cellIsst:
            let idx = Int(p.u32())
            return sst.indices.contains(idx) ? sst[idx] : ""
        case Rec.cellRk:    return formatNumber(decodeRkNumber(p.u32()), iStyleRef, styles, date1904)
        case Rec.cellReal:  return formatNumber(p.f64(), iStyleRef, styles, date1904)
        case Rec.cellSt:    return p.xlWideString()
        case Rec.cellRString: return p.richStr()
        case Rec.cellBool:  return p.u8() == 0 ? "FALSE" : "TRUE"
        default:            return ""    // cellError, cellBlank
        }
    }

    /// Apply the cell's number format (via its style index) to a numeric value.
    private func formatNumber(_ d: Double, _ iStyleRef: Int, _ styles: Styles, _ date1904: Bool) -> String {
        guard styles.fmtIds.indices.contains(iStyleRef) else { return ExcelNumberFormat.number(d) }
        let id = styles.fmtIds[iStyleRef]
        return ExcelNumberFormat.format(value: d, numFmtId: id, code: styles.custom[id], date1904: date1904)
    }
}
