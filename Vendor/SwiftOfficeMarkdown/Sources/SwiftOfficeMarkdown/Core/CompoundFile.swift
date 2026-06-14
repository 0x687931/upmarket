import Foundation

/// Reader for the OLE2 / Compound File Binary container ([MS-CFB]) — the
/// "mini-filesystem" that legacy `.xls`/`.ppt`/`.doc` are stored in. Parses the
/// header, FAT (via the header DIFAT + DIFAT chain), directory, and mini-stream,
/// and exposes named streams. All reads are bounds-checked.
public struct CompoundFile {
    private static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    private static let maxRegSect: UInt32 = 0xFFFF_FFFA   // ENDOFCHAIN (0xFFFFFFFE) and sentinels exceed this

    struct DirEntry { let name: String; let type: UInt8; let start: UInt32; let size: Int }

    private let bytes: Data
    private let sectorSize: Int
    private let miniCutoff: Int
    private var fat: [UInt32] = []
    private var miniFat: [UInt32] = []
    private var entries: [DirEntry] = []
    private var miniStream = Data()

    /// Returns nil if the data is not a compound file.
    public init?(_ data: Data) {
        let normalized = Data(data)
        guard normalized.count >= 512, normalized.prefix(8).elementsEqual(Self.signature) else { return nil }
        self.bytes = normalized
        let major = Self.u16(normalized, 26)
        self.sectorSize = 1 << Int(Self.u16(normalized, 30))
        self.miniCutoff = Int(Self.u32(normalized, 56))
        guard sectorSize == 512 || sectorSize == 4096 else { return nil }
        _ = major

        buildFAT()
        readDirectory()
        buildMiniStream()
    }

    public var streamNames: [String] { entries.filter { $0.type == 2 }.map(\.name) }

    /// Bytes of a stream by (case-insensitive) name, or nil if absent.
    public func stream(named name: String) -> Data? {
        guard let e = entries.first(where: { $0.type == 2 && $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return nil }
        guard e.size <= ParserLimits.maxCompoundStreamBytes else { return nil }
        let raw: Data
        if e.size >= miniCutoff {
            raw = readChain(from: bytes, start: e.start, unit: sectorSize, fat: fat,
                            sectorBased: true, maxBytes: e.size)
        } else {
            raw = readChain(from: miniStream, start: e.start, unit: 64, fat: miniFat,
                            sectorBased: false, maxBytes: e.size)
        }
        return Data(raw.prefix(e.size))
    }

    // MARK: - Header readers

    private static func u16(_ b: Data, _ o: Int) -> UInt16 {
        o + 2 <= b.count ? UInt16(b[o]) | UInt16(b[o + 1]) << 8 : 0
    }
    private static func u32(_ b: Data, _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    /// File offset of regular sector `n` (the 512-byte header precedes sector 0,
    /// and for v4 the header is padded to the 4096-byte sector size).
    private func sectorOffset(_ n: UInt32) -> Int { (Int(n) + 1) * sectorSize }

    // MARK: - FAT

    private mutating func buildFAT() {
        // Collect FAT sector locations: 109 in the header DIFAT, then any DIFAT chain.
        var fatSectors: [UInt32] = []
        for i in 0..<109 {
            let v = Self.u32(bytes, 76 + i * 4)
            if v <= Self.maxRegSect { fatSectors.append(v) }
        }
        var difat = Self.u32(bytes, 68)            // first DIFAT sector
        let numDifat = Self.u32(bytes, 72)
        let perDifat = sectorSize / 4 - 1
        var guardCount = 0
        while difat <= Self.maxRegSect, guardCount <= Int(numDifat) + 1 {
            let off = sectorOffset(difat)
            guard off + sectorSize <= bytes.count else { break }
            for i in 0..<perDifat {
                let v = Self.u32(bytes, off + i * 4)
                if v <= Self.maxRegSect { fatSectors.append(v) }
            }
            difat = Self.u32(bytes, off + perDifat * 4)
            guardCount += 1
        }
        // Concatenate every FAT sector's UInt32 entries.
        let entriesPerSector = sectorSize / 4
        fat.reserveCapacity(fatSectors.count * entriesPerSector)
        for sec in fatSectors {
            let off = sectorOffset(sec)
            guard off + sectorSize <= bytes.count else { continue }
            for i in 0..<entriesPerSector { fat.append(Self.u32(bytes, off + i * 4)) }
        }
    }

    /// Follow a sector chain, concatenating each unit's bytes.
    private func readChain(from store: Data, start: UInt32, unit: Int, fat: [UInt32],
                           sectorBased: Bool, maxBytes: Int? = nil) -> Data {
        var result = Data()
        var sec = start
        var steps = 0
        while sec <= Self.maxRegSect, steps <= fat.count + 1 {
            let off = sectorBased ? sectorOffset(sec) : Int(sec) * unit
            guard off >= 0, off + unit <= store.count else { break }
            let remaining = maxBytes.map { max(0, $0 - result.count) } ?? unit
            guard remaining > 0 else { break }
            let take = min(unit, remaining)
            result.append(contentsOf: store[off..<off + take])
            guard Int(sec) < fat.count else { break }
            sec = fat[Int(sec)]
            steps += 1
        }
        return result
    }

    // MARK: - Directory

    private mutating func readDirectory() {
        let dirStart = Self.u32(bytes, 48)
        let dir = readChain(from: bytes, start: dirStart, unit: sectorSize, fat: fat, sectorBased: true)
        let count = dir.count / 128
        for i in 0..<count {
            let base = i * 128
            let type = dir[base + 66]
            guard type == 1 || type == 2 || type == 5 else { continue }
            let nameLen = Int(Self.u16(dir, base + 64))
            guard nameLen >= 2, nameLen <= 64, nameLen % 2 == 0,
                  Self.u16(dir, base + nameLen - 2) == 0 else { continue }
            let chars = max(0, (nameLen / 2) - 1)               // exclude null terminator
            var units = [UInt16](); units.reserveCapacity(chars)
            var j = base
            for _ in 0..<chars { units.append(Self.u16(dir, j)); j += 2 }
            let name = String(decoding: units, as: UTF16.self)
            let start = Self.u32(dir, base + 116)
            let size = Int(Self.u32(dir, base + 120))           // low 32 bits suffice for our use
            entries.append(DirEntry(name: name, type: type, start: start, size: size))
        }
    }

    private mutating func buildMiniStream() {
        let miniFatStart = Self.u32(bytes, 60)
        let rawMiniFat = readChain(from: bytes, start: miniFatStart, unit: sectorSize, fat: fat, sectorBased: true)
        for i in 0..<(rawMiniFat.count / 4) { miniFat.append(Self.u32(rawMiniFat, i * 4)) }
        if let root = entries.first(where: { $0.type == 5 }) {   // Root Entry holds the mini stream
            guard root.size <= ParserLimits.maxCompoundStreamBytes else { return }
            let full = readChain(from: bytes, start: root.start, unit: sectorSize, fat: fat,
                                 sectorBased: true, maxBytes: root.size)
            miniStream = Data(full.prefix(root.size))
        }
    }
}
