import AppKit
import SwiftUI

struct ReportProblemView: View {
    @EnvironmentObject private var conversion: ConversionQueue
    @Environment(\.dismiss) var dismiss

    @State private var category: ReportCategory = .conversionFailed
    @State private var message = ""
    @State private var includeLogs = true
    @State private var sending = false

    private var failedJob: ConversionJob? { conversion.lastFailedJob }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(AppTheme.Colour.sectionRed.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.Colour.sectionRed)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Report a Problem")
                        .font(.system(size: 17, weight: .bold))
                    Text("Help us improve by reporting what went wrong.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Context strip (conditional)
            if let job = failedJob {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text("Conversion of \(job.filename).\(job.ext.lowercased()) failed")
                        .font(.system(size: 12).monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CategoryPicker(selected: $category)
                    DetailField(text: $message)
                    Toggle(isOn: $includeLogs) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include system logs & diagnostics")
                                .font(.system(size: 14, weight: .medium))
                            Text("Sends: error logs, conversion settings, system info (not your files)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button(sending ? "Sending…" : "Send Report") {
                    sendReport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                .tint(Color.accentColor)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 480)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func sendReport() {
        sending = true
        // Send logic would go here
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sending = false
            dismiss()
        }
    }
}

// MARK: - Category Picker

struct CategoryPicker: View {
    @Binding var selected: ReportCategory

    let categories: [(ReportCategory, String, Color)] = [
        (.conversionFailed, "doc.badge.xmark", Color.accentColor),
        (.crash, "exclamationmark.triangle.fill", AppTheme.Colour.sectionRed),
        (.outputQuality, "textformat", AppTheme.Colour.sectionPurple),
        (.performance, "timer", AppTheme.Colour.sectionAmber),
        (.other, "bubble.left.fill", Color.secondary),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("ISSUE TYPE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.4)
            }
            .padding(.bottom, 2)

            ForEach(categories, id: \.0) { cat, icon, color in
                CategoryRow(
                    label: cat.displayName,
                    icon: icon,
                    color: color,
                    selected: selected == cat
                ) {
                    selected = cat
                }
            }
        }
    }
}

struct CategoryRow: View {
    let label: String
    let icon: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                }

                Text(label)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)

                Spacer()

                Circle()
                    .strokeBorder(selected ? color : AppTheme.Colour.separator, lineWidth: selected ? 5 : 1.5)
                    .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? color.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? color : AppTheme.Colour.separator, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - Detail Field

struct DetailField: View {
    @Binding var text: String
    @FocusState var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("DETAILS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.4)
            }

            TextEditor(text: $text)
                .font(.system(size: 14))
                .frame(height: 90)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focused ? Color.accentColor : AppTheme.Colour.separator, lineWidth: 1)
                )
                .focused($focused)
        }
    }
}

// MARK: - Report Category

enum ReportCategory: CaseIterable, Equatable {
    case conversionFailed, crash, outputQuality, performance, other

    var displayName: String {
        switch self {
        case .conversionFailed: return "Conversion failed"
        case .crash: return "App crash"
        case .outputQuality: return "Output quality"
        case .performance: return "Performance issue"
        case .other: return "Other"
        }
    }
}

#Preview {
    ReportProblemView()
        .environmentObject(ConversionQueue.shared)
}
