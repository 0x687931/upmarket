import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Public entry point: convert an Office document to Markdown.
///
/// Routing is by **package contents**, not file extension — so every OOXML
/// variant (macro-enabled `.docm`/`.xlsm`/`.pptm`, templates `.dotx`/`.xltx`/
/// `.potx`, slideshows `.ppsx`, …) is handled by the matching parser, because
/// they all carry the same main part. Macros (`vbaProject.bin`) are ignored and
/// never executed. Legacy binary `.doc` is handled by macOS's text importers;
/// binary `.xls`/`.ppt`/`.xlsb` are rejected with a specific message.
public enum OfficeToMarkdown {
    public enum ConvertError: Error, CustomStringConvertible {
        case unsupportedFormat(String)
        case legacyBinaryUnsupported(format: String, modern: String)
        case legacyDocUnavailable

        public var description: String {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported format: .\(ext)"
            case .legacyBinaryUnsupported(let format, let modern):
                return "Legacy binary .\(format) (Office 97–2003) isn't supported — re-save as .\(modern)."
            case .legacyDocUnavailable:
                return "Could not read legacy .doc file"
            }
        }
    }

    /// Convert the file at `url` to Markdown. Detects the format from the
    /// package contents; falls back to legacy-binary handling when the file is
    /// not an OOXML (ZIP) package.
    public static func convert(fileURL url: URL) throws -> String {
        // Try to open as an OOXML package; only "not a ZIP" falls through to
        // the legacy-binary branch (real parse errors propagate).
        do {
            let package = try OPCPackage(url: url)
            return try renderPackage(package, extension: url.pathExtension.lowercased())
        } catch ZipReader.ZipError.notAZipArchive {
            // Not OOXML — handle the OLE2 binary formats by extension.
        }
        switch url.pathExtension.lowercased() {
        case "doc":
            // Prefer the system importer — it recovers character formatting
            // (bold/italic) and paragraph structure that the native piece-table
            // can't. Fall back to native [MS-DOC] extraction when AppKit is
            // unavailable (e.g. headless) or the importer yields nothing.
            #if canImport(AppKit)
            if let styled = try? convertLegacyDoc(url),
               !styled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return styled
            }
            #endif
            if let data = try? Data(contentsOf: url), let cf = CompoundFile(data),
               let doc = WordBinaryParser(compoundFile: cf).parse() {
                return render { doc }
            }
            return try convertLegacyDoc(url)
        case "xls":
            // Legacy BIFF8 workbook inside an OLE2 compound file.
            guard let data = try? Data(contentsOf: url), let cf = CompoundFile(data) else {
                throw ConvertError.legacyBinaryUnsupported(format: "xls", modern: "xlsx")
            }
            return render { LegacySpreadsheetParser(compoundFile: cf).parse() }
        case "ppt":
            // Legacy PowerPoint binary inside an OLE2 compound file.
            guard let data = try? Data(contentsOf: url), let cf = CompoundFile(data) else {
                throw ConvertError.legacyBinaryUnsupported(format: "ppt", modern: "pptx")
            }
            return render { PresentationBinaryParser(compoundFile: cf).parse() }
        default:
            throw ConvertError.unsupportedFormat(url.pathExtension.lowercased())
        }
    }

    /// Convert raw OOXML bytes already in memory (detected by contents).
    public static func convertData(_ data: Data, extension ext: String = "") throws -> String {
        try renderPackage(try OPCPackage(data: data), extension: ext)
    }

    /// Back-compat alias.
    public static func convertDocxData(_ data: Data) throws -> String {
        try convertData(data, extension: "docx")
    }

    // MARK: - Private

    /// Route an opened package to the right parser by the main part it contains.
    private static func renderPackage(_ package: OPCPackage, extension ext: String) throws -> String {
        let parts = Set(package.partNames)
        if parts.contains("word/document.xml") {
            return try render { var p = WordParser(package: package); return try p.parse() }
        }
        if parts.contains("xl/workbook.xml") {
            return try render { var p = SpreadsheetParser(package: package); return try p.parse() }
        }
        if parts.contains("ppt/presentation.xml") {
            return try render { var p = PresentationParser(package: package); return try p.parse() }
        }
        if parts.contains("xl/workbook.bin") {
            return try render { try SpreadsheetBinaryParser(package: package).parse() }   // .xlsb (BIFF12)
        }
        throw ConvertError.unsupportedFormat(ext.isEmpty ? "ooxml" : ext)
    }

    private static func render(_ build: () throws -> MarkdownDoc) rethrows -> String {
        var serializer = MarkdownSerializer()
        return serializer.serialize(try build())
    }

    /// Legacy `.doc` via Apple's text system — styled text without the full
    /// structural fidelity of the native OOXML path; adequate for a rare format.
    private static func convertLegacyDoc(_ url: URL) throws -> String {
        #if canImport(AppKit)
        let attributed = try NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.docFormat],
            documentAttributes: nil
        )
        return LegacyDocMarkdown.render(attributed)
        #else
        throw ConvertError.legacyDocUnavailable
        #endif
    }
}

