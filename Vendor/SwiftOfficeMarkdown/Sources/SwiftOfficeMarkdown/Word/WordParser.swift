import Foundation

/// Parses the WordprocessingML parts of a `.docx` into a `MarkdownDoc`.
///
/// Clean-room take on mammoth: resolve paragraph *styles* (styles.xml) and
/// *numbering* (numbering.xml) into semantic headings and lists, resolve
/// relationship ids (document.xml.rels) into hyperlink/image targets, and walk
/// the body in document order including tables.
public struct WordParser {
    public enum ParseError: Error, CustomStringConvertible {
        case missingDocument
        public var description: String {
            switch self {
            case .missingDocument: return "Archive has no word/document.xml"
            }
        }
    }

    private let package: OPCPackage

    private var headingLevelByStyleId: [String: Int] = [:]
    private var orderedByNumIdLevel: [String: [Int: Bool]] = [:] // numId -> ilvl -> ordered
    private var relationshipTargets: [String: String] = [:]      // rId -> target

    public init(package: OPCPackage) { self.package = package }

    public mutating func parse() throws -> MarkdownDoc {
        try loadStyles()
        try loadNumbering()
        relationshipTargets = try package.relationships(forPart: "word/document.xml")

        guard let root = try package.xmlRoot("word/document.xml"),
              let body = root.firstChild("body") else {
            throw ParseError.missingDocument
        }

        var blocks: [Block] = []
        for case let el as XMLElement in body.children ?? [] {
            switch el.localName {
            case "p":   blocks.append(.paragraph(parseParagraph(el)))
            case "tbl": blocks.append(.table(parseTable(el, depth: 0)))
            default:    break
            }
        }
        return MarkdownDoc(blocks: blocks)
    }

    // MARK: - Schema vocabulary (single source of truth; enforced by SchemaContractTests)

    /// Run-property elements (`EG_RPrBase` in wml.xsd) translated to Markdown.
    static let handledRunProperties: Set<String> = [
        "b", "bCs", "i", "iCs", "strike", "dstrike", "vertAlign",
    ]

    /// Run-property elements deliberately ignored: visual-only, not
    /// representable in Markdown, or hidden-text flags whose text we still emit.
    /// `handledRunProperties ∪ ignoredRunProperties` must cover `EG_RPrBase`.
    static let ignoredRunProperties: Set<String> = [
        "rStyle", "rFonts", "caps", "smallCaps", "outline", "shadow", "emboss",
        "imprint", "noProof", "snapToGrid", "color", "spacing", "w", "kern",
        "position", "sz", "szCs", "highlight", "u", "effect", "bdr", "shd",
        "fitText", "rtl", "cs", "em", "lang", "eastAsianLayout",
        "vanish", "specVanish", "webHidden",  // hidden flags — text still emitted
        "oMath",                              // equation marker — see shared-math.xsd (future)
        "rPrChange",
    ]

    /// `ST_NumberFormat` values that are NOT ordered: a bullet, or no marker.
    static let nonOrderedNumberFormats: Set<String> = ["bullet", "none"]

    static func isOrdered(numberFormat fmt: String) -> Bool {
        !nonOrderedNumberFormats.contains(fmt)
    }

    // MARK: - Auxiliary parts

    private mutating func loadStyles() throws {
        guard let root = try package.xmlRoot("word/styles.xml") else { return }
        for style in root.childElements("style") {
            guard style.attr("type") == "paragraph", let id = style.attr("styleId") else { continue }
            let name = style.firstChild("name")?.attr("val") ?? id
            if let level = headingLevel(styleId: id, styleName: name) {
                headingLevelByStyleId[id] = level
            }
        }
    }

    private func headingLevel(styleId: String, styleName: String) -> Int? {
        let name = styleName.lowercased()
        if name == "title" { return 1 }
        if name == "subtitle" { return 2 }
        if name.hasPrefix("heading "),
           let n = Int(name.dropFirst("heading ".count).trimmingCharacters(in: .whitespaces)) {
            return min(max(n, 1), 6)
        }
        let id = styleId.lowercased()
        if id.hasPrefix("heading"), let n = Int(id.dropFirst("heading".count)) {
            return min(max(n, 1), 6)
        }
        return nil
    }

    private mutating func loadNumbering() throws {
        guard let root = try package.xmlRoot("word/numbering.xml") else { return }
        var abstractOrdered: [String: [Int: Bool]] = [:]
        for abs in root.childElements("abstractNum") {
            guard let absId = abs.attr("abstractNumId") else { continue }
            var levels: [Int: Bool] = [:]
            for lvl in abs.childElements("lvl") {
                let ilvl = Int(lvl.attr("ilvl") ?? "0") ?? 0
                let fmt = lvl.firstChild("numFmt")?.attr("val") ?? "decimal"
                levels[ilvl] = WordParser.isOrdered(numberFormat: fmt)
            }
            abstractOrdered[absId] = levels
        }
        for num in root.childElements("num") {
            guard let numId = num.attr("numId"),
                  let absId = num.firstChild("abstractNumId")?.attr("val"),
                  let levels = abstractOrdered[absId] else { continue }
            orderedByNumIdLevel[numId] = levels
        }
    }

