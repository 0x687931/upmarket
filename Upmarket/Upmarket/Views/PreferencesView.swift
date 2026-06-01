import SwiftUI
import AppKit

/// Settings window — layout matches Dockside's preferences exactly:
/// Tab bar at top, NSBox-grouped sections, standard macOS controls.
/// Tabs: General · Conversion · Models · License · About
struct PreferencesView: View {

    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager

    @State private var selectedTab: Tab = .general

    enum Tab: String, CaseIterable {
        case general    = "General"
        case conversion = "Conversion"
        case models     = "Models"
        case license    = "License"
        case about      = "About"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — matches Dockside's NSTabView appearance exactly
            tabBar
            Divider()
            // Content area
            ScrollView {
                tabContent
                    .padding(20)
            }
        }
        .frame(width: 540, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button(tab.rawValue) {
                    selectedTab = tab
                }
                .buttonStyle(TabButtonStyle(isSelected: selectedTab == tab))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:    generalTab
        case .conversion: conversionTab
        case .models:     modelsTab
        case .license:    licenseTab
        case .about:      aboutTab
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Appearance & Behaviour
            PrefsBox(title: "Appearance & Behaviour") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Style:")
                            .frame(width: 120, alignment: .trailing)
                        Picker("", selection: Binding(
                            get: { UserDefaults.standard.integer(forKey: "upmarket.shelfStyle") },
                            set: { UserDefaults.standard.set($0, forKey: "upmarket.shelfStyle") }
                        )) {
                            Text("Transparent").tag(0)
                            Text("Dock-Style").tag(1)
                            Text("Opaque").tag(2)
                        }
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                    }

                    HStack {
                        Text("Appearance:")
                            .frame(width: 120, alignment: .trailing)
                        Picker("", selection: Binding(
                            get: { UserDefaults.standard.integer(forKey: "upmarket.appearance") },
                            set: { UserDefaults.standard.set($0, forKey: "upmarket.appearance") }
                        )) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
            }

