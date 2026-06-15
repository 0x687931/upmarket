import Foundation

/// Converts plain-text family formats (`.txt`, `.md`, `.csv`) to Markdown entirely
/// in-process — no Python runtime, no network, no third-party dependency. These are
/// Basic-tier formats (`AppTier.requiredTier(for:) == .basic`), so they must convert
/// without the Enhanced runtime download.
///
/// - `.md`  is already Markdown and is passed through verbatim.
/// - `.txt` is plain text and is valid Markdown as-is (only trailing whitespace trimmed).
/// - `.csv` is parsed (RFC 4180: quoted fields, escaped quotes, embedded newlines) and
///   rendered as a GitHub-Flavored Markdown table.
enum NativeTextConverter {

    enum Failure: Error { case unreadable }

    /// File extensions this converter handles, lowercased.
    static let extensions: Set<String> = ["txt", "md", "csv"]

    /// Convert raw bytes for the given extension to Markdown.
    static func convert(data: Data, ext: String) throws -> String {
        guard let source = decodeText(data) else { throw Failure.unreadable }

        switch ext.lowercased() {
        case "csv":
            return csvToMarkdown(source)
        case "md":
            // Already Markdown — pass through, normalising only trailing whitespace.
            return source.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        default:
            // Plain text is valid Markdown. Preserve the author's line breaks.
            return source.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }
    }

    // MARK: - Decoding

    /// Decode bytes as UTF-8, falling back to Latin-1 (which never fails) so a mis-encoded
    /// file still yields text rather than an error.
    private static func decodeText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data: data, encoding: .isoLatin1)
    }

    // MARK: - CSV

    /// Render parsed CSV rows as a Markdown table. The first row is treated as the header.
    /// Returns an empty string for empty input.
    static func csvToMarkdown(_ source: String) -> String {
        let rows = parseCSV(source)
        guard let header = rows.first, !header.isEmpty else { return "" }

        let columnCount = rows.map(\.count).max() ?? header.count
        func pad(_ row: [String]) -> [String] {
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }
        func cell(_ value: String) -> String {
            // Collapse newlines and escape pipes so a field can't break the column layout.
            value
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "|", with: "\\|")
        }

        var lines: [String] = []
        lines.append("| " + pad(header).map(cell).joined(separator: " | ") + " |")
        lines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append("| " + pad(row).map(cell).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Minimal RFC 4180 parser: handles quoted fields, `""` escaped quotes, and commas/
    /// newlines embedded inside quotes. Accepts both `\n` and `\r\n` row terminators.
    static func parseCSV(_ source: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        let scalars = Array(source)
        var i = 0

        func endField() { record.append(field); field = "" }
        func endRecord() {
            endField()
            // Skip blank trailing record produced by a final newline.
            if !(record.count == 1 && record[0].isEmpty) { rows.append(record) }
            record = []
        }

        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.append("\""); i += 1  // escaped quote
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": endField()
                case "\r":
                    if i + 1 < scalars.count && scalars[i + 1] == "\n" { i += 1 }
                    endRecord()
                case "\n": endRecord()
                default: field.append(c)
                }
            }
            i += 1
        }
        // Flush any trailing field/record not terminated by a newline.
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return rows
    }
}
