import Foundation

/// Converts HTML to GitHub-Flavored Markdown entirely in-process.
///
/// Parsing uses Foundation's libxml2-backed `XMLDocument` tidy mode, so the conversion
/// path has no Python runtime, no network, and no third-party dependency. HTML therefore
/// converts in the Basic tier without the Enhanced runtime download. The DOM→Markdown
/// walker is ours; only the tolerant parse is delegated to the system.
///
/// Output was validated for parity against SwiftSoup (jsoup/HTML5) over a differential
/// corpus: identical on the common cases once HTML5 semantic elements are preserved (see
/// `preserveHTML5Elements`). The residual differences are HTML5 tree-construction rules
/// libxml2's HTML4-era parser predates, and are decided before the walker runs:
///   • `<a>` wrapping block content — HTML5 keeps the link; libxml2 closes the anchor.
///   • Adoption agency — recovery of misnested formatting (`<b><i></b></i>`) differs.
///   • Foster parenting — stray text inside `<table>`; here libxml2 *keeps* the text that
///     HTML5 relocates/drops, so it favors content preservation.
/// These appear only in malformed markup; well-formed documents convert identically.
enum NativeHTMLConverter {

    enum Failure: Error { case unparseable }

    /// Convert raw HTML bytes to Markdown.
    static func convert(data: Data) throws -> String {
        let source = String(decoding: data, as: UTF8.self)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        // libxml2's tidy parser mis-detects the input encoding and silently drops every
        // non-ASCII character (and even numeric references), unless an authoritative UTF-8
        // declaration is present. Two steps make it deterministic regardless of any charset
        // the source already declares:
        //   1. Escape all non-ASCII scalars to numeric references, so the byte stream is
        //      pure ASCII and input decoding cannot corrupt or drop anything.
        //   2. Prepend an http-equiv UTF-8 declaration (the form libxml2 honors — the short
        //      HTML5 `<meta charset>` form is not), so the parse tree serializes as UTF-8.
        // With encoding pinned, libxml2 resolves all named entities (&mdash;, &nbsp;, …) itself.
        let prepared = Self.utf8Declaration + Self.escapeNonASCII(Self.preserveHTML5Elements(source))

        let doc: XMLDocument
        do {
            // `.documentTidyHTML` runs libxml2's lenient HTML parser, recovering from the
            // malformed markup real-world web pages ship with.
            doc = try XMLDocument(data: Data(prepared.utf8), options: [.documentTidyHTML])
        } catch {
            throw Failure.unparseable
        }
        guard let root = doc.rootElement() else { throw Failure.unparseable }
        let body = firstDescendant(named: "body", under: root) ?? root
        var walker = Walker()
        return walker.document(body)
    }

    /// Convert an HTML string to Markdown.
    static func convert(html: String) throws -> String {
        try convert(data: Data(html.utf8))
    }

    // MARK: - Parser preparation

    private static let utf8Declaration =
        "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">"

    /// HTML5 sectioning/semantic elements that libxml2's HTML4-era parser does not know and
    /// silently drops (keeping their children). Mapped to a generic container the walker
    /// already handles: block-level → `div`, inline-level → `span`.
    private static let html5BlockElements: Set<String> = [
        "figure", "figcaption", "section", "article", "main", "aside", "nav",
        "header", "footer", "details", "summary", "dialog", "hgroup", "search",
    ]
    private static let html5InlineElements: Set<String> = ["mark", "time", "data", "bdi", "output"]

    /// Rewrite the HTML5 elements libxml2 would drop into `<div>`/`<span>` so the document
    /// structure survives the parse. Renaming is safe because the walker treats every `div`
    /// as a block container and every unknown inline tag as a passthrough — the original tag
    /// identity carries no Markdown meaning. Only exact tag tokens (`<figure`, `</figure>`)
    /// are matched, so attributes like `data-x` and text are untouched.
    static func preserveHTML5Elements(_ html: String) -> String {
        guard html.contains("<") else { return html }
        var out = renameTags(html, html5BlockElements, to: "div")
        out = renameTags(out, html5InlineElements, to: "span")
        return out
    }

