import Foundation
import OSLog

/// Enhances document Markdown using Apple's Foundation Models framework.
/// On-device ~3B parameter model. Requires macOS 26+ with Apple Intelligence enabled.
/// Gracefully degrades on unsupported platforms.
struct FoundationModelEnhancer {

    struct DocumentEnhancement: Codable, Equatable {
        var extractedTitle: String?
        var extractedAuthors: [String]
        var sectionSummaries: [SectionSummary]
        var refinedMarkdown: String
        var wasEnhanced: Bool
    }

    struct SectionSummary: Codable, Equatable {
        let heading: String
        let summary: String
        let keyPoints: [String]
    }

    static var isAvailable: Bool {
        if #available(macOS 26, *) {
            var sysinfo = utsname()
            uname(&sysinfo)
            let arch = withUnsafeBytes(of: &sysinfo.machine) {
                $0.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) } ?? ""
            }
            return arch.hasPrefix("arm64")
        }
        return false
    }

    static func enhance(markdown: String, documentType: String = "general") async -> DocumentEnhancement {
        if AppRuntime.isRunningTests {
            return DocumentEnhancement(
                extractedTitle: titleFallback(from: markdown),
                extractedAuthors: [], sectionSummaries: [],
                refinedMarkdown: markdown, wasEnhanced: false
            )
        }

        if #available(macOS 26, *) {
            do {
                return try await enhanceWithFoundationModels(markdown: markdown, documentType: documentType)
            } catch {
                AppLog.featureFlags.error("Foundation model enhancement failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        return DocumentEnhancement(
            extractedTitle: titleFallback(from: markdown),
            extractedAuthors: [], sectionSummaries: [],
            refinedMarkdown: markdown, wasEnhanced: false
        )
    }

    static func titleFallback(from markdown: String) -> String? {
        for line in markdown.components(separatedBy: "\n").prefix(10) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") { return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    // MARK: - Private Implementation

    @available(macOS 26, *)
    private static func enhanceWithFoundationModels(
        markdown: String,
        documentType: String
    ) async throws -> DocumentEnhancement {
        // This implementation uses FoundationModels framework (macOS 26+ only)
        // The actual model calls would be made here via the FoundationModelsImpl module
        // For now, return unenhanced result as Foundation Models API is still in preview
        return DocumentEnhancement(
            extractedTitle: titleFallback(from: markdown),
            extractedAuthors: [],
            sectionSummaries: [],
            refinedMarkdown: markdown,
            wasEnhanced: false
        )
    }

    private struct Section { let heading: String; let content: String }

    private static func extractSections(from markdown: String) -> [Section] {
        var sections: [Section] = []
        var heading = ""; var lines: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if !lines.isEmpty { sections.append(Section(heading: heading, content: lines.joined(separator: "\n"))) }
                heading = String(line.dropFirst(3)); lines = []
            } else { lines.append(line) }
        }
        if !lines.isEmpty { sections.append(Section(heading: heading, content: lines.joined(separator: "\n"))) }
        return sections
    }
}