#if canImport(AppKit)
/// NSAttributedString → Markdown for legacy `.doc`. Recovers character
/// formatting (bold/italic from font traits) and detects headings by font size
/// relative to the document's body text.
enum LegacyDocMarkdown {
    static func render(_ attributed: NSAttributedString) -> String {
        let full = attributed.string as NSString
        let fullRange = NSRange(location: 0, length: full.length)

        // Collect non-empty paragraphs with their dominant font size.
        var paragraphs: [(range: NSRange, size: Int)] = []
        full.enumerateSubstrings(in: fullRange, options: .byParagraphs) { para, range, _, _ in
            guard let para, !para.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            paragraphs.append((range, Int((font?.pointSize ?? 12).rounded())))
        }

        // Body size = most common; sizes clearly larger map to heading levels.
        var sizeCounts: [Int: Int] = [:]
        for p in paragraphs { sizeCounts[p.size, default: 0] += 1 }
        let bodySize = sizeCounts.max { $0.value < $1.value }?.key ?? 12
        let headingSizes = Set(paragraphs.map(\.size)).filter { $0 > bodySize + 1 }.sorted(by: >)
        let sizeToLevel = Dictionary(uniqueKeysWithValues:
            headingSizes.prefix(3).enumerated().map { ($1, $0 + 1) })

        var blocks: [String] = []
        for p in paragraphs {
            let plain = full.substring(with: p.range).trimmingCharacters(in: .whitespacesAndNewlines)
            // A short, larger-than-body paragraph (≥2 chars, skipping drop-caps)
            // is treated as a heading; otherwise inline-formatted body text.
            if let level = sizeToLevel[p.size], plain.count >= 2, plain.count <= 120 {
                blocks.append(String(repeating: "#", count: level) + " " + plain)
            } else {
                blocks.append(inlineFormatted(attributed, full, p.range))
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    /// Render a paragraph applying bold/italic, coalescing adjacent runs of the
    /// same style (NSAttributedString splits runs finely) and keeping whitespace
    /// outside the emphasis markers.
    private static func inlineFormatted(_ attributed: NSAttributedString, _ full: NSString, _ range: NSRange) -> String {
        var runs: [(text: String, bold: Bool, italic: Bool)] = []
        attributed.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
            let text = full.substring(with: subRange).replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            guard !text.isEmpty else { return }
            let traits = (attrs[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let run = (text, traits.contains(.boldFontMask), traits.contains(.italicFontMask))
            if let last = runs.last, last.bold == run.1, last.italic == run.2 {
                runs[runs.count - 1].text += run.0
            } else {
                runs.append(run)
            }
        }
        return runs.map { emphasise($0.text, bold: $0.bold, italic: $0.italic) }.joined()
    }

    private static func emphasise(_ text: String, bold: Bool, italic: Bool) -> String {
        guard bold || italic else { return text }
        let lead = String(text.prefix { $0 == " " })
        let trail = String(text.reversed().prefix { $0 == " " }.reversed())
        let start = text.index(text.startIndex, offsetBy: lead.count)
        let end = text.index(text.endIndex, offsetBy: -trail.count)
        guard start < end else { return text }            // all whitespace
        let core = String(text[start..<end])
        let marker = bold && italic ? "***" : (bold ? "**" : "*")
        return lead + marker + core + marker + trail
    }
}
#endif
