import Foundation

/// Comprehensive document structure validation and repair.
/// Extracts structure from both input and output, compares them, and repairs
/// the output markdown if structure doesn't match.
struct DocumentStructureValidator {

    struct DocumentStructure {
        let headings: [Heading]
        let tables: [TableInfo]
        let lists: [ListInfo]
        let sections: [Section]

        struct Heading {
            let level: Int  // 1-6
            let text: String
            let lineNumber: Int
        }

        struct Section {
            let title: String
            let level: Int
            let startLine: Int
            let endLine: Int
            let content: String
        }

        struct TableInfo {
            let title: String?
            let rows: Int
            let columns: Int
            let lineNumber: Int
        }

        struct ListInfo {
            let items: Int
            let depth: Int  // max nesting level
            let lineNumber: Int
        }
    }

    struct ValidationReport {
        let isValid: Bool
        let issues: [Issue]
        let reformattedMarkdown: String?
        let metrics: Metrics

        struct Issue {
            let severity: Severity  // warning, error
            let category: Category
            let description: String

            enum Severity {
                case warning, error
            }

            enum Category {
                case missingHeading
                case missingSection
                case missingTable
                case missingList
                case headingLevelWrong
                case sectionOrderWrong
                case tableStructureWrong
                case emptySection
            }
        }

        struct Metrics {
            let inputHeadingCount: Int
            let outputHeadingCount: Int
            let inputTableCount: Int
            let outputTableCount: Int
            let inputListCount: Int
            let outputListCount: Int
            let structureRetention: Double  // 0.0-1.0
        }
    }

    /// Validate and repair document structure.
    static func validateAndRepair(
        originalMarkdown: String,
        convertedMarkdown: String
    ) -> ValidationReport {
        validateAndRepair(
            originalMarkdown: originalMarkdown,
            convertedMarkdown: convertedMarkdown,
            originalTables: []
        )
    }

    /// Validate and repair document structure with table preservation and repair.
    static func validateAndRepair(
        originalMarkdown: String,
        convertedMarkdown: String,
        originalTables: [TableRepair.StructuredTable]
    ) -> ValidationReport {
        let originalStructure = extractStructure(from: originalMarkdown)
        let convertedStructure = extractStructure(from: convertedMarkdown)

        var issues = compareStructures(original: originalStructure, converted: convertedStructure)
        var reformatted = issues.isEmpty ? nil : repairMarkdown(
            markdown: convertedMarkdown,
            targetStructure: originalStructure,
            currentStructure: convertedStructure
        )

        // Check for missing tables and repair if Vision data available
        if !originalTables.isEmpty {
            let markdown = reformatted ?? convertedMarkdown
            let missingTables = TableRepair.detectMissingTables(
                originalTables: originalTables,
                outputMarkdown: markdown
            )

            if !missingTables.isEmpty {
                let repaired = TableRepair.repairMissingTables(
                    markdown: markdown,
                    insertTables: missingTables
                )
                reformatted = repaired

                // Log that table repair was applied
                for _ in missingTables {
                    issues.append(
                        ValidationReport.Issue(
                            severity: .warning,
                            category: .missingTable,
                            description: "Missing table auto-repaired from Vision extraction data"
                        )
                    )
                }
            }
        }

        let metrics = ValidationReport.Metrics(
            inputHeadingCount: originalStructure.headings.count,
            outputHeadingCount: convertedStructure.headings.count,
            inputTableCount: originalStructure.tables.count,
            outputTableCount: convertedStructure.tables.count,
            inputListCount: originalStructure.lists.count,
            outputListCount: convertedStructure.lists.count,
            structureRetention: calculateRetention(original: originalStructure, converted: convertedStructure)
        )

        return ValidationReport(
            isValid: issues.isEmpty,
            issues: issues,
            reformattedMarkdown: reformatted,
            metrics: metrics
        )
    }

    // MARK: - Structure Extraction

    private static func extractStructure(from markdown: String) -> DocumentStructure {
        let lines = markdown.components(separatedBy: .newlines)
        var headings: [DocumentStructure.Heading] = []
        var tables: [DocumentStructure.TableInfo] = []
        var lists: [DocumentStructure.ListInfo] = []
        var sections: [DocumentStructure.Section] = []

        var currentSection: (title: String, level: Int, start: Int)?

        for (lineNum, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract headings
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)

                if !text.isEmpty {
                    headings.append(.init(level: level, text: text, lineNumber: lineNum))

                    // Save previous section
                    if let prev = currentSection {
                        let content = lines[prev.start..<lineNum].joined(separator: "\n")
                        sections.append(.init(
                            title: prev.title,
                            level: prev.level,
                            startLine: prev.start,
                            endLine: lineNum,
                            content: content
                        ))
                    }

                    currentSection = (text, level, lineNum)
                }
            }

