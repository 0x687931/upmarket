import Foundation

/// Parses a legacy `.xls` (BIFF8) workbook into a `MarkdownDoc` — same output as
/// the modern spreadsheet parsers. Implemented from [MS-XLS]: the `Workbook`
/// stream (extracted from the OLE2 container by `CompoundFile`) is a sequence of
/// `sid(2) + size(2) + data` records. `BoundSheet8` lists sheets (+ the stream
/// offset of each sheet's BOF), `SST` holds the shared strings, and per-sheet
/// cell records carry the values. RK numbers share BIFF12's `decodeRkNumber`.
struct LegacySpreadsheetParser {
    private let compoundFile: CompoundFile
    init(compoundFile: CompoundFile) { self.compoundFile = compoundFile }

    /// BIFF8 record sids ([MS-XLS] §2.3).
    private enum Sid {
        static let eof = 0x000A, boundSheet8 = 0x0085, sst = 0x00FC, continueR = 0x003C
        static let labelSst = 0x00FD, rk = 0x027E, mulRk = 0x00BD
        static let number = 0x0203, label = 0x0204
        static let xf = 0x00E0, format = 0x041E      // styles (number formats)
        static let date1904 = 0x0022
    }

    private struct Record { let sid: Int; let offset: Int; let data: ArraySlice<UInt8> }
    private struct Styles { var fmtIds: [Int] = []; var custom: [Int: String] = [:] }

    func parse() -> MarkdownDoc {
        guard let data = compoundFile.stream(named: "Workbook") ?? compoundFile.stream(named: "Book") else {
            return MarkdownDoc(blocks: [])
        }
        let bytes = [UInt8](data)
        let records = Self.readRecords(bytes)

        let sst = sharedStrings(records)
        let styles = buildStyles(records)
        let date1904 = uses1904Dates(records)
        var blocks: [Block] = []
        for sheet in boundSheets(records) {
            blocks.append(.paragraph(Paragraph(text: sheet.name, headingLevel: 2)))
            if let table = sheetTable(records: records, startOffset: sheet.bofOffset, sst: sst,
                                      styles: styles, date1904: date1904) {
                blocks.append(.table(table))
            }
        }
        return MarkdownDoc(blocks: blocks)
    }

    /// XF records (in order) give each cell's number-format id; FORMAT records
    /// supply custom format strings.
    private func buildStyles(_ records: [Record]) -> Styles {
        var styles = Styles()
        for rec in records {
            switch rec.sid {
            case Sid.format:
                var c = ByteReader(rec.data)
                let ifmt = c.u16()
                styles.custom[ifmt] = c.xlUnicodeString()
            case Sid.xf:
                var c = ByteReader(rec.data)
                c.skip(2)                        // ifnt
                styles.fmtIds.append(c.u16())    // ifmt
            default:
                break
            }
        }
        return styles
    }

    // MARK: - Record framing

    private static func readRecords(_ b: [UInt8]) -> [Record] {
        var recs: [Record] = []
        var pos = 0
        while pos + 4 <= b.count {
            let sid = Int(b[pos]) | Int(b[pos + 1]) << 8
            let size = Int(b[pos + 2]) | Int(b[pos + 3]) << 8
            guard pos + 4 + size <= b.count else { break }
            recs.append(Record(sid: sid, offset: pos, data: b[pos + 4..<pos + 4 + size]))
            pos += 4 + size
        }
        return recs
    }

    private func uses1904Dates(_ records: [Record]) -> Bool {
        guard let rec = records.first(where: { $0.sid == Sid.date1904 }) else { return false }
        var c = ByteReader(rec.data)
        return c.u16() != 0
    }

    // MARK: - Sheets

    private struct SheetRef { let name: String; let bofOffset: Int }

    private func boundSheets(_ records: [Record]) -> [SheetRef] {
        records.filter { $0.sid == Sid.boundSheet8 }.compactMap { rec in
            var c = ByteReader(rec.data)
            let lbPlyPos = Int(c.u32())   // stream offset of the sheet's BOF
            c.skip(2)                     // grbit (hidden state + sheet type)
            let name = c.shortString()    // ShortXLUnicodeString
            return name.isEmpty ? nil : SheetRef(name: name, bofOffset: lbPlyPos)
        }
    }

