import SwiftUI

struct MenuBarDropdown: View {

    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var conversion: ConversionQueue
    @Environment(\.openWindow) private var openWindow

    @State private var primaryActionHovered = false
    @State private var shimmerOffset: Double = -1.0
    @State private var pulsing = false
    @State private var completedConversion = false

    var body: some View {
        VStack(spacing: 0) {
            headerBanner
            sectionDivider
            sectionLabel("NOW")
            primaryActionRow
            sectionDivider
            sectionLabel("WORKSPACE")
            workspaceRows
            sectionDivider
            sectionLabel("APP")
            appRows
            sectionDivider
            footer
        }
        .frame(width: 280)
        .onChange(of: conversion.isConverting) { converting in
            if !converting {
                completedConversion = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    completedConversion = false
                }
            }
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
            badge(
                label: "Upmarket",
                foreground: .white,
                background: .white.opacity(0.2)
            )
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

    // Shimmer sweeps a brighter highlight left-to-right over the badge every 2.5s
    private var proBadge: some View {
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
                        startPoint: UnitPoint(x: shimmerOffset, y: 0),
                        endPoint: UnitPoint(x: shimmerOffset + 1, y: 0)
                    )
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.0
                }
            }
    }

    // MARK: - Pulse dot + progress bar

    @ViewBuilder private var pulseIndicator: some View {
        if conversion.isConverting {
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .opacity(pulsing ? 0.35 : 1.0)
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: pulsing
                )
                .onAppear { pulsing = true }
                .onDisappear { pulsing = false }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 3)
                Capsule()
                    .fill(completedConversion ? Color.green : Color.white.opacity(0.85))
                    .frame(width: geo.size.width * conversion.overallProgress, height: 3)
                    .animation(.linear(duration: 0.3), value: conversion.overallProgress)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Section chrome

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 1)
    }

    private var sectionDivider: some View {
        Divider()
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
                    .frame(width: 20)

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

    // MARK: - Workspace rows

    private var workspaceRows: some View {
        VStack(spacing: 0) {
            menuItem(icon: "sidebar.right", label: "Show Shelf", action: {
                ShelfWindowController.shared.show()
            }) {
                if conversion.jobs.count > 0 {
                    Text("(\(conversion.jobs.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            menuItemDisabled(icon: "clock", label: "History")
        }
    }

    // MARK: - App rows

    private var appRows: some View {
        VStack(spacing: 0) {
            menuItem(icon: "gearshape", label: "Preferences…", action: {
                NSApp.sendAction(Selector(("orderFrontPreferencesPanel:")), to: nil, from: nil)
            })
        }
    }

    // MARK: - Menu item helpers

    private func menuItem<T: View>(
        icon: String,
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> T = { EmptyView() }
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(label)
                    .font(.subheadline)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func menuItemDisabled(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Coming soon")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(versionString)
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
