import AppKit
import SwiftUI

struct ReportProblemView: View {
    @State private var category: SupportReportCategory = .conversionFailure
    @State private var summary = ""
    @State private var includeDiagnostics = true
    @State private var copied = false
    @State private var diagnosticSnapshot = Diagnostics.makeSnapshot()
    @State private var logExport = Diagnostics.recentLogExport()

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
        VStack(alignment: .leading, spacing: 14) {
            Picker("Problem type:", selection: $category) {
                ForEach(SupportReportCategory.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("What happened?")
                    .font(.headline)
                TextEditor(text: $summary)
                    .font(.body)
                    .frame(minHeight: 86)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
            }

            Toggle("Include redacted diagnostics and recent Upmarket logs", isOn: $includeDiagnostics)

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.headline)
                TextEditor(text: .constant(preview.body))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
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
        .padding(20)
        .frame(width: 620, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: includeDiagnostics) { enabled in
            if enabled {
                refreshDiagnostics()
            }
        }
    }

    private func refreshDiagnostics() {
        diagnosticSnapshot = Diagnostics.makeSnapshot()
        logExport = Diagnostics.recentLogExport()
    }
}

#Preview {
    ReportProblemView()
}
