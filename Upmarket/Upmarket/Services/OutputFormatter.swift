import Foundation

struct FormattedConversionOutput: Equatable {
    let text: String
    let fileExtension: String
}

struct ConversionMetadata: Codable, Equatable {
    let title: String
    let source: String?
    let converted: String
    let language: String
    let type: String
    let pipeline: String
    let pages: Int
    let wordCount: Int

    enum CodingKeys: String, CodingKey {
        case title
        case source
        case converted
        case language
        case type
        case pipeline
        case pages
        case wordCount = "word_count"
    }
}

enum OutputFormatter {
    static func format(
        _ output: ConversionOutput,
        sourceDisplayName: String?,
        mode: OutputMode = .markdown,
        convertedAt: Date = Date()
    ) -> FormattedConversionOutput {
        let metadata = makeMetadata(
            title: output.title,
            markdown: output.markdown,
            sourceDisplayName: sourceDisplayName,
            convertedAt: convertedAt,
            pipeline: output.pipeline,
            pages: output.pages
        )
        return format(markdown: output.markdown, metadata: metadata, mode: mode)
    }

    static func format(
        record: ConversionHistoryRecord,
        mode: OutputMode = .markdown
    ) -> FormattedConversionOutput {
        let metadata = makeMetadata(
            title: record.title,
            markdown: record.markdown,
            sourceDisplayName: record.sourceDisplayName,
            convertedAt: record.createdAt,
            pipeline: record.pipeline,
            pages: record.pages
        )
        return format(markdown: record.markdown, metadata: metadata, mode: mode)
    }

    private static func format(
        markdown: String,
        metadata: ConversionMetadata,
        mode: OutputMode
    ) -> FormattedConversionOutput {
        switch mode {
        case .markdown:
            return FormattedConversionOutput(text: markdown, fileExtension: "md")
        case .markdownWithFrontmatter:
            return FormattedConversionOutput(
                text: frontmatter(metadata: metadata) + "\n" + markdown,
                fileExtension: "md"
            )
        case .json:
            return FormattedConversionOutput(
                text: json(markdown: markdown, metadata: metadata),
                fileExtension: "json"
            )
        }
    }

    private static func makeMetadata(
        title: String,
        markdown: String,
        sourceDisplayName: String?,
        convertedAt: Date,
        pipeline: Pipeline,
        pages: Int
    ) -> ConversionMetadata {
        let intelligence = DocumentIntelligence.extractMetadata(from: markdown)
        return ConversionMetadata(
            title: title,
            source: sourceDisplayName,
            converted: isoString(from: convertedAt),
            language: intelligence.language,
            type: intelligence.documentType.rawValue,
            pipeline: pipeline.rawValue,
            pages: pages,
            wordCount: countWords(in: markdown)
        )
    }

    private static func frontmatter(metadata: ConversionMetadata) -> String {
        var lines = ["---"]
        lines.append("title: \(yamlString(metadata.title))")
        lines.append("source: \(yamlString(metadata.source ?? ""))")
        lines.append("converted: \(yamlString(metadata.converted))")
        lines.append("language: \(yamlString(metadata.language))")
        lines.append("type: \(yamlString(metadata.type))")
        lines.append("pipeline: \(yamlString(metadata.pipeline))")
        lines.append("pages: \(metadata.pages)")
        lines.append("word_count: \(metadata.wordCount)")
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func json(markdown: String, metadata: ConversionMetadata) -> String {
        struct Payload: Codable {
            let title: String
            let markdown: String
            let metadata: ConversionMetadata
        }

        let payload = Payload(title: metadata.title, markdown: markdown, metadata: metadata)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"title":"","markdown":"","metadata":{}}"#
        }
        return text
    }

    private static func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func countWords(in markdown: String) -> Int {
        markdown
            .split { $0.isWhitespace }
            .filter { token in token.contains { $0.isLetter || $0.isNumber } }
            .count
    }
}

@MainActor
final class OutputPreference {
    static let shared = OutputPreference()

    private static let defaultsKey = "upmarket.outputMode"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var mode: OutputMode {
        get {
            guard let raw = userDefaults.string(forKey: Self.defaultsKey),
                  let mode = OutputMode(rawValue: raw) else {
                return .markdown
            }
            return mode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Self.defaultsKey)
        }
    }
}
