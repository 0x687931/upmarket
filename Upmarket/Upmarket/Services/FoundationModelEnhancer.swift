import Foundation

/// Enhances document Markdown using Apple's Foundation Models framework.
/// Available on macOS 15.1+ with Apple Silicon (on-device ~3B parameter model).
/// Provides: structured metadata extraction, section summarisation, grammar refinement.
///
/// All inference is on-device — no data leaves the Mac.
/// Gracefully degrades to identity transform on unsupported platforms.

// MARK: - Availability Guard

struct FoundationModelEnhancer {

    static var isAvailable: Bool {
        if #available(macOS 15.1, *) {
            return FoundationModelEnhancerImpl.isAvailable
        }
        return false
    }

    // MARK: - Output

    struct DocumentEnhancement {
        var extractedTitle: String?
        var extractedAuthors: [String]
        var sectionSummaries: [SectionSummary]
        var refinedMarkdown: String       // grammar-corrected, improved
        var wasEnhanced: Bool
    }

    struct SectionSummary {
        let heading: String
        let summary: String              // 1-2 sentence TLDR
        let keyPoints: [String]
    }

    // MARK: - Public API

    static func enhance(markdown: String, documentType: String = "general") async -> DocumentEnhancement {
        if #available(macOS 15.1, *) {
            return await FoundationModelEnhancerImpl.enhance(
                markdown: markdown,
                documentType: documentType
            )
        }
        return DocumentEnhancement(
            extractedTitle: nil,
            extractedAuthors: [],
            sectionSummaries: [],
            refinedMarkdown: markdown,
            wasEnhanced: false
        )
    }
}

// MARK: - Implementation (macOS 15.1+)

@available(macOS 15.1, *)
private struct FoundationModelEnhancerImpl {

    static var isAvailable: Bool {
        // Foundation Models requires Apple Silicon
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) {
            $0.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) } ?? ""
        }
        return machine.hasPrefix("arm64")
    }

    static func enhance(markdown: String, documentType: String) async -> FoundationModelEnhancer.DocumentEnhancement {
        // Foundation Models framework is accessed via FoundationModels.ModelSession
        // The @Generable macro generates type-safe extraction structs at compile time.
        //
        // Full implementation requires:
        //   import FoundationModels
        //   let session = ModelSession()
        //
        // Currently stubbed — FoundationModels framework availability needs Xcode 26+
        // and a macOS 26 SDK. Wire up when SDK is available.
        //
        // Planned operations:
        //   1. extractMetadata(markdown) → @Generable DocumentMetadata
        //   2. summariseSections(markdown) → [@Generable SectionSummary]
        //   3. refineGrammar(chunk) → String (per 3000-char chunk)
        //
        // See: WWDC2025 Session 286 "Meet the Foundation Models framework"
        //      WWDC2025 Session 301 "Deep dive into the Foundation Models framework"

        return FoundationModelEnhancer.DocumentEnhancement(
            extractedTitle: extractTitleHeuristic(from: markdown),
            extractedAuthors: [],
            sectionSummaries: [],
            refinedMarkdown: markdown,
            wasEnhanced: false   // will be true once ModelSession is wired
        )
    }

    // Temporary heuristic title extraction until @Generable is wired
    private static func extractTitleHeuristic(from markdown: String) -> String? {
        for line in markdown.components(separatedBy: "\n").prefix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

// MARK: - @Generable Structs (ready for FoundationModels import)
//
// These structs are designed to work with the @Generable macro from FoundationModels.
// Uncomment and add `import FoundationModels` + `@Generable` annotation when SDK available.
//
// @Generable
struct GenerableDocumentMetadata: Codable {
    let title: String
    let authors: [String]
    let abstract: String
    let documentType: String    // "academic" | "business" | "technical" | "legal" | "general"
    let keyTopics: [String]
    let language: String
}

// @Generable
struct GenerableSectionSummary: Codable {
    let heading: String
    let oneSentenceSummary: String
    let keyPoints: [String]
    let importance: Int          // 1-5, where 5 = most important
}

// @Generable
struct GenerableDocumentOutline: Codable {
    let title: String
    let sections: [GenerableSectionSummary]
    let overallSummary: String
    let targetAudience: String
}