    private static func renameTags(_ html: String, _ tags: Set<String>, to replacement: String) -> String {
        let pattern = "(</?)(?:\(tags.joined(separator: "|")))\\b"
        return html.replacingOccurrences(
            of: pattern, with: "$1\(replacement)",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Replace every non-ASCII scalar with a numeric character reference.
    private static func escapeNonASCII(_ source: String) -> String {
        guard source.unicodeScalars.contains(where: { $0.value > 127 }) else { return source }
        var out = ""
        out.reserveCapacity(source.count)
        for scalar in source.unicodeScalars {
            out += scalar.value > 127 ? "&#\(scalar.value);" : String(scalar)
        }
        return out
    }

    // MARK: - Tree helpers

    private static func firstDescendant(named name: String, under node: XMLNode) -> XMLElement? {
        guard let element = node as? XMLElement else { return nil }
        if element.name?.lowercased() == name { return element }
        for child in element.children ?? [] {
            if let hit = firstDescendant(named: name, under: child) { return hit }
        }
        return nil
    }
}

// MARK: - Walker

/// Recursive DOM→Markdown emitter. Block elements produce paragraph-separated chunks;
/// inline elements fold into a single line with collapsed whitespace.
private struct Walker {

    /// Tags whose entire subtree contributes nothing to the document text.
    private static let dropped: Set<String> = ["script", "style", "head", "noscript", "template", "svg"]

    /// Placeholder for a `<br>`-injected hard break. A real control character survives
    /// whitespace collapsing (which can't tell a `<br>` newline from an insignificant
    /// source newline) and is swapped for a Markdown hard break afterwards.
    private static let hardBreak = "\u{1}"

    /// Render the top-level document as Markdown blocks joined by blank lines.
    mutating func document(_ root: XMLElement) -> String {
        let blocks = renderBlocks(of: root)
        return blocks
            .joined(separator: "\n\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: Block context

    /// Walk an element's children, emitting one Markdown block per block-level child.
    /// Runs of inline children are coalesced into a single paragraph block.
    private mutating func renderBlocks(of element: XMLElement) -> [String] {
        var blocks: [String] = []
        var inlineRun = ""

        func flushInline() {
            let text = collapse(inlineRun)
            if !text.isEmpty { blocks.append(text) }
            inlineRun = ""
        }

        for child in element.children ?? [] {
            switch child.kind {
            case .text:
                inlineRun += escapeText(child.stringValue ?? "")
            case .element:
                guard let el = child as? XMLElement, let tag = el.name?.lowercased() else { continue }
                if Self.dropped.contains(tag) { continue }
                if let block = blockMarkdown(for: tag, element: el) {
                    flushInline()
                    if !block.isEmpty { blocks.append(block) }
                } else {
                    // Inline-level element: append its rendered text to the current run.
                    inlineRun += inline(el)
                }
            default:
                continue
            }
        }
        flushInline()
        return blocks
    }

    /// Returns the Markdown block for a block-level tag, or `nil` if the tag is inline.
    private mutating func blockMarkdown(for tag: String, element el: XMLElement) -> String? {
        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.dropFirst())) ?? 1
            return String(repeating: "#", count: level) + " " + collapse(inline(el))

        case "p":
            return escapeBlockLeading(collapse(inline(el)))

        case "br":
            return ""  // a lone <br> between blocks is just separation

        case "hr":
            return "---"

        case "ul":
            return list(el, ordered: false, depth: 0)
        case "ol":
            return list(el, ordered: true, depth: 0)

        case "dl":
            return definitionList(el)

        case "blockquote":
            let inner = renderBlocks(of: el).joined(separator: "\n\n")
            return inner
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> " + $0 }
                .joined(separator: "\n")

        case "pre":
            // Preserve raw text; libxml2 keeps <pre> whitespace in stringValue.
            let code = (el.stringValue ?? "").trimmingCharacters(in: .newlines)
            return "```\n" + code + "\n```"

        case "table":
            return table(el)

        // Generic block containers: recurse and let children form their own blocks.
        case "div", "section", "article", "main", "header", "footer", "aside", "nav",
             "figure", "figcaption", "form", "fieldset", "details", "summary", "address":
            return renderBlocks(of: el).joined(separator: "\n\n")

        default:
            return nil  // treat unknown tags as inline
        }
    }

    // MARK: Lists

    private mutating func list(_ element: XMLElement, ordered: Bool, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []
        // Honor <ol start="N">; default to 1.
        var index = ordered ? (element.attribute(forName: "start")?.stringValue.flatMap(Int.init) ?? 1) : 1
        for child in element.children ?? [] {
            guard let li = child as? XMLElement, li.name?.lowercased() == "li" else { continue }

            // Split the item into its own inline text, any nested lists, and a leading
            // checkbox input (GFM task list).
            var inlineRun = ""
            var nested: [String] = []
            var task: String? = nil
            for node in li.children ?? [] {
                if let nestedEl = node as? XMLElement,
                   let nestedTag = nestedEl.name?.lowercased(),
                   nestedTag == "ul" || nestedTag == "ol" {
                    nested.append(list(nestedEl, ordered: nestedTag == "ol", depth: depth + 1))
                } else if let el = node as? XMLElement {
                    if el.name?.lowercased() == "input",
                       el.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" {
                        task = el.attribute(forName: "checked") != nil ? "[x] " : "[ ] "
                    } else {
                        inlineRun += inline(el)
                    }
                } else if node.kind == .text {
                    inlineRun += escapeText(node.stringValue ?? "")
                }
            }
            let marker = ordered ? "\(index). " : "- "
            index += 1
            lines.append(indent + marker + (task ?? "") + collapse(inlineRun))
            lines.append(contentsOf: nested)
        }
        return lines.joined(separator: "\n")
    }

