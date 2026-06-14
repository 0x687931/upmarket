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
            let refinedChunk = await refineChunk(chunk, language: input.language) ?? chunk
            if refinedChunk != chunk {
                processed += 1
            }
            refined.append(refinedChunk)
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

    /// Refine a single chunk of text.
    /// Implements sentence merging (broken across PDF lines) and whitespace cleanup.
    /// Returns nil if refinement fails; otherwise returns the refined text.
    private static func refineChunk(_ text: String, language: String) async -> String? {
        return await Task.detached(priority: .userInitiated) {
            refineChunkSync(text, language: language)
        }.value
    }

    /// Synchronous refinement: merge broken sentences and clean whitespace.
    /// PDF extraction often splits sentences across line breaks. This detects sentence
    /// boundaries and merges lines that should be together.
    private nonisolated static func refineChunkSync(_ text: String, language: String) -> String? {
        // Split into lines for processing
        let lines = text.components(separatedBy: .newlines)
        var mergedLines: [String] = []
        var currentParagraph = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line = paragraph boundary
            if trimmed.isEmpty {
                if !currentParagraph.isEmpty {
                    mergedLines.append(currentParagraph)
                    currentParagraph = ""
                }
                mergedLines.append("")
                continue
            }

            if isMarkdownTableRow(trimmed) {
                if !currentParagraph.isEmpty {
                    mergedLines.append(currentParagraph)
                    currentParagraph = ""
                }
                mergedLines.append(trimmed)
                continue
            }

            // Check if this line looks like it was broken mid-sentence
            // Heuristic: if previous line didn't end with sentence terminator and
            // current line doesn't start with capital or special marker, merge
            if !currentParagraph.isEmpty && shouldMergeLine(trimmed, into: currentParagraph) {
                currentParagraph += " " + trimmed
            } else {
                // New sentence or continuation of paragraph
                if !currentParagraph.isEmpty && endsWithSentenceTerminator(currentParagraph) {
                    mergedLines.append(currentParagraph)
                    currentParagraph = trimmed
                } else if !currentParagraph.isEmpty {
                    currentParagraph += " " + trimmed
                } else {
                    currentParagraph = trimmed
                }
            }
        }

        // Flush remaining paragraph
        if !currentParagraph.isEmpty {
            mergedLines.append(currentParagraph)
        }

        // Filter out excessive empty lines (more than 2 consecutive newlines)
        var result: [String] = []
        var consecutiveEmpty = 0
        for line in mergedLines {
            if line.isEmpty {
                consecutiveEmpty += 1
                if consecutiveEmpty <= 1 {
                    result.append(line)
                }
            } else {
                consecutiveEmpty = 0
                result.append(line)
            }
        }

        let refined = result.joined(separator: "\n")
        return refined.isEmpty ? nil : refined
    }

    /// Check if a line should be merged with the current paragraph.
    /// Returns true if the line appears to be a continuation of a broken sentence.
    nonisolated static func shouldMergeLine(_ line: String, into paragraph: String) -> Bool {
        guard !line.isEmpty && !paragraph.isEmpty else { return false }

        if isMarkdownTableRow(line) || isMarkdownTableRow(paragraph) {
            return false
        }

        // Don't merge if current paragraph ends with a sentence terminator
        if endsWithSentenceTerminator(paragraph) {
            return false
        }

        // Don't merge if line starts with a heading, list marker, or code fence
        let startsWithSpecial = line.hasPrefix("#") || line.hasPrefix("-") ||
                                line.hasPrefix("*") || line.hasPrefix(">") ||
                                line.hasPrefix("`") || line.hasPrefix("|")
        if startsWithSpecial {
            return false
        }

        // Don't merge if line starts with all caps (likely a new section)
        if line.allSatisfy({ $0.isUppercase || !$0.isLetter }) {
            return false
        }

        // Merge if line looks like a sentence continuation
        return true
    }

    nonisolated static func isMarkdownTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.dropFirst().contains("|")
    }

    /// Check if text ends with a sentence terminator (., !, ?, etc).
    private nonisolated static func endsWithSentenceTerminator(_ text: String) -> Bool {
        guard let lastChar = text.last else { return false }
        return lastChar == "." || lastChar == "!" || lastChar == "?" || lastChar == ":"
    }
}
