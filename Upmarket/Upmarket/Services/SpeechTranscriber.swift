import Foundation
import Speech
import AVFoundation

/// On-device audio transcription using Apple's Speech framework.
/// Requires `requiresOnDeviceRecognition = true` — no data leaves the device.
/// Supports 10+ languages on-device, unlimited duration.
actor SpeechTranscriber {

    // MARK: - Output

    struct Result {
        let transcript: String
        let confidence: Float
        let language: String
        let durationSeconds: Double
        let segments: [Segment]
    }

    struct Segment {
        let text: String
        let timestamp: TimeInterval
        let confidence: Float
    }

    // MARK: - Availability

    static var isAvailable: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Check and request authorisation. Must be called before transcribe().
    static func requestAuthorisation() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Languages with confirmed on-device support (no network fallback needed).
    static var supportedOnDeviceLanguages: [String] {
        [
            "en-US", "en-GB", "en-AU",
            "fr-FR", "de-DE", "es-ES", "it-IT",
            "ja-JP", "ko-KR", "zh-Hans", "zh-Hant",
            "pt-BR", "nl-NL", "ru-RU",
        ]
    }

    // MARK: - Public API

    /// Transcribe an audio file to Markdown-formatted text.
    /// Returns structured Markdown with timestamps as optional section headers.
    func transcribe(audioURL: URL, language: String = "en-US", includeTimestamps: Bool = false) async throws -> Result {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.notAuthorised
        }

        let locale = Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.languageNotSupported(language)
        }

        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true      // never leaves device
        request.shouldReportPartialResults = false
        request.addsPunctuation = true                  // auto-punctuation

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }

                let segments = result.bestTranscription.segments.map { seg in
                    Segment(
                        text: seg.substring,
                        timestamp: seg.timestamp,
                        confidence: seg.confidence
                    )
                }

                let transcript = includeTimestamps
                    ? self.formatWithTimestamps(segments)
                    : result.bestTranscription.formattedString

                let avgConf = segments.isEmpty ? 0 :
                    segments.map(\.confidence).reduce(0, +) / Float(segments.count)

                let duration = result.bestTranscription.segments.last
                    .map { $0.timestamp + $0.duration } ?? 0

                continuation.resume(returning: Result(
                    transcript: transcript,
                    confidence: avgConf,
                    language: language,
                    durationSeconds: duration,
                    segments: segments
                ))
            }
        }
    }

    /// Convert transcription result to clean Markdown document.
    nonisolated func toMarkdown(_ result: Result) -> String {
        var lines: [String] = []

        // Header with metadata
        lines.append("## Transcript")
        lines.append("")
        lines.append("> Language: \(result.language)  ")
        lines.append("> Duration: \(formatDuration(result.durationSeconds))  ")
        lines.append("> Confidence: \(Int(result.confidence * 100))%")
        lines.append("")

        // Transcript body
        lines.append(result.transcript)

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func formatWithTimestamps(_ segments: [Segment]) -> String {
        // Group into ~30-second chunks with timestamp headers
        var chunks: [[Segment]] = []
        var current: [Segment] = []
        var chunkStart: TimeInterval = 0

        for seg in segments {
            if seg.timestamp - chunkStart > 30 && !current.isEmpty {
                chunks.append(current)
                current = []
                chunkStart = seg.timestamp
            }
            current.append(seg)
        }
        if !current.isEmpty { chunks.append(current) }

        return chunks.enumerated().map { i, chunk in
            let ts = chunk.first.map { formatTimestamp($0.timestamp) } ?? "0:00"
            let text = chunk.map(\.text).joined(separator: " ")
            return "**[\(ts)]** \(text)"
        }.joined(separator: "\n\n")
    }

    nonisolated private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    nonisolated private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }

    // MARK: - Errors

    enum TranscriptionError: LocalizedError {
        case notAuthorised
        case languageNotSupported(String)
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorised:
                return "Microphone access is needed to transcribe audio. Please enable it in System Settings."
            case .languageNotSupported(let lang):
                return "On-device transcription is not available for \(lang)."
            case .recognizerUnavailable:
                return "Speech recognition is temporarily unavailable."
            }
        }
    }
}
