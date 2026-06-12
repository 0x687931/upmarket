import SwiftUI

struct MenuBarDropdown: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var conversion: ConversionQueue

    var body: some View {
        if conversion.isConverting {
            StatusRow(conversionStatusTitle)
            Divider()
        }

        MenuRow(icon: "doc.badge.plus", label: "Convert Document…", shortcut: "⌘O") {
            MainWindowController.shared.show(pickFile: true)
        }

        MenuRow(icon: "macwindow", label: "Show Upmarket Window") {
            MainWindowController.shared.show()
        }

        MenuRow(icon: "square.grid.2x2", label: AppVisibilityPreference.showShelf ? "Hide Shelf" : "Show Shelf") {
            let showing = AppVisibilityPreference.showShelf
            AppVisibilityPreference.applyShelfVisibility(showShelf: !showing)
        }

        Divider()

        MenuRow(icon: "gearshape", label: "Preferences…", shortcut: "⌘,") {
            PreferencesWindowController.shared.show()
        }

        MenuRow(icon: "exclamationmark.bubble", label: "Report a Problem…") {
            ReportProblemWindowController.shared.show()
        }

        Divider()

        if store.hasProOrAbove {
            MenuRow(icon: "checkmark.circle", label: "Upmarket + AI", status: true) {
                // No-op: status row only.
            }
        } else if store.hasBasicOrAbove {
            MenuRow(icon: "arrow.up.circle", label: "Upgrade to Upmarket + AI…") {
                NotificationCenter.default.post(name: .showPaywall, object: nil)
            }
        } else {
            MenuRow(icon: "lock.open", label: "Unlock Upmarket…") {
                NotificationCenter.default.post(name: .showPaywall, object: nil)
            }
        }

        Divider()

        StatusRow(versionLine)

        MenuRow(icon: "power", label: "Quit Upmarket", shortcut: "⌘Q") {
            NSApp.terminate(nil)
        }
    }

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version) · support@upmarket.app"
    }

    private var conversionStatusTitle: String {
        let percent = Int((conversion.overallProgress * 100).rounded())
        return percent > 0 ? "Converting \(percent)%" : "Converting"
    }
}

private struct StatusRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .padding(.horizontal, 12)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuRow: View {
    let icon: String
    let label: String
    var shortcut: String? = nil
    var status: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            if !status {
                action()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 16, alignment: .center)
                    .foregroundStyle(status ? Color.secondary : (isHovering ? Color.white : Color.secondary))

                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(
                            status ? Color.secondary.opacity(0.7)
                            : (isHovering ? Color.white.opacity(0.85) : Color.secondary.opacity(0.7))
                        )
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(!status && isHovering ? Color.accentColor : Color.clear)
            .foregroundStyle(status ? Color.secondary : (isHovering ? Color.white : Color.primary))
            .contentShape(Rectangle())
        }
        .disabled(status)
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { if !status { isHovering = $0 } }
    }
}
