import Foundation

/// Validates conversion output against input to detect data loss, corruption, or extraction failures.
/// Does not gate conversions (output is still usable) but logs warnings for debugging.
struct ConversionValidator {

    struct ValidationResult {
        let passed: Bool
        let warnings: [String]
        let metrics: Metrics

        struct Metrics {
            let inputWordCount: Int
            let outputWordCount: Int
            let retentionRatio: Double  // output words / input words
            let inputCharCount: Int
            let outputCharCount: Int
            let tablesDetected: Int
            let listsDetected: Int
            let pagesProcessed: Int
        }
    }

    /// Validate conversion output against original input.
    /// Returns warnings if quality concerns detected, but conversion is still usable.
    static func validate(
        originalMarkdown: String,
        convertedMarkdown: String,
        tablesDetected: Int,
        listsDetected: Int,
        pagesProcessed: Int
    ) -> ValidationResult {
        var warnings: [String] = []

        // Basic metrics
        let inputWords = countWords(originalMarkdown)
        let outputWords = countWords(convertedMarkdown)
        let retentionRatio = inputWords > 0 ? Double(outputWords) / Double(inputWords) : 1.0
        let inputChars = originalMarkdown.count
        let outputChars = convertedMarkdown.count

        // Check for major data loss
        if retentionRatio < 0.7 {
            warnings.append("Output retained only \(Int(retentionRatio * 100))% of input words (expected > 70%)")
        }

        // Check if output is suspiciously small
        if outputChars < 100 && inputChars > 1000 {
            warnings.append("Output is very short (\(outputChars) chars) compared to input (\(inputChars) chars)")
        }

        // Check for obvious extraction failures
        if outputWords == 0 && inputWords > 0 {
            warnings.append("Output contains no text despite input having \(inputWords) words")
        }

        // Check if output has reasonable structure for input size
        let expectedTables = estimateTablesInDocument(originalMarkdown)
        let expectedLists = estimateListsInDocument(originalMarkdown)

        if tablesDetected == 0 && expectedTables > 0 {
            warnings.append("Expected ~\(expectedTables) tables but found 0")
        }

        if listsDetected == 0 && expectedLists > 0 {
            warnings.append("Expected ~\(expectedLists) lists but found 0")
        }

        // Sanity check: output shouldn't be wildly larger than input
        if outputChars > inputChars * 3 {
            warnings.append("Output is \(outputChars / inputChars)x larger than input (possible duplication)")
        }

        let metrics = ValidationResult.Metrics(
            inputWordCount: inputWords,
            outputWordCount: outputWords,
            retentionRatio: retentionRatio,
            inputCharCount: inputChars,
            outputCharCount: outputChars,
            tablesDetected: tablesDetected,
            listsDetected: listsDetected,
            pagesProcessed: pagesProcessed
        )

        return ValidationResult(
            passed: warnings.isEmpty,
            warnings: warnings,
            metrics: metrics
        )
    }

    // MARK: - Private Helpers

    private static func countWords(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }

    /// Estimate number of tables in document by looking for Markdown table markers.
    private static func estimateTablesInDocument(_ markdown: String) -> Int {
        let tableMarkers = markdown.components(separatedBy: "|").count / 5
        return max(0, tableMarkers)
    }

    /// Estimate number of lists by looking for list markers.
    private static func estimateListsInDocument(_ markdown: String) -> Int {
        let lines = markdown.components(separatedBy: .newlines)
        var listCount = 0
        var inList = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList {
                    listCount += 1
                    inList = true
                }
            } else if !trimmed.isEmpty {
                inList = false
            }
        }
        return listCount
    }
}
