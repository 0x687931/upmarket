import Foundation

/// Parses a legacy `.doc` (Word 97–2003 binary) into a `MarkdownDoc` via the
/// piece table ([MS-DOC]).
///
/// Algorithm (from [MS-DOC] "Retrieving Text"): read the FIB at offset 0 of the
/// `WordDocument` stream → `base.fWhichTblStm` picks the `0Table`/`1Table`
/// stream → `FibRgFcLcb97.fcClx/lcbClx` locate the `Clx` there → the `Clx`'s
/// `Pcdt` holds a `PlcPcd` (CP array + piece descriptors). Each `Pcd.fc` is an
/// `FcCompressed`: `fCompressed`=0 → 16-bit Unicode at `fc`; `fCompressed`=1 →
/// 8-bit (cp1252) at `fc/2`. The main document is CP `0..ccpText`.
///
/// Returns nil when it can't extract text (complex/encrypted/unexpected FIB), so
/// the caller can fall back to the system text importer.
struct WordBinaryParser {
    private let compoundFile: CompoundFile
    init(compoundFile: CompoundFile) { self.compoundFile = compoundFile }

    func parse() -> MarkdownDoc? {
        guard let wdData = compoundFile.stream(named: "WordDocument") else { return nil }
        let w = [UInt8](wdData)
        guard w.count > 0x1AA, u16(w, 0) == 0xA5EC else { return nil }   // wIdent

        let flags = u16(w, 0x0A)
        let useOneTable = (flags >> 9) & 1 == 1                          // base.fWhichTblStm
        let ccpText = Int(i32(w, 0x4C))                                  // FibRgLw97.ccpText
        let fcClx = Int(u32(w, 0x1A2)), lcbClx = Int(u32(w, 0x1A6))      // FibRgFcLcb97
        guard ccpText > 0 else { return nil }

        guard let tableData = compoundFile.stream(named: useOneTable ? "1Table" : "0Table"),
              fcClx >= 0, lcbClx > 0 else { return nil }
        let t = [UInt8](tableData)
        guard fcClx + lcbClx <= t.count else { return nil }

        guard let plc = pieceTable(Array(t[fcClx..<fcClx + lcbClx])) else { return nil }

        var scalars = String.UnicodeScalarView()
        for i in 0..<plc.pcds.count {
            let cpStart = plc.cps[i], cpEnd = plc.cps[i + 1]
            if cpStart >= ccpText { break }
            let count = min(cpEnd, ccpText) - cpStart
            guard count > 0 else { continue }
            let (fc, compressed) = plc.pcds[i]
            if compressed {
                let off = fc / 2
                guard off >= 0, off + count <= w.count else { continue }
                for k in 0..<count { scalars.append(cp1252(w[off + k])) }
            } else {
                let off = fc
                guard off >= 0, off + count * 2 <= w.count else { continue }
                for k in 0..<count {
                    let u = UInt16(w[off + k * 2]) | UInt16(w[off + k * 2 + 1]) << 8
                    scalars.append(Unicode.Scalar(u) ?? " ")
                }
            }
        }

        let blocks = cleanToBlocks(String(scalars))
        return blocks.isEmpty ? nil : MarkdownDoc(blocks: blocks)
    }

    // MARK: - Piece table (Clx → Pcdt → PlcPcd)

    private struct PieceTable { let cps: [Int]; let pcds: [(fc: Int, compressed: Bool)] }

    private func pieceTable(_ clx: [UInt8]) -> PieceTable? {
        var p = 0
        while p < clx.count {
            switch clx[p] {
            case 0x01:                               // Prc — skip
                guard p + 3 <= clx.count else { return nil }
                let cb = Int(u16(clx, p + 1))
                p += 3 + cb
            case 0x02:                               // Pcdt
                guard p + 5 <= clx.count else { return nil }
                let lcb = Int(u32(clx, p + 1))
                let start = p + 5
                guard lcb >= 4, start + lcb <= clx.count else { return nil }
                let n = (lcb - 4) / 12
                guard n > 0 else { return nil }
                var cps: [Int] = []; cps.reserveCapacity(n + 1)
                for i in 0...n { cps.append(Int(i32(clx, start + i * 4))) }
                let pcdBase = start + 4 * (n + 1)
                var pcds: [(Int, Bool)] = []; pcds.reserveCapacity(n)
                for i in 0..<n {
                    let v = u32(clx, pcdBase + i * 8 + 2)   // Pcd.fc (FcCompressed) after 2-byte flags
                    pcds.append((Int(v & 0x3FFF_FFFF), (v & 0x4000_0000) != 0))
                }
                return PieceTable(cps: cps, pcds: pcds)
            default:
                return nil
            }
        }
        return nil
    }

    // MARK: - Text cleanup

    /// Strip field instructions, normalise control marks, split into paragraphs.
    private func cleanToBlocks(_ text: String) -> [Block] {
        var out = String.UnicodeScalarView()
        var inFieldInstruction = false
        for ch in text.unicodeScalars {
            switch ch.value {
            case 0x13: inFieldInstruction = true            // field begin
            case 0x14: inFieldInstruction = false           // field separator (result follows)
            case 0x15: break                                // field end
            case _ where inFieldInstruction: break          // hide field code
            case 0x0D, 0x07, 0x0B, 0x0C: out.append("\n")   // para / cell / line / page marks
            case 0x09: out.append("\t")
            case 0x1E: out.append("-")                      // non-breaking hyphen
            case 0x00..<0x20, 0x1F: break                   // other control / optional hyphen
            default: out.append(ch)
            }
        }
        return String(out)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { .paragraph(Paragraph(text: $0)) }
    }

    // MARK: - Byte helpers

    private func u16(_ b: [UInt8], _ o: Int) -> Int {
        o + 2 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0
    }
    private func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    private func i32(_ b: [UInt8], _ o: Int) -> Int32 { Int32(bitPattern: u32(b, o)) }

    /// Map a cp1252 byte to a Unicode scalar (only the 0x80–0x9F range differs
    /// from Latin-1; the common punctuation is handled).
    private func cp1252(_ byte: UInt8) -> Unicode.Scalar {
        switch byte {
        case 0x85: return "\u{2026}"; case 0x91: return "\u{2018}"; case 0x92: return "\u{2019}"
        case 0x93: return "\u{201C}"; case 0x94: return "\u{201D}"; case 0x95: return "\u{2022}"
        case 0x96: return "\u{2013}"; case 0x97: return "\u{2014}"
        default: return Unicode.Scalar(byte)
        }
    }
}
