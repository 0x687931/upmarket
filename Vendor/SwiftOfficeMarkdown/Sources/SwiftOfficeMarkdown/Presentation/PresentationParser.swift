import Foundation

/// Parses the PresentationML parts of a `.pptx` into a `MarkdownDoc`: each
/// slide becomes a level-2 heading (its title, or "Slide N") followed by its
/// body text as a bullet list.
///
/// Note: slide *text* is DrawingML — paragraphs are `a:p`, runs are `a:r`/`a:t`,
/// and run emphasis (`b`, `i`, `strike`) are **attributes** on `a:rPr`, unlike
/// WordprocessingML where they are child elements.
public struct PresentationParser {
    private let package: OPCPackage

    public init(package: OPCPackage) { self.package = package }

    // Placeholder types that act as a slide's title.
    static let titlePlaceholderTypes: Set<String> = ["title", "ctrTitle"]

    public mutating func parse() throws -> MarkdownDoc {
        guard let presentation = try package.xmlRoot("ppt/presentation.xml") else {
            return MarkdownDoc(blocks: [])
        }
        let rels = try package.relationships(forPart: "ppt/presentation.xml")

        var blocks: [Block] = []
        var slideNumber = 0
        let idList = presentation.firstChild("sldIdLst") ?? presentation
        for sldId in idList.childElements("sldId") {
            guard let rId = sldId.relationshipID(), let target = rels[rId] else { continue }
            slideNumber += 1
            let partPath = package.resolve(target: target, relativeTo: "ppt/presentation.xml")
            guard let slide = try package.xmlRoot(partPath) else { continue }
            blocks.append(contentsOf: slideBlocks(slide, number: slideNumber))
        }
        return MarkdownDoc(blocks: blocks)
    }

    private func slideBlocks(_ slide: XMLElement, number: Int) -> [Block] {
        var titleText: String?
        var bullets: [(plain: String, block: Block)] = []

        slide.forEachDescendant("sp") { shape in
            let isTitle = shape.firstDescendant("ph").flatMap { $0.attr("type") }
                .map(Self.titlePlaceholderTypes.contains) ?? false
            guard let txBody = shape.firstChild("txBody") else { return }

            for para in txBody.childElements("p") {
                let inlines = runInlines(in: para)
                let plain = plainText(inlines)
                guard !plain.isEmpty else { continue }

                if isTitle && titleText == nil {
                    titleText = plain
                } else {
                    let level = para.firstChild("pPr")?.attr("lvl").flatMap { Int($0) } ?? 0
                    bullets.append((plain, .paragraph(Paragraph(
                        list: ListInfo(level: level, ordered: false, numId: "pptx"),
                        inlines: inlines))))
                }
            }
        }

        var blocks: [Block] = [.paragraph(Paragraph(text: titleText ?? "Slide \(number)", headingLevel: 2))]
        // Decks often repeat the title in a second placeholder — drop bullets
        // that merely echo the slide title.
        blocks.append(contentsOf: bullets.filter { $0.plain != titleText }.map(\.block))
        return blocks
    }

    private func plainText(_ inlines: [Inline]) -> String {
        inlines.compactMap { if case .text(let r) = $0 { return r.text } else { return nil } }
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Build inline runs from an `a:p`, applying DrawingML run attributes.
    private func runInlines(in paragraph: XMLElement) -> [Inline] {
        var inlines: [Inline] = []
        for case let node as XMLElement in paragraph.children ?? [] {
            switch node.localName {
            case "r": // a:r
                guard let t = node.firstChild("t")?.stringValue else { continue }
                var run = Run(text: t)
                if let rPr = node.firstChild("rPr") { applyDrawingRunProperties(rPr, to: &run) }
                inlines.append(.text(run))
            case "br":
                inlines.append(.lineBreak)
            case "fld": // field (e.g. slide number) — emit its cached text
                if let t = node.firstChild("t")?.stringValue { inlines.append(.text(Run(text: t))) }
            default:
                break
            }
        }
        // OOXML math in slide text (m:oMath, usually under an mc:AlternateContent
        // extension) — reuse the shared OMML→LaTeX renderer.
        paragraph.forEachDescendant("oMath") { math in
            inlines.append(.math(OMML.latex(math)))
        }
        return inlines
    }

    /// DrawingML emphasis lives in `a:rPr` *attributes* (b/i/strike), not child
    /// elements. Toggle attributes are "1"/"true" for on.
    private func applyDrawingRunProperties(_ rPr: XMLElement, to run: inout Run) {
        func isOn(_ name: String) -> Bool {
            guard let v = rPr.attr(name) else { return false }
            return v == "1" || v == "true"
        }
        run.bold = isOn("b")
        run.italic = isOn("i")
        if let strike = rPr.attr("strike") { run.strikethrough = (strike != "noStrike") }
    }
}
