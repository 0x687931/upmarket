import SwiftUI

struct MenuBarDropdown: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var conversion: ConversionQueue
    @EnvironmentObject private var historyStore: ConversionHistoryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if conversion.isConverting {
            Text(conversionStatusTitle)
            Divider()
        }

        Button {
            MainWindowController.shared.show(pickFile: true)
        } label: {
            Label("Convert Document...", systemImage: "doc.badge.plus")
        }
        .keyboardShortcut("o", modifiers: .command)

        if let lastRecord = historyStore.records.first {
            Button {
                let formatted = OutputFormatter.format(record: lastRecord, mode: OutputPreference.shared.mode)
                FileAccessService.shared.copyMarkdown(formatted.text)
            } label: {
                Label("Copy Last Result", systemImage: "doc.on.doc")
            }
        }

        Button {
            MainWindowController.shared.show()
        } label: {
            Label("Show Upmarket Window", systemImage: "macwindow")
        }

        Button {
            AppVisibilityPreference.showShelf = true
            ShelfWindowController.shared.show(ignoringPreference: true)
        } label: {
            Label(shelfTitle, systemImage: "sidebar.right")
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Button {
            HistoryWindowController.shared.show()
        } label: {
            Label(historyTitle, systemImage: "clock")
        }

        Divider()

        Button {
            NSApp.sendAction(Selector(("orderFrontPreferencesPanel:")), to: nil, from: nil)
        } label: {
            Label("Preferences...", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            openWindow(id: "reportProblem")
        } label: {
            Label("Report a Problem...", systemImage: "exclamationmark.bubble")
        }

        Divider()

        if store.hasProOrAbove {
            Text("Upmarket + AI")
        } else if store.hasBasicOrAbove {
            Button {
                NotificationCenter.default.post(name: .showPaywall, object: nil)
            } label: {
                Label("Upgrade to Upmarket + AI...", systemImage: "arrow.up.circle")
            }
        } else {
            Button {
                NotificationCenter.default.post(name: .showPaywall, object: nil)
            } label: {
                Label("Unlock Upmarket...", systemImage: "lock.open")
            }
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit Upmarket", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var conversionStatusTitle: String {
        let percent = Int((conversion.overallProgress * 100).rounded())
        return percent > 0 ? "Converting \(percent)%" : "Converting"
    }

    private var shelfTitle: String {
        conversion.jobs.isEmpty ? "Show Shelf" : "Show Shelf (\(conversion.jobs.count))"
    }

    private var historyTitle: String {
        historyStore.records.isEmpty ? "History" : "History (\(historyStore.records.count))"
    }

    private var entitlementTitle: String {
        switch store.entitlement {
        case .none:
            return "Locked"
        case .basic:
            return "Upmarket"
        case .pro:
            return "Upmarket + AI"
        }
    }
}

struct HistoryPopover: View {
    @ObservedObject var historyStore: ConversionHistoryStore
    @State private var query = ""

    private var records: [ConversionHistoryRecord] {
        historyStore.filteredRecords(query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("History")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if !historyStore.isEnabled {
                emptyState("History is turned off.")
            } else if historyStore.records.isEmpty {
                emptyState("Completed conversions will appear here.")
            } else if records.isEmpty {
                emptyState("No matching conversions.")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(records) { record in
                            HistoryRow(record: record)
                            if record.id != records.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 300)
        .padding(.bottom, 8)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 96)
    }
}

private struct HistoryRow: View {
    let record: ConversionHistoryRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.sourceDisplayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(historyDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                FileAccessService.shared.copyMarkdown(
                    OutputFormatter.format(record: record, mode: OutputPreference.shared.mode).text
                )
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Copy Output")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var historyDetail: String {
        let title = record.title == record.sourceDisplayName ? record.format : record.title
        return "\(title) · \(record.provenanceLabel) · \(record.wordCount) words"
    }
}
