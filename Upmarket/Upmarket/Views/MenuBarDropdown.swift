import SwiftUI

struct MenuBarDropdown: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var conversion: ConversionQueue
    @State private var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 0) {
            // Converting status (only when a job is running)
            if conversion.isConverting {
                StatusRow(text: "Converting \(Int(conversion.overallProgress * 100))%")
                MenuDivider()
            }

            // Primary actions
            MenuRow(icon: "doc.badge.plus", label: "Convert Document…", shortcut: "⌘O", action: {
                MainWindowController.shared.show(pickFile: true)
            })
            MenuRow(icon: "macwindow", label: "Show Upmarket Window", action: {
                MainWindowController.shared.show()
            })
            MenuRow(icon: "sidebar.squares.left",
                    label: AppVisibilityPreference.showShelf ? "Hide Shelf" : "Show Shelf",
                    action: {
                let showing = AppVisibilityPreference.showShelf
                AppVisibilityPreference.applyShelfVisibility(showShelf: !showing)
            })

            MenuDivider()

            // Settings
            MenuRow(icon: "gearshape", label: "Preferences…", shortcut: "⌘,", action: {
                PreferencesWindowController.shared.show()
            })
            MenuRow(icon: "exclamationmark.triangle", label: "Report a Problem…", action: {
                ReportProblemWindowController.shared.show()
            })

            MenuDivider()

            // Tier row — adapts to current entitlement
            switch store.tier {
            case .basic:
                MenuRow(icon: "arrow.up.circle", label: "Upgrade to Upmarket Pro…", accent: true, action: {
                    NotificationCenter.default.post(name: .showPaywall, object: nil)
                })
            case .pro:
                MenuRow(icon: "arrow.up.circle", label: "Upgrade to Upmarket Max…", accent: true, action: {
                    NotificationCenter.default.post(name: .showPaywall, object: nil)
                })
            case .max:
                MenuRow(icon: "checkmark.circle.fill", label: "Upmarket Max", isStatus: true)
            }

            MenuDivider()

            // Footer (non-interactive)
            StatusRow(text: "v\(appVersion)")
            StatusRow(text: userEmail)
            MenuRow(icon: "power", label: "Quit Upmarket", shortcut: "⌘Q", action: {
                NSApp.terminate(nil)
            })
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var userEmail: String {
        // From receipt or AppStore account — fallback to empty string for now
        // This would come from StoreKit or stored preference
        ""
    }
}

// MARK: - MenuRow

struct MenuRow: View {
    let icon: String
    let label: String
    var shortcut: String? = nil
    var accent: Bool = false
    var isStatus: Bool = false
    var action: (() -> Void)? = nil

    @State private var hovered = false

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(hovered ? .white : accent ? Color.accentColor : .secondary)

                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(hovered ? .white : accent ? Color.accentColor : .primary)

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(hovered ? .white.opacity(0.85) : .secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(hovered && !isStatus ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(isStatus)
        .padding(.horizontal, 4)
        .onHover { hovered = $0 && !isStatus }
    }
}

// MARK: - StatusRow

struct StatusRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - MenuDivider

struct MenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}
