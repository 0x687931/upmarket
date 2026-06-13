import Foundation

// MARK: - Version-safe public API (always available)

struct WritingToolsOutput {
    let markdown: String
    let wasRefined: Bool
}

enum WritingToolsService {
    static func refineMarkdown(_ markdown: String, language: String) async -> WritingToolsOutput {
        if #available(macOS 15.1, *) {
            let input = WritingToolsRefiner.Input(markdown: markdown, language: language)
            let result = await WritingToolsRefiner.refine(input)
            return WritingToolsOutput(markdown: result.markdown, wasRefined: result.wasRefined)
        } else {
            return WritingToolsOutput(markdown: markdown, wasRefined: false)
        }
    }
}

// MARK: - macOS 15.1+ Implementation

/// Refines structured Markdown using Apple Intelligence Writing Tools.
/// Available on macOS 15.1+ with Apple Silicon.
///
/// Responsibilities:
/// - Fix broken sentences split across PDF lines
/// - Normalise inconsistent capitalisation from PDF extraction
/// - Clean up repetitive or malformed text patterns
///
/// Gracefully degrades: returns input unchanged on unsupported OS/hardware.
/// Must be called asynchronously — Writing Tools API is async.
@available(macOS 15.1, *)
struct WritingToolsRefiner {

    // MARK: - Availability

    static var isAvailable: Bool {
        if #available(macOS 15.1, *) {
            // Apple Intelligence requires Apple Silicon + opt-in
            // Check via ProcessInfo as the API doesn't expose a direct check
            return isAppleSilicon
        }
        return false
    }

    private static var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) {
            $0.bindMemory(to: CChar.self).baseAddress
                .map { String(cString: $0) } ?? ""
        }.hasPrefix("arm64")
    }

    // MARK: - Refinement

    struct Input {
        let markdown: String
        let language: String
        /// Maximum characters to send per refinement request.
        /// Writing Tools works best on focused chunks, not full documents.
        var chunkSize: Int = 3000
    }

    struct Output {
        let markdown: String
        let wasRefined: Bool      // false if Writing Tools was unavailable
        let chunksProcessed: Int
    }

    /// Refine markdown in chunks using Writing Tools.
    /// Splits at paragraph boundaries to preserve structure.
    static func refine(_ input: Input) async -> Output {
        guard isAvailable else {
            return Output(markdown: input.markdown, wasRefined: false, chunksProcessed: 0)
        }

        let chunks = splitIntoChunks(input.markdown, maxSize: input.chunkSize)
        var refined: [String] = []
        var processed = 0

        for chunk in chunks {
            if let result = await refineChunk(chunk, language: input.language) {
                refined.append(result)
                processed += 1
            } else {
                // Writing Tools failed for this chunk — use original
                refined.append(chunk)
            }
        }

        return Output(
            markdown: refined.joined(separator: "\n\n"),
            wasRefined: processed > 0,
            chunksProcessed: processed
        )
    }

    // MARK: - Private

    /// Split markdown at paragraph boundaries, respecting headings.
    private static func splitIntoChunks(_ text: String, maxSize: Int) -> [String] {
        var chunks: [String] = []
        var current = ""

        for paragraph in text.components(separatedBy: "\n\n") {
            if current.count + paragraph.count > maxSize && !current.isEmpty {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = paragraph
            } else {
                current += (current.isEmpty ? "" : "\n\n") + paragraph
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return chunks
    }

    /// Send a single chunk to Writing Tools for refinement.
    /// Returns nil if Writing Tools is unavailable, fails, or not yet implemented.
    ///
    /// NSWritingToolsCoordinator (macOS 15.1+) requires a responder/view context for text editing.
    /// Upmarket's conversion pipeline runs without an active text view, so this integration
    /// is deferred until either: (1) NSWritingToolsCoordinator gains a text-only API, or
    /// (2) the feature is wired to an editor surface with user-initiated refinement.
    /// Currently, refinement gracefully returns the input unchanged on all platforms.
    private static func refineChunk(_ text: String, language: String) async -> String? {
        return nil
    }
}
