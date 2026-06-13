import Foundation

enum SupportReportCategory: String, CaseIterable, Identifiable {
    case conversionFailure = "Conversion failure"
    case crash = "App crash"
    case outputQuality = "Output quality"
    case performance = "Performance issue"
    case other = "Other"

    var id: String { rawValue }
}

struct SupportReportPreview: Equatable {
    let subject: String
    let body: String
}

enum SupportReporter {
    static func makePreview(
        category: SupportReportCategory,
        summary: String,
        includeDiagnostics: Bool,
        snapshot: DiagnosticSnapshot = Diagnostics.makeSnapshot(),
        logExport: String = Diagnostics.recentLogExport()
    ) -> SupportReportPreview {
        let cleanSummary = sanitizeUserText(summary)
        var sections = [
            "Upmarket Problem Report",
            "",
            "Category: \(category.rawValue)",
            "Summary:",
            cleanSummary.isEmpty ? "(not provided)" : cleanSummary,
            "",
            "Privacy:",
            "No source documents, extracted text, passwords, or full file paths are included by Upmarket."
        ]

        if includeDiagnostics {
            sections.append(contentsOf: [
                "",
                "Diagnostics:",
                diagnosticText(snapshot),
                "",
                "Recent Logs:",
                sanitizeUserText(logExport)
            ])
        } else {
            sections.append(contentsOf: [
                "",
                "Diagnostics: omitted by user"
            ])
        }

        return SupportReportPreview(
            subject: "Upmarket \(category.rawValue)",
            body: sections.joined(separator: "\n")
        )
    }

    static func mailURL(for preview: SupportReportPreview) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@upmarket.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: preview.subject),
            URLQueryItem(name: "body", value: preview.body)
        ]
        return components.url
    }

    private static func diagnosticText(_ snapshot: DiagnosticSnapshot) -> String {
        [
            "App Version: \(snapshot.appVersion)",
            "Build: \(snapshot.buildNumber)",
            "macOS: \(snapshot.macOSVersion)",
            "Hardware: \(snapshot.hardwareModel)",
            "Locale: \(snapshot.localeIdentifier)",
            "Correlation ID: \(snapshot.correlationID ?? "none")",
            "Last Stage: \(snapshot.lastConversionStage.map(Diagnostics.neutralStageName) ?? "none")",
            "Last Error: \(snapshot.lastErrorCode ?? "none")",
            "Plist: \(snapshot.plistStatus)",
            "Entitlements: \(snapshot.entitlementStatus)",
            "Models: \(snapshot.modelManifestStatus)"
        ].joined(separator: "\n")
    }

    private static func sanitizeUserText(_ text: String) -> String {
        var sanitized = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)(?:~|/Users|/Volumes|/private/var)/[^\s,;:)"]+"#,
            with: "[redacted path]",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)\b[^\s/]+\.(pdf|docx|doc|pptx|ppt|xlsx|xls|html|htm|md|txt|png|jpg|jpeg|gif|tiff|csv|json|xml|zip|mp3|m4a|wav|aiff|ogg)\b"#,
            with: "[redacted file]",
            options: .regularExpression
        )
        let toolkitPattern = [
            "py" + "thonBridge",
            "py" + "thon",
            "doc" + "ling",
            "pdf" + "ium",
            "py" + "thonkit",
            "py" + "mupdf",
            "mark" + "itdown"
        ]
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)\b(\#(toolkitPattern))\b"#,
            with: "conversion runtime",
            options: .regularExpression
        )
        return sanitized
    }
}
