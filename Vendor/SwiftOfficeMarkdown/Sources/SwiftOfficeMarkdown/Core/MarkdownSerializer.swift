import Foundation

/// Serializes a `MarkdownDoc` to GitHub-flavored Markdown.
struct MarkdownSerializer {
    private var out: [String] = []          // emitted blocks (joined by blank lines)
    private var listCounters: [Int: Int] = [:] // ilvl -> next ordinal for ordered lists
    private var listBuffer: [String] = []   // consecutive list-item lines (joined tightly)
    private var inList = false
    /// True when serializing the contents of a table cell. Markdown headings
    /// don't render inside table cells, so we downgrade them to bold.
    var inCell = false

    mutating func serialize(_ model: MarkdownDoc) -> String {
        for block in model.blocks {
            emit(block)
        }
        flushList()
        // Collapse 3+ blank lines and trim.
        let joined = out.joined(separator: "\n\n")
        return joined.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func emit(_ block: Block) {
        switch block {
        case .paragraph(let p): emit(paragraph: p)
        case .table(let t): flushList(); emitTable(t)
        }
    }

    private mutating func emit(paragraph p: Paragraph) {
        if let list = p.list {
            emitListItem(p, list: list)
            return
        }
        flushList()

        // Table-of-contents entries arrive as tab-separated "1.⇥Title⇥page"
        // lines. Drop the tab leaders and trailing page number for clean prose.
        if let style = p.styleId?.lowercased(), style.hasPrefix("toc") {
            emitTOCEntry(p)
            return
        }

        let text = renderInlines(p.inlines)
        if let level = p.headingLevel {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            if inCell {
                out.append("**\(body)**")
            } else {
                let hashes = String(repeating: "#", count: min(max(level, 1), 6))
                out.append("\(hashes) \(body)")
            }
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(text)
        }
    }

    private mutating func emitTOCEntry(_ p: Paragraph) {
        var t = renderInlines(p.inlines).replacingOccurrences(of: "\t", with: " ")
        t = t.replacingOccurrences(of: "\\s*\\d+\\s*$", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { out.append(t) }
    }

    // MARK: - Lists

    private mutating func emitListItem(_ p: Paragraph, list: ListInfo) {
        if !inList { inList = true; listCounters.removeAll() }
        let indent = String(repeating: "  ", count: list.level)
        let marker: String
        if list.ordered {
            let n = listCounters[list.level, default: 1]
            listCounters[list.level] = n + 1
            // Starting a deeper level resets everything below it.
            for deeper in listCounters.keys where deeper > list.level { listCounters[deeper] = 1 }
            marker = "\(n)."
        } else {
            marker = "-"
        }
        let body = renderInlines(p.inlines).trimmingCharacters(in: .whitespacesAndNewlines)
        // Buffer items so a run of list paragraphs renders as one tight list
        // (single newlines between items) rather than blank-line-separated.
        listBuffer.append("\(indent)\(marker) \(body)")
    }

    private mutating func flushList() {
        if !listBuffer.isEmpty {
            out.append(listBuffer.joined(separator: "\n"))
            listBuffer.removeAll()
        }
        inList = false
        listCounters.removeAll()
    }

    // MARK: - Tables

    private mutating func emitTable(_ table: Table) {
        guard !table.rows.isEmpty else { return }
        let columnCount = table.rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return }

        func renderCell(_ cell: Cell) -> String {
            // Flatten a cell's paragraphs into one line; pipes and newlines
            // would break the table grid.
            var sub = MarkdownSerializer()
            sub.inCell = true
            let text = sub.serialize(MarkdownDoc(blocks: cell.blocks))
            return text
                .replacingOccurrences(of: "\n", with: "<br>")
                .replacingOccurrences(of: "|", with: "\\|")
        }

        func row(_ cells: [Cell]) -> String {
            var rendered = cells.map(renderCell)
            while rendered.count < columnCount { rendered.append("") }
            return "| " + rendered.joined(separator: " | ") + " |"
        }

        var lines: [String] = []
        lines.append(row(table.rows[0]))
        lines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
        for r in table.rows.dropFirst() { lines.append(row(r)) }
        out.append(lines.joined(separator: "\n"))
    }

    // MARK: - Inlines

    private func renderInlines(_ inlines: [Inline]) -> String {
        // Coalesce adjacent text runs that share identical formatting and link
        // so we emit `**ab**` rather than `**a****b**`.
        var result = ""
        var i = 0
        let runs = inlines

        while i < runs.count {
            switch runs[i] {
            case .lineBreak:
                result += "  \n" // hard break
                i += 1
            case .image(let alt, let target):
                let url = target.map { ($0 as NSString).lastPathComponent } ?? ""
                result += "![\(escape(alt))](\(url))"
                i += 1
            case .math(let latex):
                result += "$\(latex)$"   // verbatim — no Markdown escaping
                i += 1
            case .text(let first):
                // Gather a maximal span of text runs with the same style+link.
                var span = [first]
                var j = i + 1
                while j < runs.count, case .text(let next) = runs[j], sameStyle(next, first) {
                    span.append(next)
                    j += 1
                }
                result += renderStyledText(span)
                i = j
            }
        }
        return result
    }

    private func sameStyle(_ a: Run, _ b: Run) -> Bool {
        a.bold == b.bold && a.italic == b.italic && a.strikethrough == b.strikethrough
            && a.superscript == b.superscript && a.subscript == b.subscript && a.link == b.link
    }

    private func renderStyledText(_ span: [Run]) -> String {
        guard let style = span.first else { return "" }
        let raw = span.map(\.text).joined()
        if raw.isEmpty { return "" }

        // Keep leading/trailing whitespace outside the emphasis markers so we
        // never produce `** text **`, which renderers won't treat as bold.
        let leading = String(raw.prefix { $0 == " " })
        let trailing = String(raw.reversed().prefix { $0 == " " }.reversed())
        let coreStart = raw.index(raw.startIndex, offsetBy: leading.count)
        let coreEnd = raw.index(raw.endIndex, offsetBy: -trailing.count)
        guard coreStart < coreEnd else { return raw } // all whitespace
        var core = escape(String(raw[coreStart..<coreEnd]))

        if style.superscript { core = "<sup>\(core)</sup>" }
        if style.subscript { core = "<sub>\(core)</sub>" }
        if style.strikethrough { core = "~~\(core)~~" }
        if style.bold && style.italic { core = "***\(core)***" }
        else if style.bold { core = "**\(core)**" }
        else if style.italic { core = "*\(core)*" }
        if let link = style.link, !link.isEmpty { core = "[\(core)](\(link))" }

        return leading + core + trailing
    }

    /// Escape characters that would otherwise be interpreted as Markdown syntax.
    private func escape(_ text: String) -> String {
        var escaped = String()
        escaped.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\\", "`", "*", "_", "[", "]", "<", ">":
                escaped.append("\\")
                escaped.append(ch)
            default:
                escaped.append(ch)
            }
        }
        return escaped
    }
}
