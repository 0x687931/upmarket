import SwiftUI

/// Dropdown that appears when clicking the menu bar icon.
/// Compact, actionable, shows conversion state.
struct MenuBarDropdown: View {

    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var conversion: ConversionService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            actions
            Divider()
            footer
        }
        .frame(width: 220)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            // Animated icon
            ZStack {
                if #available(macOS 14.0, *) {
                    Image(systemName: conversion.isConverting ? "number.circle.fill" : "number.square")
                        .symbolRenderingMode(conversion.isConverting ? .palette : .hierarchical)
                        .foregroundStyle(
                            conversion.isConverting ? Color.white : Color.primary,
                            conversion.isConverting ? Color(nsColor: .controlAccentColor) : Color.primary
                        )
                        .font(.system(size: 22, weight: .medium))
                        .symbolEffect(.pulse, isActive: conversion.isConverting)
                } else {
                    Image(systemName: conversion.isConverting ? "number.circle.fill" : "number")
                        .font(.system(size: 22, weight: .medium))
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Upmarket")
                    .font(.subheadline).fontWeight(.semibold)
                Text(statusText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusText: String {
        if conversion.isConverting { return "Converting…" }
        switch store.entitlement {
        case .pro:   return "Upmarket + AI"
        case .basic: return "Upmarket"
        case .none:
            return store.freeDocsRemaining > 0
                ? "\(store.freeDocsRemaining) free conversions"
                : "Trial expired"
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 0) {
            menuItem(icon: "sidebar.right", label: "Show Shelf") {
                ShelfWindowController.shared.show()
            }
            menuItem(icon: "gearshape", label: "Preferences…") {
                openWindow(id: "preferences")
            }
        }
        .padding(.vertical, 4)
    }

    private func menuItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(label)
                    .font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.001))  // makes full row tappable
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("v\(appVersion)")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
