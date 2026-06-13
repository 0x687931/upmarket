import AppKit
import SwiftUI

struct ReportProblemView: View {
    @EnvironmentObject private var conversion: ConversionQueue

    @State private var category: SupportReportCategory = .conversionFailure
    @State private var details = ""
    @State private var includeDiagnostics = true
    @State private var diagnosticSnapshot = DiagnosticsService.shared.makeSnapshot()
    @State private var logExport = DiagnosticsService.shared.recentLogExport()

    private var failedJob: ConversionJob? { conversion.lastFailedJob }

    private var preview: SupportReportPreview {
        SupportReporter.makePreview(
            category: category,
            summary: details,
            includeDiagnostics: includeDiagnostics,
            snapshot: diagnosticSnapshot,
            logExport: logExport
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let job = failedJob {
                contextStrip(job: job)
            }
            bodyContent
            footer
        }
        .frame(width: AppTheme.WindowSize.modal.width)
        .fixedSize(horizontal: true, vertical: true)
        .background(AppTheme.Colour.background)
        .onChange(of: includeDiagnostics) { enabled in
            if enabled { refreshDiagnostics() }
        }
        .onAppear { refreshDiagnostics() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.Colour.sectionRed.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.Colour.sectionRed)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("Report a Problem")
                    .font(.title3.weight(.bold))
                Text("Help us improve by reporting what went wrong.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSApp.keyWindow?.performClose(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(AppPlainButtonStyle())
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Context strip

    private func contextStrip(job: ConversionJob) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Conversion of \(job.name).\(job.ext.lowercased()) failed")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(AppTheme.Colour.subtleFill)
        .overlay(Divider(), alignment: .top)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Body

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            categoryPicker
            detailsField
            logsToggle
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(icon: "list.bullet", text: "Issue Type")
            VStack(spacing: 8) {
                ForEach(SupportReportCategory.allCases) { cat in
                    categoryRow(cat)
                }
            }
        }
    }

    private func categoryRow(_ cat: SupportReportCategory) -> some View {
        let isSelected = category == cat
        let color = categoryColor(cat)
        return Button {
            category = cat
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: categoryIcon(cat))
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                }
                Text(cat.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isSelected ? color : Color.secondary.opacity(0.35),
                                lineWidth: isSelected ? 5 : 1.5
                            )
                    )
                    .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? color.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? color : AppTheme.Colour.separator,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: category)
    }

    private var detailsField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(icon: "pencil.line", text: "Details")
            TextEditor(text: $details)
                .font(.body)
                .frame(height: 90)
                .appTextEditorChrome()
        }
    }

    private var logsToggle: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $includeDiagnostics)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Include system logs & diagnostics")
                    .font(.subheadline.weight(.medium))
                Text("Helps us diagnose faster. Logs don't contain file contents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") {
                NSApp.keyWindow?.performClose(nil)
            }
            .buttonStyle(AppBorderedButtonStyle())

            Button("Send Report") {
                if let url = SupportReporter.mailURL(for: preview) {
                    FileAccessService.shared.open(url)
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .buttonStyle(AppProminentButtonStyle())
            .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(AppTheme.Colour.subtleFill)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Helpers

    private func sectionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
        }
    }

    private func categoryIcon(_ cat: SupportReportCategory) -> String {
        switch cat {
        case .conversionFailure: return "text.badge.xmark"
        case .crash:             return "exclamationmark.triangle.fill"
        case .outputQuality:     return "textformat"
        case .performance:       return "timer"
        case .other:             return "bubble.left.fill"
        }
    }

    private func categoryColor(_ cat: SupportReportCategory) -> Color {
        switch cat {
        case .conversionFailure: return Color.accentColor
        case .crash:             return AppTheme.Colour.sectionRed
        case .outputQuality:     return AppTheme.Colour.sectionPurple
        case .performance:       return AppTheme.Colour.sectionAmber
        case .other:             return .secondary
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