    /// Render `<dl>` as bold terms each followed by their definitions, one per line.
    private mutating func definitionList(_ element: XMLElement) -> String {
        var lines: [String] = []
        for child in element.children ?? [] {
            guard let el = child as? XMLElement, let tag = el.name?.lowercased() else { continue }
            switch tag {
            case "dt": lines.append("**" + collapse(inline(el)) + "**")
            case "dd": lines.append(collapse(inline(el)))
            default: continue
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Tables

    private mutating func table(_ element: XMLElement) -> String {
        var rows: [[String]] = []
        collectRows(element, into: &rows)
        guard let header = rows.first else { return "" }

        let columnCount = rows.map(\.count).max() ?? header.count
        func pad(_ row: [String]) -> [String] {
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }

        var out = ["| " + pad(header).joined(separator: " | ") + " |"]
        out.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            out.append("| " + pad(row).joined(separator: " | ") + " |")
        }
        let table = out.joined(separator: "\n")

        // A <caption> renders as an emphasized line above the table, as its own block.
        if let caption = (element.children ?? []).first(where: { ($0 as? XMLElement)?.name?.lowercased() == "caption" }) as? XMLElement {
            let text = collapse(inline(caption))
            if !text.isEmpty { return "**" + text + "**\n\n" + table }
        }
        return table
    }

    private mutating func collectRows(_ node: XMLElement, into rows: inout [[String]]) {
        for child in node.children ?? [] {
            guard let el = child as? XMLElement, let tag = el.name?.lowercased() else { continue }
            switch tag {
            case "tr":
                var cells: [String] = []
                for cellNode in el.children ?? [] {
                    guard let cell = cellNode as? XMLElement,
                          let cellTag = cell.name?.lowercased(),
                          cellTag == "td" || cellTag == "th" else { continue }
                    // Escape pipes so cell content can't break the column layout.
                    cells.append(collapse(inline(cell)).replacingOccurrences(of: "|", with: "\\|"))
                }
                if !cells.isEmpty { rows.append(cells) }
            case "thead", "tbody", "tfoot":
                collectRows(el, into: &rows)
            default:
                continue
            }
        }
    }

    // MARK: Inline context

    /// Render an element's subtree as a single inline Markdown string.
    private mutating func inline(_ element: XMLElement) -> String {
        let tag = element.name?.lowercased() ?? ""
        switch tag {
        case "strong", "b":
            return wrap(children(of: element), "**")
        case "em", "i":
            return wrap(children(of: element), "*")
        case "code":
            // Code is verbatim: take raw descendant text, never escaped or re-marked-up.
            return "`" + (element.stringValue ?? "") + "`"
        case "del", "s", "strike":
            return wrap(children(of: element), "~~")
        case "br":
            return Self.hardBreak
        case "a":
            let text = children(of: element)
            guard let href = element.attribute(forName: "href")?.stringValue, !href.isEmpty else { return text }
            // Drop anchors with no visible label (e.g. block content libxml2 hoisted out) so
            // they don't leave `[](url)` noise; keep the bare text if there is any.
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
            return "[\(text)](\(Self.decodeNonASCIIEscapes(href)))"
        case "img":
            let alt = element.attribute(forName: "alt")?.stringValue ?? ""
            let src = element.attribute(forName: "src")?.stringValue ?? ""
            return src.isEmpty ? "" : "![\(alt)](\(Self.decodeNonASCIIEscapes(src)))"
        default:
            return children(of: element)
        }
    }

    /// Concatenate an element's children in inline context.
    private mutating func children(of element: XMLElement) -> String {
        var out = ""
        for child in element.children ?? [] {
            switch child.kind {
            case .text:
                out += escapeText(child.stringValue ?? "")
            case .element:
                guard let el = child as? XMLElement, let tag = el.name?.lowercased() else { continue }
                if Self.dropped.contains(tag) { continue }
                out += inline(el)
            default:
                continue
            }
        }
        return out
    }

    /// Wrap non-empty content in an emphasis delimiter, preserving surrounding spaces
    /// outside the markers so `a <b>b</b> c` renders correctly.
    private func wrap(_ content: String, _ delimiter: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return content }
        let leading = content.hasPrefix(" ") ? " " : ""
        let trailing = content.hasSuffix(" ") ? " " : ""
        return leading + delimiter + trimmed + delimiter + trailing
    }

    // MARK: Whitespace

    /// Collapse runs of HTML whitespace to single spaces and trim the edges, matching how
    /// browsers fold insignificant whitespace in flow content.
    private func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t\\n\\r\\f]+", with: " ", options: .regularExpression)
            // Restore <br> hard breaks, absorbing any spaces the collapse left around them.
            .replacingOccurrences(of: " ?\(Self.hardBreak) ?", with: "  \n", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Markdown escaping

    /// Characters that change inline Markdown rendering anywhere they appear.
    private static let inlineSpecials: Set<Character> = ["\\", "`", "*", "_", "[", "]"]

    /// Backslash-escape characters in flow text so literal source content is not reparsed as
    /// Markdown. Applied only to text nodes — never to generated markup, code, or URLs.
    private func escapeText(_ text: String) -> String {
        guard text.contains(where: { Self.inlineSpecials.contains($0) }) else { return text }
        var out = ""
        out.reserveCapacity(text.count + 4)
        for ch in text {
            if Self.inlineSpecials.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Escape a leading marker that would otherwise turn a paragraph into a heading,
    /// blockquote, or list item (`#`, `>`, `-`, `+`, `1.`). Bullets `*` and `[` are already
    /// covered by inline escaping; only the markers it misses are handled here.
    private func escapeBlockLeading(_ line: String) -> String {
        if line.range(of: "^(#{1,6}|>|[-+])(?=\\s|$)", options: .regularExpression) != nil {
            return "\\" + line
        }
        if let m = line.range(of: "^\\d+([.)])(?=\\s|$)", options: .regularExpression) {
            var s = line
            s.insert("\\", at: line.index(before: m.upperBound))
            return s
        }
        return line
    }

    // MARK: URLs

    /// Reverse the percent-encoding libxml2 applies to non-ASCII bytes in URI attributes,
    /// while leaving intentional ASCII escapes (`%20`, `%2F`, …) verbatim. A maximal run of
    /// `%HH` tokens that carries any byte ≥ 0x80 and decodes as valid UTF-8 is libxml2's doing
    /// and is restored to its raw characters; a run of only ASCII bytes is left as authored.
    static func decodeNonASCIIEscapes(_ url: String) -> String {
        guard url.contains("%") else { return url }
        let chars = Array(url)
        var out = ""
        var i = 0
        while i < chars.count {
            guard chars[i] == "%", i + 2 < chars.count,
                  let hi = chars[i + 1].hexDigitValue, let lo = chars[i + 2].hexDigitValue else {
                out.append(chars[i]); i += 1; continue
            }
            var bytes: [UInt8] = [UInt8(hi << 4 | lo)]
            var raw = "%\(chars[i + 1])\(chars[i + 2])"
            var j = i + 3
            while j + 2 < chars.count, chars[j] == "%",
                  let h = chars[j + 1].hexDigitValue, let l = chars[j + 2].hexDigitValue {
                bytes.append(UInt8(h << 4 | l))
                raw += "%\(chars[j + 1])\(chars[j + 2])"
                j += 3
            }
            if bytes.contains(where: { $0 >= 0x80 }), let decoded = String(bytes: bytes, encoding: .utf8) {
                out += decoded
            } else {
                out += raw
            }
            i = j
        }
        return out
    }
}
