import Foundation

/// Reader for the BIFF12 record stream used by `.xlsb` parts.
///
/// Per [MS-XLSB] §2.1.4 each record is: a **record type** (1–2 bytes; two bytes
/// iff the low byte's high bit is set, value = `(b1&0x7F) | ((b2&0x7F)<<7)`),
/// then a **record size** (1–4 byte LEB128-style varint, 7 bits/byte, low byte
/// first), then `size` bytes of payload. All reads are bounds-checked so a
/// truncated/garbage stream stops cleanly rather than crashing.
struct BIFF12Reader {
    private let bytes: [UInt8]
    private var pos = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    /// Next `(recordType, payload)`, or nil at end / on truncation.
    mutating func next() -> (type: Int, payload: ArraySlice<UInt8>)? {
        guard pos < bytes.count else { return nil }
        let type = readType()
        guard let size = readSize(), pos + size <= bytes.count else { return nil }
        let payload = bytes[pos..<pos + size]
        pos += size
        return (type, payload)
    }

    private mutating func readType() -> Int {
        let b1 = Int(bytes[pos]); pos += 1
        if b1 & 0x80 == 0 { return b1 }
        guard pos < bytes.count else { return b1 }
        let b2 = Int(bytes[pos]); pos += 1
        return (b1 & 0x7F) | ((b2 & 0x7F) << 7)
    }

    private mutating func readSize() -> Int? {
        var size = 0, shift = 0
        for _ in 0..<4 {
            guard pos < bytes.count else { return nil }
            let b = Int(bytes[pos]); pos += 1
            size |= (b & 0x7F) << shift
            if b & 0x80 == 0 { return size }
            shift += 7
        }
        return size
    }
}

/// Little-endian cursor over a BIFF12 record payload, with the field readers the
/// spreadsheet parser needs (`XLWideString`, `RichStr`, etc.).
struct BIFF12Payload {
    private let bytes: ArraySlice<UInt8>
    private var pos: ArraySlice<UInt8>.Index

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        self.pos = bytes.startIndex
    }

    init(_ bytes: [UInt8]) {
        self.init(bytes[...])
    }

    mutating func skip(_ n: Int) { pos = min(pos + n, bytes.endIndex) }

    mutating func u8() -> UInt8 {
        guard pos < bytes.endIndex else { return 0 }
        defer { pos += 1 }
        return bytes[pos]
    }

    mutating func u16() -> Int {
        guard pos + 2 <= bytes.endIndex else { pos = bytes.endIndex; return 0 }
        let v = Int(bytes[pos]) | Int(bytes[pos + 1]) << 8
        pos += 2
        return v
    }

    mutating func u32() -> UInt32 {
        guard pos + 4 <= bytes.endIndex else { pos = bytes.endIndex; return 0 }
        let v = UInt32(bytes[pos]) | UInt32(bytes[pos + 1]) << 8
            | UInt32(bytes[pos + 2]) << 16 | UInt32(bytes[pos + 3]) << 24
        pos += 4
        return v
    }

    mutating func f64() -> Double {
        guard pos + 8 <= bytes.endIndex else { pos = bytes.endIndex; return 0 }
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(bytes[pos + i]) << (8 * i) }
        pos += 8
        return Double(bitPattern: bits)
    }

    /// `XLWideString` ([MS-XLSB] §2.5.169): u32 character count + UTF-16LE chars.
    mutating func xlWideString() -> String {
        let cch = Int(u32())
        let byteCount = cch * 2
        guard cch >= 0, cch <= ParserLimits.maxSharedStringLength,
              pos + byteCount <= bytes.endIndex else { pos = bytes.endIndex; return "" }
        var units = [UInt16](); units.reserveCapacity(cch)
        var i = pos
        for _ in 0..<cch { units.append(UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8); i += 2 }
        pos += byteCount
        return String(decoding: units, as: UTF16.self)
    }

    /// `XLNullableWideString` / `RelID`: a u32 of 0xFFFFFFFF means null.
    mutating func xlNullableWideString() -> String? {
        guard pos + 4 <= bytes.endIndex else { return nil }
        let cch = UInt32(bytes[pos]) | UInt32(bytes[pos + 1]) << 8
            | UInt32(bytes[pos + 2]) << 16 | UInt32(bytes[pos + 3]) << 24
        if cch == 0xFFFF_FFFF { pos += 4; return nil }
        return xlWideString()
    }

    /// `RichStr` ([MS-XLSB] §2.5.122): a flags byte then the `str` XLWideString.
    /// Rich-run and phonetic data follow but are not needed for text extraction.
    mutating func richStr() -> String {
        _ = u8()
        return xlWideString()
    }
}

/// Decode an `RkNumber` ([MS-XLSB] §2.5.123): bit 0 = ×1/100, bit 1 = int vs
/// double, top 30 bits = the value (high bits of an IEEE-754 double, or a
/// signed 30-bit integer).
func decodeRkNumber(_ rk: UInt32) -> Double {
    let fx100 = (rk & 0x1) != 0
    let fInt = (rk & 0x2) != 0
    let value: Double
    if fInt {
        value = Double(Int32(bitPattern: rk) >> 2)               // signed 30-bit
    } else {
        value = Double(bitPattern: UInt64(rk & 0xFFFF_FFFC) << 32)
    }
    return fx100 ? value / 100 : value
}
