import SwiftUI
import AppKit

// Two tabs: Settings (save location + models) · About (identity + license + links + open source)
// Every control is backed by a real service. No dead controls.

struct PreferencesView: View {

    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager

    private let device = DeviceCapability.shared

    var body: some View {
        TabView {
            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 440)
    }

    // MARK: - Settings

    private var settingsTab: some View {
        Form {
            Section("Save Location") {
                LabeledContent("Save files:") {
                    Picker("", selection: Binding(
                        get: { SavePreference.shared.destination },
                        set: { SavePreference.shared.destination = $0 }
                    )) {
                        Text("Same folder as original").tag(SavePreference.Destination.sameFolder)
                        Text("Ask each time").tag(SavePreference.Destination.askEachTime)
                        Text("Choose folder…").tag(SavePreference.Destination.chosenFolder)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }

                if SavePreference.shared.destination == .chosenFolder {
                    LabeledContent("Folder:") {
                        HStack(spacing: 8) {
                            Text(SavePreference.shared.chosenFolderURL?.lastPathComponent ?? "None chosen")
                                .foregroundStyle(
                                    SavePreference.shared.chosenFolderURL == nil ? .secondary : .primary
                                )
                            Button("Choose…") { chooseSaveFolder() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }

            Section("Models") {
                modelRows
            }

            if device.supportsAdvancedRuntime {
                if modelManager.isDownloading {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: modelManager.downloadProgress, total: 100)
                            Text(modelManager.downloadMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = modelManager.downloadError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                if modelManager.models.contains(where: \.isDownloaded) {
                    Section {
                        LabeledContent("Storage used:") {
                            HStack {
                                Text(modelManager.totalStorageUsedFormatted)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Delete All Models") { modelManager.deleteAllModels() }
                                    .foregroundStyle(.red)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if case .unchecked = modelManager.installState { modelManager.checkModels() }
        }
    }

    private func chooseSaveFolder() {
        if let url = FileAccessService.shared.chooseSaveDirectory(
            message: "Upmarket will save converted files here."
        ) {
            SavePreference.shared.chosenFolderURL = url
            SavePreference.shared.destination = .chosenFolder
        }
    }

    @ViewBuilder private var modelRows: some View {
        if !device.supportsAdvancedRuntime {
            Label("Fast conversion available. AI models require Apple Silicon.",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if case .checking = modelManager.installState {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let error = modelManager.checkError {
            HStack {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") { modelManager.checkModels() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
        } else if modelManager.models.isEmpty {
            HStack {
                Label("No models needed for fast conversion.",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check Again") { modelManager.checkModels() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
        } else {
            ForEach(modelManager.models, id: \.key) { model in
                LabeledContent {
                    HStack(spacing: 8) {
                        Text("\(model.sizeMB) MB")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if model.isDownloaded {
                            Button("Delete") { modelManager.deleteModel(key: model.key) }
                                .foregroundStyle(.red)
                                .buttonStyle(.bordered).controlSize(.mini)
                        } else {
                            Button("Download") {
                                model.tier == "pro"
                                    ? modelManager.downloadProModels(hasPro: store.hasProOrAbove)
                                    : modelManager.downloadRequiredModels()
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                            .disabled(downloadUnavailable(for: model) != nil)
                            .help(downloadUnavailable(for: model) ?? "")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.isDownloaded
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                model.isDownloaded ? Color.green
                                    : model.isAvailable ? Color.secondary
                                    : Color.red
                            )
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
                            Text(model.error ?? model.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func downloadUnavailable(for model: ModelStatus) -> String? {
        if model.isDownloaded { return nil }
        if model.tier == "pro" {
            return modelManager.proDownloadUnavailableReason(hasPro: store.hasProOrAbove)
        }
        if !model.isAvailable {
            return model.error ?? "Not available on this Mac."
        }
        return nil
    }

    // MARK: - About

    @State private var showAttributions = false

    private var aboutTab: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upmarket").font(.headline)
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section("License") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(planName).font(.subheadline).fontWeight(.medium)
                        Text(planDetail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !store.hasProOrAbove {
                        Button("Upgrade") {
                            NotificationCenter.default.post(name: .showPaywall, object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                if store.packCredits > 0 {
                    LabeledContent("Document credits:") {
                        Text("\(store.packCredits) remaining")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Restore Purchases") {
                    Task { await store.restorePurchases() }
                }
            }

            Section {
                HStack(spacing: 0) {
                    linkButton(icon: "lock.shield", label: "Privacy Policy",
                               url: "https://0x687931.github.io/upmarket/privacy")
                    Divider().frame(height: 28)
                    linkButton(icon: "envelope", label: "Support",
                               url: "mailto:support@upmarket.app")
                    Divider().frame(height: 28)
                    linkButton(icon: "star", label: "Rate",
                               url: "macappstore://")
                }
            }

            if !openSourcePackages.isEmpty {
                Section {
                    Button {
                        showAttributions = true
                    } label: {
                        Label("Attributions", systemImage: "doc.text")
                    }
                    .sheet(isPresented: $showAttributions) {
                        AttributionsSheet(groups: licenseGroups)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Equal-width tappable button: icon above label, fills 1/3 of the row
    private func linkButton(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var licenseGroups: [LicenseGroup] {
        let packages = openSourcePackages
        guard !packages.isEmpty else { return [] }
        var buckets: [String: [LicenseEntry]] = [:]
        for pkg in packages {
            buckets[normalisedFamily(pkg.license), default: []].append(pkg)
        }
        return ["MIT", "BSD", "Apache-2.0"].compactMap { family in
            buckets[family].map { LicenseGroup(family: family, packages: $0) }
        }
    }

    private func normalisedFamily(_ raw: String) -> String {
        let l = raw.lowercased()
        if l.contains("mit")    { return "MIT" }
        if l.contains("apache") { return "Apache-2.0" }
        if l.contains("bsd")    { return "BSD" }
        return "Other"
    }

    // MARK: - Helpers

    private var planName: String {
        switch store.entitlement {
        case .pro:   return "Upmarket + AI"
        case .basic: return "Upmarket"
        case .none:  return store.freeDocsRemaining > 0 ? "Free Trial" : "Trial Ended"
        }
    }

    private var planDetail: String {
        switch store.entitlement {
        case .pro:   return "Unlimited · AI included"
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

// MARK: - Attributions sheet

struct AttributionsSheet: View {
    let groups: [LicenseGroup]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Attributions")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Package list grouped by license family
            List {
                ForEach(groups) { group in
                    Section(group.family) {
                        ForEach(group.packages) { pkg in
                            Button {
                                if let url = URL(string: pkg.url) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text(pkg.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(pkg.version)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 380, height: 420)
    }
}

// MARK: - Supporting types

struct LicenseGroup: Identifiable {
    var id: String { family }
    let family: String
    let packages: [LicenseEntry]
}

struct LicenseEntry: Identifiable, Codable {
    var id: String { name }
    let name: String
    let version: String
    let license: String
    let url: String
}

#Preview {
    PreferencesView()
        .environmentObject(ModelManager.shared)
        .environmentObject(StoreManager.shared)
}
