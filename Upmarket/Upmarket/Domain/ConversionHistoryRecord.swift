import Foundation

struct ConversionHistoryRecord: Codable, Equatable, Identifiable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    let createdAt: Date
    let sourceDisplayName: String
    let sourceExtension: String
    let title: String
    let format: String
    let pages: Int
    let wordCount: Int
    let pipeline: Pipeline
    let selectedPathway: ConversionPathway
    let markdown: String

    init(
        version: Int = Self.currentVersion,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceDisplayName: String,
        sourceExtension: String,
        title: String,
        format: String,
        pages: Int,
        wordCount: Int,
        pipeline: Pipeline,
        selectedPathway: ConversionPathway,
        markdown: String
    ) {
        self.version = version
        self.id = id
        self.createdAt = createdAt
        self.sourceDisplayName = sourceDisplayName
        self.sourceExtension = sourceExtension
        self.title = title
        self.format = format
        self.pages = pages
        self.wordCount = wordCount
        self.pipeline = pipeline
        self.selectedPathway = selectedPathway
        self.markdown = markdown
    }

    init(job: ConversionJob, output: ConversionOutput, createdAt: Date = Date()) {
        self.init(
            createdAt: createdAt,
            sourceDisplayName: job.displayName ?? job.sourceURL.lastPathComponent,
            sourceExtension: job.ext,
            title: output.title,
            format: output.format,
            pages: output.pages,
            wordCount: Self.countWords(in: output.markdown),
            pipeline: output.pipeline,
            selectedPathway: output.selectedPathway,
            markdown: output.markdown
        )
    }

    var provenanceLabel: String {
        selectedPathway.displayPipeline.displayName
    }

    var contentSnippet: String {
        markdown
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .prefix(18)
            .joined(separator: " ")
    }

    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = [
            sourceDisplayName,
            sourceExtension,
            title,
            format,
            provenanceLabel,
            Self.searchDateString(from: createdAt),
            markdown
        ]
        .joined(separator: " ")
        .localizedCaseInsensitiveContains(trimmed)
        return haystack
    }

    private static func countWords(in markdown: String) -> Int {
        markdown
            .split { $0.isWhitespace }
            .filter { token in token.contains { $0.isLetter || $0.isNumber } }
            .count
    }

    private static func searchDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
