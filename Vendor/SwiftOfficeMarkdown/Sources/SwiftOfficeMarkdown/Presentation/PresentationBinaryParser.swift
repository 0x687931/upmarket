import Foundation

/// Parses a legacy `.ppt` (PowerPoint 97–2003 binary) into a `MarkdownDoc`.
///
/// Implemented from [MS-PPT]: the `PowerPoint Document` stream (from the OLE2
/// container) is a tree of records. Each has an 8-byte header — `recVer`
/// (4 bits) + `recInstance` (12 bits), `recType` (2 bytes), `recLen` (4 bytes);
/// `recVer == 0xF` marks a container whose body is child records. Slide text
/// lives in `TextCharsAtom` (UTF-16) / `TextBytesAtom` (compressed) atoms inside
/// `Slide` containers.
struct PresentationBinaryParser {
    private let compoundFile: CompoundFile
    init(compoundFile: CompoundFile) { self.compoundFile = compoundFile }

    private enum RT {
        static let slide = 0x03EE
        static let textCharsAtom = 0x0FA0
        static let textBytesAtom = 0x0FA8
    }

    func parse() -> MarkdownDoc {
        guard let data = compoundFile.stream(named: "PowerPoint Document") else {
            return MarkdownDoc(blocks: [])
        }
        let bytes = [UInt8](data)
        var slides: [[String]] = []
        var loose: [String] = []

        func walk(_ start: Int, _ end: Int, depth: Int, into bucket: inout [String]) {
            guard depth <= ParserLimits.maxPowerPointRecordDepth else { return }
            var pos = start
            while pos + 8 <= end {
                let verInstance = u16(bytes, pos)
                let recType = u16(bytes, pos + 2)
                let recLen = Int(u32(bytes, pos + 4))
                let dataStart = pos + 8
                guard recLen >= 0, recLen <= end - dataStart else { break }
                let dataEnd = dataStart + recLen

                if recType == RT.slide {                         // start a new slide
                    var slideText: [String] = []
                    walk(dataStart, dataEnd, depth: depth + 1, into: &slideText)
                    slides.append(slideText)
                } else if (verInstance & 0x0F) == 0x0F {         // container → recurse
                    walk(dataStart, dataEnd, depth: depth + 1, into: &bucket)
                } else if recType == RT.textCharsAtom {
                    bucket.append(decodeUTF16(bytes, dataStart, recLen))
                } else if recType == RT.textBytesAtom {
                    bucket.append(decodeCompressed(bytes, dataStart, recLen))
                }
                pos = dataStart + recLen
            }
        }
        walk(0, bytes.count, depth: 0, into: &loose)

        // Prefer per-slide text; fall back to any loose text atoms (e.g. outline).
        var blocks: [Block] = []
        let groups = slides.contains(where: { !$0.isEmpty }) ? slides : [loose]
        var slideNumber = 0
        for group in groups {
            let lines = group.flatMap(paragraphLines)
            guard !lines.isEmpty else { continue }
            slideNumber += 1
            blocks.append(.paragraph(Paragraph(text: "Slide \(slideNumber)", headingLevel: 2)))
            for line in lines {
                blocks.append(.paragraph(Paragraph(list: ListInfo(level: 0, ordered: false, numId: "ppt"),
                                                   inlines: [.text(Run(text: line))])))
            }
        }
        return MarkdownDoc(blocks: blocks)
    }

    /// PPT paragraphs are separated by CR (0x0D); vertical tab (0x0B) is a soft
    /// line break. Split into trimmed, non-empty lines.
    private func paragraphLines(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\r" || $0 == "\u{0B}" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func decodeUTF16(_ b: [UInt8], _ start: Int, _ len: Int) -> String {
        let count = len / 2
        guard count > 0, start + count * 2 <= b.count else { return "" }
        var units = [UInt16](); units.reserveCapacity(count)
        for i in 0..<count { units.append(UInt16(b[start + i * 2]) | UInt16(b[start + i * 2 + 1]) << 8) }
        return String(decoding: units, as: UTF16.self)
    }

    /// TextBytesAtom: each byte is the low byte of a UTF-16 code unit (high 0x00).
    private func decodeCompressed(_ b: [UInt8], _ start: Int, _ len: Int) -> String {
        guard len > 0, start + len <= b.count else { return "" }
        var units = [UInt16](); units.reserveCapacity(len)
        for i in 0..<len { units.append(UInt16(b[start + i])) }
        return String(decoding: units, as: UTF16.self)
    }

    private func u16(_ b: [UInt8], _ o: Int) -> Int {
        o + 2 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0
    }
    private func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}