    // MARK: - Shared strings (SST + Continue)

    private func sharedStrings(_ records: [Record]) -> [String] {
        guard let i = records.firstIndex(where: { $0.sid == Sid.sst }) else { return [] }
        // chunk 0 = SST data after the 8-byte cstTotal/cstUnique header; then any
        // immediately-following Continue records extend the string data.
        let sstData = records[i].data
        guard sstData.count >= 8 else { return [] }
        var header = ByteReader(sstData)
        header.skip(4) // cstTotal
        let cstUnique = Int(header.u32())
        var chunks: [ArraySlice<UInt8>] = [sstData.dropFirst(8)]
        var j = i + 1
        while j < records.count, records[j].sid == Sid.continueR { chunks.append(records[j].data); j += 1 }

        let sst = SSTStream(chunks)
        var result: [String] = []; result.reserveCapacity(cstUnique)
        var totalBytes = 0
        for _ in 0..<cstUnique {
            guard result.count < ParserLimits.maxSharedStrings else { break }
            if sst.done { break }
            let text = sst.readRichExtendedString()
            totalBytes += text.utf8.count
            guard text.utf8.count <= ParserLimits.maxSharedStringLength,
                  totalBytes <= ParserLimits.maxSharedStringBytes else { break }
            result.append(text)
        }
        return result
    }

    // MARK: - Worksheet → table

    private func sheetTable(records: [Record], startOffset: Int, sst: [String],
                            styles: Styles, date1904: Bool) -> Table? {
        guard let start = records.firstIndex(where: { $0.offset == startOffset }) else { return nil }
        var rows: [Int: [Int: String]] = [:]

        func put(_ r: Int, _ col: Int, _ text: String) {
            guard !text.isEmpty, r >= 0, r < ParserLimits.excelMaxRows,
                  col >= 0, col < ParserLimits.excelMaxColumns,
                  rows.count < ParserLimits.maxMarkdownTableRows else { return }
            rows[r, default: [:]][col] = text
        }

        var k = start + 1   // skip the sheet BOF
        while k < records.count {
            let rec = records[k]; k += 1
            if rec.sid == Sid.eof { break }
            var c = ByteReader(rec.data)
            switch rec.sid {
            case Sid.labelSst:
                let r = Int(c.u16()), col = Int(c.u16()); c.skip(2)
                let isst = Int(c.u32())
                put(r, col, sst.indices.contains(isst) ? sst[isst] : "")
            case Sid.rk:
                let r = Int(c.u16()), col = Int(c.u16()), ixfe = c.u16()
                put(r, col, formatNumber(decodeRkNumber(c.u32()), ixfe, styles, date1904))
            case Sid.number:
                let r = Int(c.u16()), col = Int(c.u16()), ixfe = c.u16()
                put(r, col, formatNumber(c.f64(), ixfe, styles, date1904))
            case Sid.label:
                let r = Int(c.u16()), col = Int(c.u16()); c.skip(2)
                put(r, col, c.xlUnicodeString())
            case Sid.mulRk:
                let r = Int(c.u16()), colFirst = Int(c.u16())
                let n = (rec.data.count - 6) / 6
                for idx in 0..<max(0, n) {
                    let ixfe = c.u16()
                    put(r, colFirst + idx, formatNumber(decodeRkNumber(c.u32()), ixfe, styles, date1904))
                }
            default:
                break
            }
        }

        return SpreadsheetTableBuilder.table(from: rows)
    }

    /// Apply the cell's number format (via its XF index) to a numeric value.
    private func formatNumber(_ d: Double, _ ixfe: Int, _ styles: Styles, _ date1904: Bool) -> String {
        guard styles.fmtIds.indices.contains(ixfe) else { return ExcelNumberFormat.number(d) }
        let id = styles.fmtIds[ixfe]
        return ExcelNumberFormat.format(value: d, numFmtId: id, code: styles.custom[id], date1904: date1904)
    }
}

// MARK: - Contiguous payload reader

