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

    private let windowSize: AppTheme.WindowSize = .modal

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
            problemTypeCard
            summaryCard
            diagnosticsCard
            previewCard
            actionsRow
        }
        .padding(windowSize.contentPadding)
        .frame(width: windowSize.width, height: windowSize.height)
        .background(AppTheme.Colour.background)
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

    private var problemTypeCard: some View {
        AppSectionCard(title: "Problem Type") {
            Picker("Problem type:", selection: $category) {
                ForEach(SupportReportCategory.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    private var summaryCard: some View {
        AppSectionCard(title: "What happened?") {
            TextEditor(text: $summary)
                .font(.body)
                .frame(minHeight: 86)
                .appTextEditorChrome()
        }
    }

    private var diagnosticsCard: some View {
        AppSectionCard {
            Toggle("Include redacted diagnostics and recent Upmarket logs", isOn: $includeDiagnostics)
        }
    }

    private var previewCard: some View {
        AppSectionCard(title: "Preview") {
            TextEditor(text: .constant(preview.body))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 220)
                .appTextEditorChrome()
        }
    }

    private var actionsRow: some View {
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
            .buttonStyle(AppBorderedButtonStyle())
            Button("Email Support") {
                if let url = SupportReporter.mailURL(for: preview) {
                    FileAccessService.shared.open(url)
                }
            }
            .buttonStyle(AppProminentButtonStyle())
        }
    }
}

#Preview {
    ReportProblemView()
        .environmentObject(ConversionQueue.shared)
}
