import AppKit
import SwiftUI

struct ReportProblemView: View {
    @EnvironmentObject private var conversion: ConversionQueue

    @State private var category: SupportReportCategory = .conversionFailure
    @State private var summary = ""
    @State private var includeDiagnostics = true
    @State private var copied = false
    @State private var diagnosticSnapshot = DiagnosticsService.shared.makeSnapshot()
    @State private var logExport = DiagnosticsService.shared.recentLogExport()

    private let windowSize: AppTheme.WindowSize = .thin

    private var preview: SupportReportPreview {
        SupportReporter.makePreview(
            category: category,
            summary: summary,
            includeDiagnostics: includeDiagnostics,
            snapshot: diagnosticSnapshot,
            logExport: logExport
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Picker("Problem type:", selection: $category) {
                ForEach(SupportReportCategory.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("What happened?")
                    .font(.headline)
                TextEditor(text: $summary)
                    .font(.body)
                    .frame(minHeight: 86)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
            }

            Toggle("Include redacted diagnostics and recent Upmarket logs", isOn: $includeDiagnostics)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Preview")
                    .font(.headline)
                TextEditor(text: .constant(preview.body))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
            }

            HStack {
                if copied {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy Report") {
                    FileAccessService.shared.copySupportReport(preview.body)
                    copied = true
                }
                Button("Email Support") {
                    if let url = SupportReporter.mailURL(for: preview) {
                        FileAccessService.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(windowSize.contentPadding)
        .frame(width: 620, height: windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: includeDiagnostics) { enabled in
            if enabled {
                refreshDiagnostics()
            }
        }
        .onAppear {
            refreshDiagnostics()
        }
    }

    private func refreshDiagnostics() {
        diagnosticSnapshot = conversion.diagnosticSnapshotForLastFailedJob()
        logExport = DiagnosticsService.shared.recentLogExport()
    }
}

#Preview {
    ReportProblemView()
        .environmentObject(ConversionQueue.shared)
}
