import SwiftUI

struct PreferencesView: View {

    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager

    @State private var selectedTab: Tab = .models

    enum Tab: String, CaseIterable {
        case models  = "Models"
        case account = "Account"
        case about   = "About"

        var icon: String {
            switch self {
            case .models:  return "cpu"
            case .account: return "person.circle"
            case .about:   return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 560, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .frame(width: 18)
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .medium : .regular)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        selectedTab == tab
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 140)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .models:  modelsTab
        case .account: accountTab
        case .about:   aboutTab
        }
    }

    // MARK: - Models Tab

    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(icon: "cpu", title: "Models", subtitle: "Manage downloaded AI models")
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(modelManager.models, id: \.key) { model in
                        modelRow(model)
                    }
                    if modelManager.models.isEmpty {
                        Text("No models downloaded")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Text("Storage used: \(modelManager.totalStorageUsedFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if modelManager.models.contains(where: \.isDownloaded) {
                    Button("Delete All Models") {
                        modelManager.deleteAllModels()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    private func modelRow(_ model: ModelStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: model.isDownloaded ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.isDownloaded ? Color.green : Color.secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if model.tier == "pro" {
                        Text("PRO")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isDownloaded {
                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(model.sizeMB) * 1024 * 1024,
                    countStyle: .file
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Delete") {
                    modelManager.deleteModel(key: model.key)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .foregroundStyle(.red)
            } else {
                Text("\(model.sizeMB) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Download") {
                    if model.tier == "pro" {
                        modelManager.downloadProModels()
                    } else {
                        modelManager.downloadRequiredModels()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Account Tab

    private var accountTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(icon: "person.circle", title: "Account", subtitle: "Your Upmarket plan")
            Divider()
            VStack(spacing: 16) {
                // Current plan
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 48, height: 48)
                        Text("#")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(planName)
                            .font(.headline)
                        Text(planDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !store.hasProOrAbove {
                        Button("Upgrade") {
                            // Post notification to show paywall from parent
                            NotificationCenter.default.post(name: .showPaywall, object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                // Credits if applicable
                if store.packCredits > 0 {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Color.accentColor)
                        Text("\(store.packCredits) document conversions remaining")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                Button("Restore Purchases") {
                    Task { await store.restorePurchases() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private var planName: String {
        switch store.entitlement {
        case .pro:   return "Upmarket + AI"
        case .basic: return "Upmarket"
        case .none:  return store.freeDocsRemaining > 0 ? "Free" : "Free (used)"
        }
    }

    private var planDescription: String {
        switch store.entitlement {
        case .pro:   return "Unlimited conversions · Upmarket AI included"
        case .basic: return "Unlimited conversions · One-time purchase"
        case .none:
            return store.freeDocsRemaining > 0
                ? "\(store.freeDocsRemaining) free conversions remaining"
                : "Upgrade to continue converting"
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(icon: "info.circle", title: "About", subtitle: "Upmarket v\(appVersion)")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Links
                    VStack(alignment: .leading, spacing: 8) {
                        linkRow(icon: "lock.shield", label: "Privacy Policy",
                                url: "https://0x687931.github.io/upmarket/privacy")
                        linkRow(icon: "doc.text", label: "Terms of Use",
                                url: "https://0x687931.github.io/upmarket/terms")
                        linkRow(icon: "envelope", label: "Support",
                                url: "mailto:support@upmarket.app")
                    }

                    Divider()

                    // Open source
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open Source")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(openSourcePackages, id: \.name) { pkg in
                            HStack {
                                Text(pkg.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(pkg.version)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(pkg.license)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func linkRow(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(Color.accentColor)
                Text(label)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func tabHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var openSourcePackages: [LicenseEntry] {
        guard let url = Bundle.main.url(forResource: "licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([LicenseEntry].self, from: data)
        else {
            return []
        }
        return entries
    }
}

struct LicenseEntry: Identifiable, Codable {
    var id: String { name }
    let name: String
    let version: String
    let license: String
    let url: String
}

extension Notification.Name {
    static let showPaywall = Notification.Name("upmarket.showPaywall")
}

#Preview {
    PreferencesView()
        .environmentObject(ModelManager.shared)
        .environmentObject(StoreManager.shared)
}
