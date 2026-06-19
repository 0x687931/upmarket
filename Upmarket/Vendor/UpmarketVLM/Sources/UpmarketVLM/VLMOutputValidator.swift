import Foundation

/// Rejects obviously incomplete or runaway model output before it reaches a conversion result.
///
/// This is intentionally conservative: it does not grade OCR accuracy. It only catches failure
/// modes that should always trigger the app's existing OCR fallback.
public enum VLMOutputValidator {
    public enum Failure: Error, Equatable {
        case empty
        case excessiveLength
        case repeatedLine
        case repeatedPhrase
    }

    public static func validate(_ output: String) throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count <= 3_500, trimmed.utf8.count <= 120_000 else {
            throw Failure.excessiveLength
        }

        var lineCounts: [String: Int] = [:]
        for line in trimmed.components(separatedBy: .newlines) {
            let normalized = normalize(line)
            guard normalized.count >= 8 else { continue }
            lineCounts[normalized, default: 0] += 1
            if lineCounts[normalized, default: 0] >= 6 {
                throw Failure.repeatedLine
            }
        }

        // Alternating or slightly reformatted loops can evade exact-line counting. Twelve-word
        // shingles retain enough context to avoid rejecting ordinary repeated labels and headers.
        if words.count >= 12 {
            var phraseCounts: [String: Int] = [:]
            for start in 0...(words.count - 12) {
                let phrase = words[start..<(start + 12)]
                    .map { $0.lowercased() }
                    .joined(separator: " ")
                phraseCounts[phrase, default: 0] += 1
                if phraseCounts[phrase, default: 0] >= 6 {
                    throw Failure.repeatedPhrase
                }
            }
        }

        return trimmed
    }

    private static func normalize(_ line: String) -> String {
        line.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
