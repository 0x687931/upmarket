import Foundation

/// Repairs missing or corrupted tables in markdown by reconstructing from original structure.
/// Works with structured table data extracted via Vision framework.
struct TableRepair {

    /// Structured table data extracted from Vision framework.
    struct StructuredTable: Equatable, Sendable {
        let rows: [[String]]  // Array of rows, each row is array of cell strings
        let headerRow: Int    // Index of header row (usually 0)
        let columnCount: Int
        let rowCount: Int
        let originalPosition: Int?  // Where it appeared in document

        init(rows: [[String]], headerRow: Int = 0) {
            self.rows = rows
            self.headerRow = headerRow
            self.columnCount = rows.first?.count ?? 0
            self.rowCount = rows.count
            self.originalPosition = nil
        }
    }

    /// Detect missing tables by comparing original structure with output.
    static func detectMissingTables(
        originalTables: [StructuredTable],
        outputMarkdown: String
    ) -> [StructuredTable] {
        var remainingOutputTables = extractMarkdownTableSignatures(from: outputMarkdown)
        var missing: [StructuredTable] = []

        for table in originalTables {
            let signature = tableSignature(for: table)
            if let index = remainingOutputTables.firstIndex(of: signature) {
                remainingOutputTables.remove(at: index)
            } else {
                missing.append(table)
            }
        }

        return missing
    }

    /// Repair markdown by inserting missing tables at appropriate positions.
    static func repairMissingTables(
        markdown: String,
        insertTables: [StructuredTable],
        afterHeading: String? = nil
    ) -> String {
        guard !insertTables.isEmpty else { return markdown }

        var lines = markdown.components(separatedBy: .newlines)
        var insertionPoint = lines.count

        // If afterHeading specified, insert after that heading
        if let heading = afterHeading {
            if let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).contains(heading) }) {
                insertionPoint = headingIndex + 1

                // Skip any existing content until next heading or end
                while insertionPoint < lines.count && !lines[insertionPoint].trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    insertionPoint += 1
                }
            }
        }

        // Insert missing tables
        var tablesToInsert: [String] = []
        for table in insertTables {
            tablesToInsert.append(tableToMarkdown(table))
        }

        // Insert with spacing
        lines.insert(contentsOf: [""] + tablesToInsert + [""], at: insertionPoint)

        return lines.joined(separator: "\n")
    }

    /// Extract tables detected in markdown.
    static func extractMarkdownTables(from markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: .newlines)
        var tables: [String] = []
        var currentTable: [String] = []
        var inTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Table line starts with |
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                currentTable.append(line)
                inTable = true
            } else if inTable && !currentTable.isEmpty {
                // End of table
                tables.append(currentTable.joined(separator: "\n"))
                currentTable = []
                inTable = false
            }
        }

        // Flush final table
        if !currentTable.isEmpty {
            tables.append(currentTable.joined(separator: "\n"))
        }

        return tables
    }

    private static func extractMarkdownTableSignatures(from markdown: String) -> [String] {
        extractMarkdownTables(from: markdown).map(normalizeMarkdownTable)
    }

    private static func tableSignature(for table: StructuredTable) -> String {
        normalizeMarkdownTable(tableToMarkdown(table))
    }

    private static func normalizeMarkdownTable(_ markdown: String) -> String {
        markdown
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " | ", with: "|")
                    .replacingOccurrences(of: "| ", with: "|")
                    .replacingOccurrences(of: " |", with: "|")
                    .lowercased()
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Convert structured table to markdown format.
    static func tableToMarkdown(_ table: StructuredTable) -> String {
        var lines: [String] = []

        for (idx, row) in table.rows.enumerated() {
            let cells = row.map { cell in
                cell.replacingOccurrences(of: "\n", with: " ")
                   .trimmingCharacters(in: .whitespaces)
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")

            // Add separator after header
            if idx == table.headerRow {
                lines.append("| " + cells.map { _ in "---" }.joined(separator: " | ") + " |")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Validate table structure integrity.
    static func validateTableStructure(_ table: StructuredTable) -> [String] {
        var issues: [String] = []

        // Check all rows have same column count
        let expectedCols = table.columnCount
        for (idx, row) in table.rows.enumerated() {
            if row.count != expectedCols {
                issues.append("Row \(idx) has \(row.count) columns (expected \(expectedCols))")
            }
        }

        // Check header exists
        if table.rows.isEmpty {
            issues.append("Table is empty (no rows)")
        }

        // Check cells aren't all empty
        let nonEmptyCells = table.rows.flatMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if nonEmptyCells.isEmpty {
            issues.append("Table has no content (all cells empty)")
        }

        return issues
    }
}
