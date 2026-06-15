import Foundation

/// An Open Packaging Conventions container — the ZIP-of-XML-parts structure
/// shared by every OOXML format (.docx/.xlsx/.pptx). Provides part access,
/// XML parsing, and relationship resolution so each format parser doesn't
/// re-implement the plumbing.
public struct OPCPackage {
    public enum OPCError: Error, CustomStringConvertible {
        case missingPart(String)
        case badXML(String)
        case unsafeXML(String)
        public var description: String {
            switch self {
            case .missingPart(let p): return "Package has no part: \(p)"
            case .badXML(let d): return "Malformed XML: \(d)"
            case .unsafeXML(let d): return "Unsafe XML: \(d)"
            }
        }
    }

    private let zip: ZipReader

    public init(url: URL) throws { zip = try ZipReader(url: url) }
    public init(data: Data) throws { zip = try ZipReader(data: data) }

    public var partNames: [String] { zip.entryNames }

    /// Raw bytes of a part, or nil if absent.
    public func part(_ path: String) throws -> Data? { try zip.data(for: path) }

    /// Root element of a part parsed as XML, or nil if the part is absent.
    public func xmlRoot(_ path: String) throws -> XMLElement? {
        guard let data = try zip.data(for: path) else { return nil }
        guard !Self.containsDOCTYPE(data) else { throw OPCError.unsafeXML("\(path): DOCTYPE is not allowed") }
        do { return try XMLDocument(data: data, options: []).rootElement() }
        catch { throw OPCError.badXML("\(path): \(error.localizedDescription)") }
    }

    private static func containsDOCTYPE(_ data: Data) -> Bool {
        let needle = Array("<!DOCTYPE".utf8)
        guard data.count >= needle.count else { return false }
        let bytes = data
        for start in 0...(bytes.count - needle.count) {
            var matched = true
            for i in 0..<needle.count {
                let b = bytes[start + i]
                let n = needle[i]
                let folded = (b >= 65 && b <= 90) ? b + 32 : b
                let target = (n >= 65 && n <= 90) ? n + 32 : n
                if folded != target { matched = false; break }
            }
            if matched { return true }
        }
        return false
    }

    /// Resolve the relationships for a part. For `word/document.xml` this reads
    /// `word/_rels/document.xml.rels` and returns a map of relationship id ->
    /// target. Targets are returned verbatim (relative to the part's folder).
    public func relationships(forPart partPath: String) throws -> [String: String] {
        let dir = (partPath as NSString).deletingLastPathComponent
        let file = (partPath as NSString).lastPathComponent
        let relsPath = dir.isEmpty ? "_rels/\(file).rels" : "\(dir)/_rels/\(file).rels"
        guard let root = try xmlRoot(relsPath) else { return [:] }
        var map: [String: String] = [:]
        for rel in root.childElements("Relationship") {
            if let id = rel.attr("Id"), let target = rel.attr("Target") {
                map[id] = target
            }
        }
        return map
    }

    /// Resolve a target that is relative to a part's folder into a full part
    /// path (e.g. base "xl/workbook.xml" + target "worksheets/sheet1.xml" ->
    /// "xl/worksheets/sheet1.xml"). Absolute targets ("/xl/…") are normalised.
    public func resolve(target: String, relativeTo basePart: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        let baseDir = (basePart as NSString).deletingLastPathComponent
        let joined = baseDir.isEmpty ? target : "\(baseDir)/\(target)"
        return (joined as NSString).standardizingPath
    }
}