            // Launch Options
            PrefsBox(title: "Launch Options") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("")
                            .frame(width: 120, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Start at Login", isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "upmarket.launchAtLogin") },
                                set: { UserDefaults.standard.set($0, forKey: "upmarket.launchAtLogin") }
                            ))
                            Toggle("Play Sounds", isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "upmarket.playSounds") },
                                set: { UserDefaults.standard.set($0, forKey: "upmarket.playSounds") }
                            ))
                            Toggle("Hide Menu Bar Icon", isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "upmarket.hideMenuBar") },
                                set: { UserDefaults.standard.set($0, forKey: "upmarket.hideMenuBar") }
                            ))
                        }
                    }

                    HStack {
                        Text("Check for Updates:")
                            .frame(width: 120, alignment: .trailing)
                        Toggle("Automatically", isOn: .constant(true))
                        Button("Check Now") {}
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Conversion Tab

    private var conversionTab: some View {
        VStack(alignment: .leading, spacing: 16) {

            PrefsBox(title: "Conversion Settings") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Default pipeline:")
                            .frame(width: 140, alignment: .trailing)
                        Picker("", selection: Binding(
                            get: { UserDefaults.standard.integer(forKey: "upmarket.defaultPipeline") },
                            set: { UserDefaults.standard.set($0, forKey: "upmarket.defaultPipeline") }
                        )) {
                            Text("Fast (instant)").tag(0)
                            Text("Enhanced (better quality)").tag(1)
                        }
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                    }

                    HStack(alignment: .top) {
                        Text("")
                            .frame(width: 140, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Enable OCR for scanned documents", isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "upmarket.enableOCR") },
                                set: { UserDefaults.standard.set($0, forKey: "upmarket.enableOCR") }
                            ))
                            Toggle("Suggest Upmarket AI for complex documents", isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "upmarket.suggestAI") },
                                set: { UserDefaults.standard.set($0, forKey: "upmarket.suggestAI") }
                            ))
                            Toggle("Auto-convert on drop (no confirmation)", isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "upmarket.autoConvert") },
                                set: { UserDefaults.standard.set($0, forKey: "upmarket.autoConvert") }
                            ))
                        }
                    }
                }
            }

            PrefsBox(title: "Drop Zone Activation") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activate:")
                            .frame(width: 140, alignment: .trailing)
                        Picker("", selection: Binding(
                            get: { UserDefaults.standard.integer(forKey: "upmarket.dropActivation") },
                            set: { UserDefaults.standard.set($0, forKey: "upmarket.dropActivation") }
                        )) {
                            Text("when dragging starts…").tag(0)
                            Text("when dragging is near the shelf…").tag(1)
                            Text("disabled").tag(2)
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
            }
        }
    }

    // MARK: - Models Tab

    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 16) {

            PrefsBox(title: "Downloaded Models") {
                VStack(spacing: 8) {
                    ForEach(modelManager.models, id: \.key) { model in
                        HStack(spacing: 12) {
                            Image(systemName: model.isDownloaded ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.isDownloaded ? Color.green : .secondary)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(model.name).fontWeight(.medium)
                                    if model.tier == "pro" {
                                        Text("PRO")
                                            .font(.caption2).fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.accentColor, in: Capsule())
                                    }
                                }
                                Text(model.description)
                                    .font(.caption).foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(model.isDownloaded ? modelManager.totalStorageUsedFormatted : "\(model.sizeMB) MB")
                                .font(.caption).foregroundStyle(.secondary)

                            if model.isDownloaded {
                                Button("Delete") { modelManager.deleteModel(key: model.key) }
                                    .buttonStyle(.bordered).controlSize(.mini)
                                    .foregroundStyle(.red)
                            } else {
                                Button("Download") {
                                    model.tier == "pro"
                                        ? modelManager.downloadProModels()
                                        : modelManager.downloadRequiredModels()
                                }
                                .buttonStyle(.bordered).controlSize(.mini)
                            }
                        }
                        .padding(.vertical, 4)
                        if model.key != modelManager.models.last?.key {
                            Divider()
                        }
                    }

                    if modelManager.isDownloading {
                        VStack(spacing: 6) {
                            ProgressView(value: modelManager.downloadProgress, total: 100)
                            Text(modelManager.downloadMessage)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }

            if modelManager.models.contains(where: \.isDownloaded) {
                HStack {
                    Spacer()
                    Text("Total storage: \(modelManager.totalStorageUsedFormatted)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Delete All Models") { modelManager.deleteAllModels() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - License Tab

    private var licenseTab: some View {
        VStack(alignment: .leading, spacing: 16) {

            PrefsBox(title: "Upmarket License") {
                VStack(alignment: .leading, spacing: 12) {
                    // Current plan
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 44, height: 44)
                            Text("#")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planName).font(.headline)
                            Text(planDetail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !store.hasProOrAbove {
                            Button("Upgrade") {
                                NotificationCenter.default.post(name: .showPaywall, object: nil)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }

                    if store.packCredits > 0 {
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(Color.accentColor)
                            Text("\(store.packCredits) document conversions remaining")
                                .font(.subheadline)
                        }
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Restore Purchases") {
                            Task { await store.restorePurchases() }
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("✓ Use on this Mac · One-time purchase · No subscription")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {

            PrefsBox(title: "Upmarket") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable().frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Upmarket").font(.title3).fontWeight(.bold)
                            Text("Version \(appVersion)").font(.subheadline).foregroundStyle(.secondary)
                            Text("Document to Markdown, On-Device").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        linkRow(icon: "lock.shield",   label: "Privacy Policy",    url: "https://0x687931.github.io/upmarket/privacy")
                        linkRow(icon: "doc.text",      label: "Terms of Use",      url: "https://0x687931.github.io/upmarket/terms")
                        linkRow(icon: "envelope",      label: "Support",           url: "mailto:support@upmarket.app")
                        linkRow(icon: "star",          label: "Rate Upmarket",     url: "macappstore://")
                        linkRow(icon: "bubble.left",   label: "Report a Bug",      url: "mailto:support@upmarket.app?subject=Bug%20Report")
                    }
                }
            }

            PrefsBox(title: "Open Source") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(openSourcePackages, id: \.name) { pkg in
                        HStack {
                            Text(pkg.name).font(.caption).fontWeight(.medium)
                            Text(pkg.version).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(pkg.license)
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func linkRow(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(Color.accentColor)
                Text(label).font(.subheadline)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var planName: String {
        switch store.entitlement {
        case .pro:   return "Upmarket + AI"
        case .basic: return "Upmarket"
        case .none:  return store.freeDocsRemaining > 0 ? "Free" : "Free (expired)"
        }
    }

    private var planDetail: String {
        switch store.entitlement {
        case .pro:   return "Unlimited · Upmarket AI included"
        case .basic: return "Unlimited · One-time purchase"
        case .none:  return store.freeDocsRemaining > 0
            ? "\(store.freeDocsRemaining) free conversions remaining"
            : "Upgrade to continue converting"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var openSourcePackages: [LicenseEntry] {
        guard let url = Bundle.main.url(forResource: "licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([LicenseEntry].self, from: data)
        else { return [] }
        return entries
    }
}

// MARK: - Tab Button Style (matches Dockside's NSTabView appearance)

struct TabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? Color(nsColor: .controlAccentColor).opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }
}

// MARK: - PrefsBox (matches Dockside's NSBox sections)

struct PrefsBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                content
                    .padding(14)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PreferencesView()
        .environmentObject(ModelManager.shared)
        .environmentObject(StoreManager.shared)
}

// MARK: - Supporting types

struct LicenseEntry: Identifiable, Codable {
    var id: String { name }
    let name: String
    let version: String
    let license: String
    let url: String
}