            // Extract tables (lines with | markers)
            if trimmed.contains("|") && !trimmed.starts(with: "#") {
                let cells = trimmed.components(separatedBy: "|").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if cells.count > 1 {
                    tables.append(.init(title: nil, rows: 1, columns: cells.count, lineNumber: lineNum))
                }
            }

            // Extract lists
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let depth = line.prefix(while: { $0 == " " }).count / 2 + 1
                lists.append(.init(items: 1, depth: depth, lineNumber: lineNum))
            }
        }

        // Save final section
        if let prev = currentSection {
            let content = lines[prev.start...].joined(separator: "\n")
            sections.append(.init(
                title: prev.title,
                level: prev.level,
                startLine: prev.start,
                endLine: lines.count,
                content: content
            ))
        }

        return DocumentStructure(
            headings: headings,
            tables: tables,
            lists: lists,
            sections: sections
        )
    }

    // MARK: - Structure Comparison

    private static func compareStructures(
        original: DocumentStructure,
        converted: DocumentStructure
    ) -> [ValidationReport.Issue] {
        var issues: [ValidationReport.Issue] = []

        // Check headings
        if original.headings.count > converted.headings.count {
            let missing = original.headings.count - converted.headings.count
            issues.append(.init(
                severity: .error,
                category: .missingHeading,
                description: "Missing \(missing) heading(s) from original document"
            ))
        }

        // Check heading levels match
        for (idx, origHeading) in original.headings.enumerated() {
            if idx < converted.headings.count {
                let convHeading = converted.headings[idx]
                if origHeading.level != convHeading.level {
                    issues.append(.init(
                        severity: .warning,
                        category: .headingLevelWrong,
                        description: "Heading '\(origHeading.text)' should be level \(origHeading.level), got \(convHeading.level)"
                    ))
                }
                if origHeading.text != convHeading.text {
                    issues.append(.init(
                        severity: .warning,
                        category: .missingHeading,
                        description: "Heading text changed: '\(origHeading.text)' → '\(convHeading.text)'"
                    ))
                }
            }
        }

        // Check tables
        if original.tables.count > converted.tables.count {
            let missing = original.tables.count - converted.tables.count
            issues.append(.init(
                severity: .error,
                category: .missingTable,
                description: "Missing \(missing) table(s) from original document"
            ))
        }

        // Check lists
        if original.lists.count > converted.lists.count {
            let missing = original.lists.count - converted.lists.count
            issues.append(.init(
                severity: .warning,
                category: .missingList,
                description: "Missing \(missing) list(s) from original document"
            ))
        }

        // Check sections aren't empty
        for section in converted.sections {
            let contentLength = section.content.trimmingCharacters(in: .whitespacesAndNewlines).count
            if contentLength < 20 {
                issues.append(.init(
                    severity: .warning,
                    category: .emptySection,
                    description: "Section '\(section.title)' has very little content (\(contentLength) chars)"
                ))
            }
        }

        return issues
    }

    // MARK: - Structure Repair

    private static func repairMarkdown(
        markdown: String,
        targetStructure: DocumentStructure,
        currentStructure: DocumentStructure
    ) -> String {
        var repaired = markdown

        // Repair heading levels
        var headingIndex = 0
        let lines = repaired.components(separatedBy: .newlines)
        var repairedLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") && headingIndex < targetStructure.headings.count {
                let targetLevel = targetStructure.headings[headingIndex].level
                let currentLevel = trimmed.prefix(while: { $0 == "#" }).count

                if currentLevel != targetLevel {
                    let text = trimmed.dropFirst(currentLevel).trimmingCharacters(in: .whitespaces)
                    let correctedLine = String(repeating: "#", count: targetLevel) + " " + text
                    repairedLines.append(correctedLine)
                    headingIndex += 1
                } else {
                    repairedLines.append(line)
                    headingIndex += 1
                }
            } else {
                repairedLines.append(line)
            }
        }

        repaired = repairedLines.joined(separator: "\n")

        // Ensure consistent spacing between sections
        let sectionPattern = try? NSRegularExpression(pattern: "^(#{1,6})\\s", options: .anchorsMatchLines)
        repaired = sectionPattern?.stringByReplacingMatches(
            in: repaired,
            options: [],
            range: NSRange(repaired.startIndex..., in: repaired),
            withTemplate: "\n\n$1 "
        ) ?? repaired

        return repaired.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Metrics

    private static func calculateRetention(
        original: DocumentStructure,
        converted: DocumentStructure
    ) -> Double {
        let totalOriginal = original.headings.count +
                           original.tables.count * 2 +
                           original.lists.count

        guard totalOriginal > 0 else { return 1.0 }

        let totalConverted = converted.headings.count +
                            converted.tables.count * 2 +
                            converted.lists.count

        return Double(totalConverted) / Double(totalOriginal)
    }
}