    // MARK: - Block parsing

    private func parseParagraph(_ el: XMLElement) -> Paragraph {
        var styleId: String?
        var headingLevel: Int?
        var list: ListInfo?

        if let pPr = el.firstChild("pPr") {
            if let style = pPr.firstChild("pStyle")?.attr("val") {
                styleId = style
                headingLevel = headingLevelByStyleId[style]
            }
            if let numPr = pPr.firstChild("numPr"), let numId = numPr.firstChild("numId")?.attr("val") {
                let ilvl = numPr.firstChild("ilvl")?.attr("val").flatMap { Int($0) } ?? 0
                let ordered = orderedByNumIdLevel[numId]?[ilvl] ?? false
                list = ListInfo(level: ilvl, ordered: ordered, numId: numId)
            }
        }

        var inlines: [Inline] = []
        for case let node as XMLElement in el.children ?? [] {
            switch node.localName {
            case "r":
                inlines.append(contentsOf: parseRun(node, link: nil))
            case "hyperlink":
                let target = node.relationshipID().flatMap { relationshipTargets[$0] }
                for r in node.childElements("r") {
                    inlines.append(contentsOf: parseRun(r, link: target))
                }
            case "oMath":
                inlines.append(.math(OMML.latex(node)))
            case "oMathPara":
                for m in node.childElements("oMath") { inlines.append(.math(OMML.latex(m))) }
            default:
                break
            }
        }
        return Paragraph(styleId: styleId, headingLevel: headingLevel, list: list, inlines: inlines)
    }

    private func parseRun(_ el: XMLElement, link: String?) -> [Inline] {
        var base = Run(text: "")
        base.link = link
        if let rPr = el.firstChild("rPr") { applyRunProperties(rPr, to: &base) }

        var result: [Inline] = []
        for case let node as XMLElement in el.children ?? [] {
            switch node.localName {
            case "t":
                var run = base; run.text = node.stringValue ?? ""
                result.append(.text(run))
            case "tab":
                var run = base; run.text = "\t"
                result.append(.text(run))
            case "br", "cr":
                result.append(.lineBreak)
            case "drawing", "pict":
                result.append(.image(alt: imageAlt(node), target: imageTarget(node)))
            default:
                break
            }
        }
        return result
    }

    private func applyRunProperties(_ rPr: XMLElement, to run: inout Run) {
        func isOn(_ e: XMLElement) -> Bool {
            guard let v = e.attr("val") else { return true }
            return !(v == "0" || v == "false" || v == "off")
        }
        for case let p as XMLElement in rPr.children ?? [] {
            switch p.localName {
            case "b", "bCs": run.bold = isOn(p)          // bCs: complex-script bold
            case "i", "iCs": run.italic = isOn(p)        // iCs: complex-script italic
            case "strike", "dstrike": run.strikethrough = isOn(p)
            case "vertAlign":
                switch p.attr("val") {
                case "superscript": run.superscript = true
                case "subscript": run.subscript = true
                default: break
                }
            default:
                break  // ignoredRunProperties (and any unknown, caught by the contract test)
            }
        }
    }

    private func imageTarget(_ drawing: XMLElement) -> String? {
        guard let blip = drawing.firstDescendant("blip"),
              let rId = blip.relationshipID("embed") ?? blip.relationshipID("link") else { return nil }
        return relationshipTargets[rId]
    }

    private func imageAlt(_ drawing: XMLElement) -> String {
        if let docPr = drawing.firstDescendant("docPr") {
            return docPr.attr("descr") ?? docPr.attr("name") ?? "image"
        }
        return "image"
    }

    private func parseTable(_ el: XMLElement, depth: Int) -> Table {
        guard depth <= ParserLimits.maxWordTableDepth else {
            return Table(rows: [[Cell(blocks: [.paragraph(Paragraph(text: "[nested table omitted]"))])]])
        }
        var rows: [[Cell]] = []
        for tr in el.childElements("tr") {
            var cells: [Cell] = []
            for tc in tr.childElements("tc") {
                var blocks: [Block] = []
                for case let node as XMLElement in tc.children ?? [] {
                    switch node.localName {
                    case "p":   blocks.append(.paragraph(parseParagraph(node)))
                    case "tbl": blocks.append(.table(parseTable(node, depth: depth + 1)))
                    default:    break
                    }
                }
                cells.append(Cell(blocks: blocks))
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return Table(rows: rows)
    }
}
