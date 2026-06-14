import Foundation

enum SpreadsheetTableBuilder {
    static func table(from sparseRows: [Int: [Int: String]]) -> Table? {
        let rowKeys = sparseRows.keys.sorted().prefix(ParserLimits.maxMarkdownTableRows)
        guard !rowKeys.isEmpty else { return nil }

        var usedColumns = Set<Int>()
        for row in rowKeys {
            guard let rowCells = sparseRows[row] else { continue }
            for col in rowCells.keys where col >= 0 && col < ParserLimits.excelMaxColumns {
                usedColumns.insert(col)
                if usedColumns.count >= ParserLimits.maxMarkdownTableColumns { break }
            }
            if usedColumns.count >= ParserLimits.maxMarkdownTableColumns { break }
        }
        let columns = usedColumns.sorted().prefix(ParserLimits.maxMarkdownTableColumns)
        guard !columns.isEmpty else { return nil }

        let maxRowsByCells = max(1, ParserLimits.maxMarkdownTableCells / max(columns.count, 1))
        let cappedRows = rowKeys.prefix(maxRowsByCells)
        var tableRows: [[Cell]] = []
        tableRows.reserveCapacity(cappedRows.count)
        for row in cappedRows {
            let rowCells = sparseRows[row] ?? [:]
            tableRows.append(columns.map { col in
                Cell(blocks: [.paragraph(Paragraph(text: rowCells[col] ?? ""))])
            })
        }
        return tableRows.isEmpty ? nil : Table(rows: tableRows)
    }
}
