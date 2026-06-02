import Foundation
import FoundationModels

// MARK: - macOS 26 Implementation

@available(macOS 26, *)
enum _FMImpl {

    // @Generable — compile-time JSON schema, type-safe guided generation
    @Generable(description: "Structured metadata extracted from a document")
    struct DocumentMetadata {
        @Guide(description: "The main title of the document") var title: String
        @Guide(description: "Author names found in the document") var authors: [String]
        @Guide(description: "One sentence describing what this document is about") var abstract: String
        @Guide(description: "Type: academic, business, technical, legal, or general") var documentType: String
        @Guide(description: "Up to 5 key topics covered") var keyTopics: [String]
    }

    @Generable(description: "A concise summary of one document section")
    struct SectionSummary {
        @Guide(description: "The section heading") var heading: String
        @Guide(description: "One sentence summary of this section") var summary: String
        @Guide(description: "Up to 3 key points from this section") var keyPoints: [String]
    }

    static func enhance(
        markdown: String,
        documentType: String
    ) async throws -> FoundationModelEnhancer.DocumentEnhancement {

        guard SystemLanguageModel.default.isAvailable else {
            return FoundationModelEnhancer.DocumentEnhancement(
                extractedTitle: FoundationModelEnhancer.titleFallback(from: markdown),
                extractedAuthors: [], sectionSummaries: [],
                refinedMarkdown: markdown, wasEnhanced: false
            )
        }

        // Session 1: extract metadata from document header/abstract
        let metaSession = LanguageModelSession(
            instructions: "You analyse documents and extract structured metadata accurately."
        )
        let sample = String(markdown.prefix(3000))
        let metaResponse = try await metaSession.respond(
            to: "Extract structured metadata from this document:\n\n\(sample)",
            generating: DocumentMetadata.self
        )
        let meta = metaResponse.content

        // Session 2: summarise major sections (H2 headings)
        let sections = extractSections(from: markdown)
        var summaries: [FoundationModelEnhancer.SectionSummary] = []

        for section in sections.prefix(5) {
            let sSession = LanguageModelSession(
                instructions: "Summarise document sections in one sentence with key points."
            )
            let response = try await sSession.respond(
                to: "Summarise this section:\n\n\(section.content.prefix(1500))",
                generating: SectionSummary.self
            )
            let s = response.content
            summaries.append(FoundationModelEnhancer.SectionSummary(
                heading: s.heading.isEmpty ? section.heading : s.heading,
                summary: s.summary,
                keyPoints: s.keyPoints
            ))
        }

        return FoundationModelEnhancer.DocumentEnhancement(
            extractedTitle: meta.title.isEmpty ? nil : meta.title,
            extractedAuthors: meta.authors,
            sectionSummaries: summaries,
            refinedMarkdown: markdown,   // grammar refinement is Writing Tools' job
            wasEnhanced: true
        )
    }

    // MARK: - Section extraction

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
