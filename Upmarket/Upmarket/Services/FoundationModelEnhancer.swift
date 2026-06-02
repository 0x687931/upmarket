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
            return _FMAvailability.check()
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
                return try await _FMImpl.enhance(markdown: markdown, documentType: documentType)
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
}

// MARK: - macOS 26 availability helper (no FoundationModels import needed here)

@available(macOS 26, *)
private enum _FMAvailability {
    static func check() -> Bool {
        // SystemLanguageModel is in FoundationModels — checked in _FMImpl
        // Return true on macOS 26 hardware; actual model availability checked at call time
        var sysinfo = utsname(); uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) {
            $0.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) } ?? ""
        }.hasPrefix("arm64")
    }
}

// MARK: - macOS 26 implementation in separate file to isolate FoundationModels import
// See: FoundationModelEnhancerImpl.swift