/// Little-endian cursor over one BIFF8 record payload.
private struct ByteReader {
    private let b: ArraySlice<UInt8>
    private var p: ArraySlice<UInt8>.Index
    init(_ bytes: ArraySlice<UInt8>) {
        b = bytes
        p = bytes.startIndex
    }

    mutating func skip(_ n: Int) { p = min(p + n, b.endIndex) }
    mutating func u8() -> Int { guard p < b.endIndex else { return 0 }; defer { p += 1 }; return Int(b[p]) }
    mutating func u16() -> Int { let a = u8(); return a | (u8() << 8) }
    mutating func u32() -> UInt32 { let a = UInt32(u16()); return a | (UInt32(u16()) << 16) }
    mutating func f64() -> Double {
        guard p + 8 <= b.endIndex else { p = b.endIndex; return 0 }
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(b[p + i]) << (8 * i) }
        p += 8
        return Double(bitPattern: bits)
    }

    /// ShortXLUnicodeString: 1-byte char count + 1-byte flags + chars.
    mutating func shortString() -> String { readChars(count: u8(), flags: u8()) }
    /// XLUnicodeString: 2-byte char count + 1-byte flags + chars.
    mutating func xlUnicodeString() -> String { readChars(count: u16(), flags: u8()) }

    private mutating func readChars(count: Int, flags: Int) -> String {
        let highByte = (flags & 0x01) != 0
        var units = [UInt16](); units.reserveCapacity(count)
        for _ in 0..<count {
            if highByte { units.append(UInt16(u8()) | UInt16(u8()) << 8) }
            else { units.append(UInt16(u8())) }
        }
        return String(decoding: units, as: UTF16.self)
    }
}

// MARK: - SST string reader (handles Continue-boundary splits)

/// Reads `XLUnicodeRichExtendedString`s from the SST + Continue chunk list.
/// Per [MS-XLS], a string's `rgb` may break across a Continue boundary, and the
/// continuation begins with a fresh `fHighByte` flag byte.
private final class SSTStream {
    private let chunks: [ArraySlice<UInt8>]
    private var ci = 0
    private var p: ArraySlice<UInt8>.Index = 0

    init(_ chunks: [ArraySlice<UInt8>]) {
        self.chunks = chunks
        self.p = chunks.first?.startIndex ?? 0
    }

    var done: Bool { advanceIfNeeded(); return ci >= chunks.count }

    private func advanceIfNeeded() {
        while ci < chunks.count, p >= chunks[ci].endIndex {
            ci += 1
            p = ci < chunks.count ? chunks[ci].startIndex : 0
        }
    }

    private func u8() -> Int {
        advanceIfNeeded()
        guard ci < chunks.count else { return 0 }
        defer { p += 1 }
        return Int(chunks[ci][p])
    }
    private func u16() -> Int { let a = u8(); return a | (u8() << 8) }
    private func u32() -> Int { let a = u16(); return a | (u16() << 16) }
    private func skip(_ n: Int) {
        var k = n
        while k > 0, ci < chunks.count {
            advanceIfNeeded()
            guard ci < chunks.count else { return }
            let take = min(chunks[ci].endIndex - p, k)
            p += take; k -= take
        }
    }

    func readRichExtendedString() -> String {
        let cch = u16()
        let flags = u8()
        var highByte = (flags & 0x01) != 0
        let ext = (flags & 0x04) != 0
        let rich = (flags & 0x08) != 0
        let cRun = rich ? u16() : 0
        let cbExtRst = ext ? u32() : 0

        var units = [UInt16](); units.reserveCapacity(cch)
        var i = 0
        while i < cch {
            advanceIfNeeded()
            guard ci < chunks.count else { break }
            // A Continue break mid-rgb: the new chunk starts with a fresh flag byte.
            if p == 0, ci > 0 { highByte = (Int(chunks[ci][p]) & 0x01) != 0; p += 1; advanceIfNeeded() }
            if highByte { units.append(UInt16(u8()) | UInt16(u8()) << 8) }
            else { units.append(UInt16(u8())) }
            i += 1
        }
        skip(cRun * 4)      // rgRun (formatting runs)
        skip(cbExtRst)      // ExtRst (phonetic data)
        return String(decoding: units, as: UTF16.self)
    }
}
