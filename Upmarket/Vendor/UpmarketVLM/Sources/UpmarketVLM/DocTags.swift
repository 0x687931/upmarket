import Foundation

/// Converts Granite-Docling **DocTags** output into Markdown — the Swift replacement for
/// `docling_core`'s `DoclingDocument.load_from_doctags(...).export_to_markdown()`.
///
/// DocTags is a tag stream: each element is `<tag><loc_…>content</tag>`; tables use OTSL
/// (`<fcel>`/`<ecel>`/`<ched>`/`<nl>`…). This handles the elements Granite-Docling emits for
/// document conversion; unknown tags are stripped.
public enum DocTags {

    public static func toMarkdown(_ raw: String) -> String {
        var s = raw
        if let r = s.range(of: "<doctag>") { s = String(s[r.upperBound...]) }
        if let r = s.range(of: "</doctag>") { s = String(s[..<r.lowerBound]) }
        // Drop location tokens. Granite emits a bbox as `<loc_x1<loc_y1<loc_x2<loc_y2>` with a
        // single closing `>` after the 4th coord, so the `>` must be optional or only the last
        // token strips (leaving `<loc_x1<loc_y1<loc_x2` garbage that breaks tag matching).
        s = regexReplace(s, #"<loc_\d+>?"#) { _ in "" }

        // Tables first (so their inner tags aren't stripped as text).
        s = regexReplace(s, #"<otsl>(.*?)</otsl>"#, options: [.dotMatchesLineSeparators]) {
            "\n\n" + parseOTSL($0[1]) + "\n\n"
        }
        // Block elements → Markdown, in document order (in-place replacement preserves order).
        let headers: [(String, String)] = [
            ("title", "# "),
            ("section_header_level_1", "## "), ("section_header_level_2", "### "),
            ("section_header_level_3", "#### "), ("section_header_level_4", "##### "),
            ("section_header_level_5", "###### "), ("section_header_level_6", "###### "),
        ]
        for (tag, prefix) in headers {
            s = regexReplace(s, "<\(tag)>(.*?)</\(tag)>", options: [.dotMatchesLineSeparators]) {
                "\n\n\(prefix)\(clean($0[1]))\n\n"
            }
        }
        s = regexReplace(s, #"<list_item>(.*?)</list_item>"#, options: [.dotMatchesLineSeparators]) {
            "\n- \(clean($0[1]))"
        }
        for tag in ["text", "caption", "footnote", "formula", "paragraph"] {
            s = regexReplace(s, "<\(tag)>(.*?)</\(tag)>", options: [.dotMatchesLineSeparators]) {
                "\n\n\(clean($0[1]))\n\n"
            }
        }
        s = regexReplace(s, #"<code>(.*?)</code>"#, options: [.dotMatchesLineSeparators]) {
            "\n\n```\n\(clean($0[1]))\n```\n\n"
        }
        s = regexReplace(s, #"<(picture|chart|image)>.*?</(picture|chart|image)>"#, options: [.dotMatchesLineSeparators]) { _ in "\n\n<!-- image -->\n\n" }
        // Drop page furniture + any remaining tags.
        s = regexReplace(s, #"<(page_header|page_footer)>.*?</(page_header|page_footer)>"#, options: [.dotMatchesLineSeparators]) { _ in "" }
        s = regexReplace(s, #"</?[a-z_0-9]+>"#) { _ in "" }
        // Collapse excess blank lines / spaces.
        s = regexReplace(s, #"[ \t]+\n"#) { _ in "\n" }
        s = regexReplace(s, #"\n{3,}"#) { _ in "\n\n" }
        // Drop a block that exactly repeats the previous non-empty block. Tiled inference can
        // re-emit content seen in both a sub-tile and the global thumbnail (e.g. a Bates number
        // transcribed twice); table rows are exempt so legitimately repeated values survive.
        var deduped: [String] = []
        var lastContent = ""
        for line in s.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !t.hasPrefix("|"), t == lastContent { continue }
            if !t.isEmpty { lastContent = t }
            deduped.append(line)
        }
        s = deduped.joined(separator: "\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse an OTSL cell stream into a Markdown table.
    static func parseOTSL(_ otsl: String) -> String {
        var rows: [[String]] = []
        var cur: [String] = []
        // Each control tag followed by its (optional) cell text up to the next tag.
        for m in regexMatches(otsl, #"<(fcel|ecel|ched|rhed|lcel|ucel|xcel|nl)>([^<]*)"#) {
            let tag = m[1], text = clean(m[2])
            switch tag {
            case "nl":
                rows.append(cur); cur = []
            case "ecel", "lcel", "ucel", "xcel":
                cur.append("")                          // empty / merged cell
            default:
                cur.append(text)                        // fcel, ched, rhed
            }
        }
        if !cur.isEmpty { rows.append(cur) }
        rows = rows.filter { $0.contains { !$0.isEmpty } }
        guard !rows.isEmpty else { return "" }
        let cols = rows.map(\.count).max() ?? 0
        guard cols > 0 else { return "" }
        func pad(_ r: [String]) -> [String] { r + Array(repeating: "", count: cols - r.count) }
        var out = ["| " + pad(rows[0]).joined(separator: " | ") + " |",
                   "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |"]
        for r in rows.dropFirst() { out.append("| " + pad(r).joined(separator: " | ") + " |") }
        return out.joined(separator: "\n")
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - regex helpers
    private static func regexReplace(_ s: String, _ pattern: String,
                                     options: NSRegularExpression.Options = [],
                                     _ transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        let ns = s as NSString
        var result = "", last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result += transform(groups)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
    private static func regexReplace(_ s: String, _ p: String, _ t: ([String]) -> String) -> String {
        regexReplace(s, p, options: [], t)
    }
    private static func regexMatches(_ s: String, _ pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i); return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}
