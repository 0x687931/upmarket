import SwiftUI

struct MenuBarDropdown: View {

    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var conversion: ConversionQueue
    @EnvironmentObject private var historyStore: ConversionHistoryStore
    @Environment(\.openWindow) private var openWindow

    @State private var primaryActionHovered = false
    @State private var completedConversion = false
    @State private var showHistory = false
    @State private var completionToken = 0

    var body: some View {
        VStack(spacing: 0) {
            headerBanner
            Divider()
            actionRows
            Divider()
            footer
        }
        .frame(width: 280)
        // onChange fires only on genuine transitions; never on initial appearance.
        // completionToken increment is the trigger; task resets it after 0.8s.
        .onChange(of: conversion.isConverting) { converting in
            if converting {
                completedConversion = false   // clear green tint if a new job starts
            } else {
                completionToken += 1
            }
        }
        .task(id: completionToken) {
            guard completionToken > 0 else { return }
            completedConversion = true
            try? await Task.sleep(for: .seconds(0.8))
            completedConversion = false
        }
    }

    // MARK: - Header banner

    private var headerBanner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(hue: 0.67, saturation: 0.7, brightness: 0.75),
                    Color(hue: 0.75, saturation: 0.65, brightness: 0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "number.square.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("Upmarket")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Spacer()

                    entitlementBadge
                    pulseIndicator
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, conversion.isConverting ? 8 : 12)

                if conversion.isConverting {
                    progressBar
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: conversion.isConverting)
        }
        .frame(height: conversion.isConverting ? 68 : 48)
        .animation(.easeInOut(duration: 0.25), value: conversion.isConverting)
        .clipped()
    }

    // MARK: - Entitlement badge

    @ViewBuilder private var entitlementBadge: some View {
        switch store.entitlement {
        case .none:
            badge(
                label: store.freeDocsRemaining > 0
                    ? "\(store.freeDocsRemaining) free"
                    : "Trial ended",
                foreground: .white.opacity(0.85),
                background: .white.opacity(0.15)
            )
        case .basic:
            badge(label: "Upmarket", foreground: .white, background: .white.opacity(0.2))
        case .pro:
            proBadge
        }
    }

    private func badge(label: String, foreground: Color, background: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }

    private var proBadge: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.5) / 2.5
            let offset = phase * 2 - 1
            Text("Upmarket + AI")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.67, saturation: 0.5, brightness: 1.0),
                                Color(hue: 0.75, saturation: 0.6, brightness: 0.9),
                                Color(hue: 0.67, saturation: 0.5, brightness: 1.0)
                            ],
                            startPoint: UnitPoint(x: offset, y: 0),
                            endPoint: UnitPoint(x: offset + 1, y: 0)
                        )
                    )
                )
        }
    }

    // MARK: - Pulse dot + progress bar

    @ViewBuilder private var pulseIndicator: some View {
        if conversion.isConverting {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.4) / 1.4
                let opacity = 0.35 + 0.65 * abs(sin(t * .pi))
                Circle()
                    .fill(Color.white.opacity(opacity))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var progressBar: some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(completedConversion ? Color.green : Color.white.opacity(0.85))
                    .scaleEffect(
                        x: max(0.01, conversion.overallProgress),
                        anchor: .leading
                    )
                    .animation(.linear(duration: 0.3), value: conversion.overallProgress)
            }
    }

    // MARK: - Action rows (flat — no section labels)

    private var actionRows: some View {
        VStack(spacing: 0) {
            // Primary
            primaryActionRow

            Divider().padding(.leading, 44)

            // Shelf
            menuItem(icon: "sidebar.right", label: "Show Shelf",
                     shortcut: "⌘⇧S",
                     action: { ShelfWindowController.shared.show() }) {
                if conversion.jobs.count > 0 {
                    Text("(\(conversion.jobs.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            menuItem(icon: "clock", label: "History",
                     shortcut: nil,
                     action: { showHistory.toggle() }) {
                if !historyStore.records.isEmpty {
                    Text("(\(historyStore.records.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .popover(isPresented: $showHistory, arrowEdge: .leading) {
                HistoryPopover(historyStore: historyStore)
            }

            Divider().padding(.leading, 44)

            // Preferences
            menuItem(icon: "gearshape", label: "Preferences…",
                     shortcut: "⌘,",
                     action: {
                NSApp.sendAction(Selector(("orderFrontPreferencesPanel:")), to: nil, from: nil)
            })

            Divider().padding(.leading, 44)

            menuItem(icon: "power", label: "Quit Upmarket",
                     shortcut: "⌘Q",
                     action: { NSApp.terminate(nil) })
        }
        .padding(.vertical, 4)
    }

    // MARK: - Primary action row

    private var primaryActionRow: some View {
        Button {
            openConversionWindow(pickFile: true)
        } label: {
            HStack(spacing: 10) {
                primaryActionIcon
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, alignment: .center)

                Text("Convert Document…")
                    .font(.subheadline).fontWeight(.medium)

                Spacer()

                Text("⌘N")
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(primaryActionHovered ? 0.1 : 0))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .onHover { primaryActionHovered = $0 }
    }

    @ViewBuilder private var primaryActionIcon: some View {
        if #available(macOS 14.0, *) {
            Image(systemName: primaryActionHovered
                  ? "doc.badge.arrowtriangle.up.fill"
                  : "doc.badge.plus")
                .contentTransition(.symbolEffect(.replace.downUp))
        } else {
            Image(systemName: "doc.badge.plus")
        }
    }

    // MARK: - Menu item helper

    private func menuItem<T: View>(
        icon: String,
        label: String,
        shortcut: String?,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> T = { EmptyView() }
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, alignment: .center)
                Text(label)
                    .font(.subheadline)
                Spacer()
                trailing()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(versionString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        #if DEBUG
        return "v\(v) · debug"
        #else
        return "v\(v)"
        #endif
    }

    // MARK: - Helpers

    private func openConversionWindow(pickFile: Bool = false) {
        MainWindowController.shared.show(pickFile: pickFile)
    }
}

// MARK: - History popover

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
