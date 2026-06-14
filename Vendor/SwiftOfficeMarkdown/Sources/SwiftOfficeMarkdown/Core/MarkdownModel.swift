import Foundation

/// Format-neutral Markdown document model. Every format parser
/// (Word / Spreadsheet / Presentation) produces this, and one serializer
/// renders it. Visual-only attributes (fonts, colours, spacing) are
/// intentionally discarded — like mammoth, we map *semantics* (headings,
/// lists, emphasis, tables, links) rather than reproduce appearance.
public struct MarkdownDoc {
    public var blocks: [Block]
    public init(blocks: [Block]) { self.blocks = blocks }
}

public enum Block {
    case paragraph(Paragraph)
    case table(Table)
}

public struct Paragraph {
    /// Raw paragraph style id (e.g. "Heading2", "TOC1"), if any.
    public var styleId: String?
    /// Resolved heading level 1...6, if this paragraph uses a heading style.
    public var headingLevel: Int?
    /// List membership, if any.
    public var list: ListInfo?
    public var inlines: [Inline]

    public init(styleId: String? = nil, headingLevel: Int? = nil,
                list: ListInfo? = nil, inlines: [Inline]) {
        self.styleId = styleId
        self.headingLevel = headingLevel
        self.list = list
        self.inlines = inlines
    }

    /// Convenience: a plain-text paragraph (optionally a heading or list item).
    public init(text: String, headingLevel: Int? = nil, list: ListInfo? = nil) {
        self.init(headingLevel: headingLevel, list: list, inlines: [.text(Run(text: text))])
    }

    public var isBlank: Bool {
        inlines.allSatisfy {
            if case .text(let r) = $0 { return r.text.trimmingCharacters(in: .whitespaces).isEmpty }
            return false
        }
    }
}

public struct ListInfo {
    public var level: Int      // 0-based nesting (w:ilvl)
    public var ordered: Bool   // true for numbered, false for bullet
    public var numId: String   // distinguishes independent lists
}

public enum Inline {
    case text(Run)
    case lineBreak
    case image(alt: String, target: String?)
    /// A LaTeX-ish math expression, emitted verbatim inside `$…$` (no Markdown
    /// escaping). Produced from OOXML `m:oMath`.
    case math(String)
}

public struct Run {
    public var text: String
    public var bold = false
    public var italic = false
    public var strikethrough = false
    public var superscript = false
    public var `subscript` = false
    /// Hyperlink target if this run sits inside a `<w:hyperlink>`.
    public var link: String?

    public init(text: String) { self.text = text }
}

public struct Table {
    public var rows: [[Cell]]
}

public struct Cell {
    public var blocks: [Block]
}
