import Foundation
import Compression

/// Minimal, dependency-free ZIP reader for `.docx` containers.
///
/// A `.docx` is an Open Packaging Conventions ZIP archive of XML parts. We only
/// need random read access to a handful of named entries (`word/document.xml`,
/// `word/styles.xml`, etc.), so this reads the central directory and inflates
/// individual entries on demand using Apple's Compression framework. No Zip64,
/// encryption, or streaming — none of which appear in real Word documents.
public struct ZipReader {
    public enum ZipError: Error, CustomStringConvertible {
        case notAZipArchive
        case truncated
        case unsupportedCompression(UInt16)
        case decompressionFailed
        case entryTooLarge(String, Int)
        case archiveTooLarge(Int)
        case packageTooLarge(Int)

        public var description: String {
            switch self {
            case .notAZipArchive: return "Not a ZIP archive (no end-of-central-directory record)"
            case .truncated: return "ZIP archive is truncated or corrupt"
            case .unsupportedCompression(let m): return "Unsupported ZIP compression method \(m)"
            case .decompressionFailed: return "DEFLATE decompression failed"
            case .entryTooLarge(let path, let size): return "ZIP entry \(path) exceeds size limit (\(size) bytes)"
            case .archiveTooLarge(let size): return "ZIP archive exceeds size limit (\(size) bytes)"
            case .packageTooLarge(let size): return "ZIP package uncompressed size exceeds limit (\(size) bytes)"
            }
        }
    }

    private struct CentralEntry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private var directory: [String: CentralEntry] = [:]

    public init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    public init(data: Data) throws {
        guard data.count <= ParserLimits.maxZipArchiveBytes else {
            throw ZipError.archiveTooLarge(data.count)
        }
        self.data = Data(data)
        try parseCentralDirectory()
    }

    /// All entry paths in the archive.
    public var entryNames: [String] { Array(directory.keys) }

    /// Returns the decompressed bytes for an entry, or nil if absent.
    public func data(for path: String) throws -> Data? {
        guard let entry = directory[path] else { return nil }
        return try read(entry)
    }

    // MARK: - Little-endian readers

    private func u16(_ offset: Int) throws -> UInt16 {
        guard offset + 2 <= data.count else { throw ZipError.truncated }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func u32(_ offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ZipError.truncated }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    // MARK: - Central directory

    private static let eocdSignature: UInt32 = 0x0605_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let localSignature: UInt32 = 0x0403_4b50

    private mutating func parseCentralDirectory() throws {
        // Locate the End Of Central Directory record by scanning backwards. The
        // EOCD is 22 bytes plus an optional trailing comment (max 65535 bytes).
        let minEOCD = 22
        guard data.count >= minEOCD else { throw ZipError.notAZipArchive }
        let searchLimit = max(0, data.count - minEOCD - 0xFFFF)
        var eocd = -1
        var i = data.count - minEOCD
        while i >= searchLimit {
            if (try? u32(i)) == Self.eocdSignature { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZipArchive }

        let entryCount = Int(try u16(eocd + 10))
        var offset = Int(try u32(eocd + 16)) // central directory start
        var declaredTotal = 0

        for _ in 0..<entryCount {
            guard (try u32(offset)) == Self.centralSignature else { throw ZipError.truncated }
            let method = try u16(offset + 10)
            let compressedSize = Int(try u32(offset + 20))
            let uncompressedSize = Int(try u32(offset + 24))
            let nameLen = Int(try u16(offset + 28))
            let extraLen = Int(try u16(offset + 30))
            let commentLen = Int(try u16(offset + 32))
            let localOffset = Int(try u32(offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLen <= data.count else { throw ZipError.truncated }
            let name = String(decoding: data[nameStart..<nameStart + nameLen], as: UTF8.self)
            guard uncompressedSize <= ParserLimits.maxZipPartUncompressedBytes else {
                throw ZipError.entryTooLarge(name, uncompressedSize)
            }
            guard declaredTotal <= ParserLimits.maxZipPackageUncompressedBytes - uncompressedSize else {
                throw ZipError.packageTooLarge(declaredTotal + uncompressedSize)
            }
            declaredTotal += uncompressedSize

            directory[name] = CentralEntry(
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            )
            offset = nameStart + nameLen + extraLen + commentLen
        }
    }

    // MARK: - Entry extraction

    private func read(_ entry: CentralEntry) throws -> Data {
        let lh = entry.localHeaderOffset
        guard (try u32(lh)) == Self.localSignature else { throw ZipError.truncated }
        // The local header repeats name/extra lengths; they can differ from the
        // central directory, so the data offset must be computed from the LFH.
        let nameLen = Int(try u16(lh + 26))
        let extraLen = Int(try u16(lh + 28))
        let dataStart = lh + 30 + nameLen + extraLen
        guard dataStart + entry.compressedSize <= data.count else { throw ZipError.truncated }
        guard entry.uncompressedSize <= ParserLimits.maxZipPartUncompressedBytes else {
            throw ZipError.entryTooLarge("<unknown>", entry.uncompressedSize)
        }

        switch entry.method {
        case 0: // stored
            guard entry.compressedSize == entry.uncompressedSize else { throw ZipError.truncated }
            return Data(data[dataStart..<dataStart + entry.compressedSize])
        case 8: // DEFLATE
            return try inflate(at: dataStart, compressedSize: entry.compressedSize,
                               expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    /// Inflates a raw DEFLATE stream (ZIP method 8) via libcompression.
    /// `COMPRESSION_ZLIB` decodes a headerless DEFLATE stream per RFC 1951,
    /// which is exactly what a ZIP entry stores.
    private func inflate(at start: Int, compressedSize: Int, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        guard expectedSize <= ParserLimits.maxZipPartUncompressedBytes else {
            throw ZipError.entryTooLarge("<unknown>", expectedSize)
        }
        var dst = [UInt8](repeating: 0, count: expectedSize)
        let written = data.withUnsafeBytes { raw -> Int in
            let src = raw.bindMemory(to: UInt8.self)
            guard let base = src.baseAddress else { return 0 }
            return dst.withUnsafeMutableBufferPointer { dstBuf in
                compression_decode_buffer(
                    dstBuf.baseAddress!, expectedSize,
                    base + start, compressedSize,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipError.decompressionFailed }
        return Data(dst)
    }
}
