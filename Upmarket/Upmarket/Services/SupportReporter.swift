import Foundation

enum SupportReportCategory: String, CaseIterable, Identifiable {
    case crash = "Crash"
    case conversionEngine = "Conversion engine crash or stall"
    case stalledConversion = "Stalled conversion"
    case conversionFailure = "Conversion failure"
    case enhancedConversionDownload = "Enhanced conversion download issue"
    case purchaseIssue = "Purchase or payment issue"
    case appUpdateIssue = "App update issue"
    case unexpectedFeatureBehavior = "Unexpected feature behavior"
    case uiAccessibility = "UI/accessibility bug"

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
        snapshot: DiagnosticSnapshot = DiagnosticsService.shared.makeSnapshot(),
        logExport: String = DiagnosticsService.shared.recentLogExport()
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
                logExport
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
            "Last Stage: \(snapshot.lastConversionStage ?? "none")",
            "Last Error: \(snapshot.lastErrorCode ?? "none")",
            "Plist: \(snapshot.plistStatus)",
            "Entitlements: \(snapshot.entitlementStatus)",
            "Models: \(snapshot.modelManifestStatus)"
        ].joined(separator: "\n")
    }

    private static func sanitizeUserText(_ text: String) -> String {
        text
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            .replacingOccurrences(
                of: #"/Users/[^/\s]+"#,
                with: "/Users/[redacted]",
                options: .regularExpression
            )
    }
}
