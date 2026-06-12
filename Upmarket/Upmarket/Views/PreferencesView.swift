import SwiftUI
import AppKit

// Three tabs: General (app + storage) · Conversion (output + automation + models) · About
// Every control is backed by a real service. No dead controls.

struct PreferencesView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var historyStore: ConversionHistoryStore
    @EnvironmentObject private var watchedFolderService: WatchedFolderService

    @StateObject private var mcpIntegration = MCPIntegrationService.shared
    private let device = DeviceCapability.shared
    @State private var watchedFolderError: String?
    @AppStorage(AppVisibilityPreference.showDockIconKey) private var showDockIcon = AppVisibilityPreference.defaultShowDockIcon
    @AppStorage(AppVisibilityPreference.showMenuBarIconKey) private var showMenuBarIcon = AppVisibilityPreference.defaultShowMenuBarIcon
    @AppStorage(AppVisibilityPreference.showShelfKey) private var showShelf = AppVisibilityPreference.defaultShowShelf
    @AppStorage("upmarket.shelfAnchor") private var shelfAnchorRaw: Int = ShelfWindowController.ShelfAnchor.center.rawValue

    private static let watchDocumentOptions: [WatchPatternOption] = [
        WatchPatternOption(
            title: "PDF",
            detail: ".pdf",
            patterns: ["*.pdf"]
        ),
        WatchPatternOption(
            title: "Word",
            detail: ".docx",
            patterns: ["*.docx"]
        ),
        WatchPatternOption(
            title: "Slides",
            detail: ".pptx",
            patterns: ["*.pptx"]
        ),
        WatchPatternOption(
            title: "Sheets",
            detail: ".xlsx",
            patterns: ["*.xlsx"]
        ),
        WatchPatternOption(
            title: "HTML",
            detail: ".html",
            patterns: ["*.html", "*.htm"]
        ),
        WatchPatternOption(
            title: "Text",
            detail: ".txt",
            patterns: ["*.txt"]
        ),
        WatchPatternOption(
            title: "EPUB",
            detail: ".epub",
            patterns: ["*.epub"]
        ),
        WatchPatternOption(
            title: "ZIP",
            detail: ".zip",
            patterns: ["*.zip"]
        ),
        WatchPatternOption(
            title: "CSV",
            detail: ".csv",
            patterns: ["*.csv"]
        ),
        WatchPatternOption(
            title: "XML",
            detail: ".xml",
            patterns: ["*.xml"]
        )
    ]

    private static let watchImageOptions: [WatchPatternOption] = [
        WatchPatternOption(
            title: "PNG",
            detail: ".png",
            patterns: ["*.png"]
        ),
        WatchPatternOption(
            title: "JPEG",
            detail: ".jpg",
            patterns: ["*.jpg", "*.jpeg"]
        ),
        WatchPatternOption(
            title: "GIF",
            detail: ".gif",
            patterns: ["*.gif"]
        ),
        WatchPatternOption(
            title: "TIFF",
            detail: ".tiff",
            patterns: ["*.tif", "*.tiff"]
        )
    ]

    private static let watchAudioOptions: [WatchPatternOption] = [
        WatchPatternOption(
            title: "MP3/M4A",
            detail: ".mp3 .m4a",
            patterns: ["*.mp3", "*.m4a"]
        ),
        WatchPatternOption(
            title: "WAV/AIFF",
            detail: "+ Opus",
            patterns: ["*.wav", "*.aiff", "*.opus"]
        )
    ]

    private static let watchIncludeOptions =
        watchDocumentOptions + watchImageOptions + watchAudioOptions

    private static let watchExcludeOptions: [WatchPatternOption] = [
        WatchPatternOption(
            title: "Converted outputs",
            detail: "Markdown and JSON files Upmarket may create",
            patterns: ["*.md", "*.markdown", "*.json"]
        ),
        WatchPatternOption(
            title: "Temporary downloads",
            detail: "Partial browser and system download files",
            patterns: ["*.tmp", "*.download", "*.part", "*.crdownload", "~$*"]
        ),
        WatchPatternOption(
            title: "Drafts",
            detail: "Files with draft in the name",
            patterns: ["*draft*"]
        )
    ]

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            conversionTab
                .tabItem { Label("Conversion", systemImage: "doc.text") }

            automationTab
                .tabItem { Label("Automation", systemImage: "folder.badge.gearshape") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 680)
        .onChange(of: showDockIcon) { value in
            AppVisibilityPreference.apply(showDockIcon: value)
            showDockIcon = AppVisibilityPreference.showDockIcon
        }
        .onChange(of: showMenuBarIcon) { _ in
            AppVisibilityPreference.normalizePersistentVisibility()
            AppVisibilityPreference.applyMenuBarVisibility(showMenuBarIcon: showMenuBarIcon)
        }
        .onChange(of: showShelf) { value in
            AppVisibilityPreference.applyShelfVisibility(showShelf: value)
        }
        .onAppear {
            AppVisibilityPreference.normalizePersistentVisibility()
            showDockIcon = AppVisibilityPreference.showDockIcon
            AppVisibilityPreference.apply(showDockIcon: showDockIcon)
            AppVisibilityPreference.applyMenuBarVisibility(showMenuBarIcon: showMenuBarIcon)
            if !showShelf {
                ShelfWindowController.shared.hide(animate: false)
            }
            if case .unchecked = modelManager.installState { modelManager.checkModels() }
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("App") {
                Toggle("Show Dock icon", isOn: dockIconBinding)
                    .toggleStyle(.checkbox)
                    .disabled(AppVisibilityPreference.requiresDockIcon)

                Toggle("Show menu bar icon", isOn: menuBarIconBinding)
                    .toggleStyle(.checkbox)

                #if DEBUG
                Toggle("Show shelf", isOn: $showShelf)
                    .toggleStyle(.checkbox)
                    .onChange(of: showShelf) { show in
                        if show { ShelfWindowController.shared.show() }
                        else { ShelfWindowController.shared.hide(animate: false) }
                    }

                if showShelf {
                    LabeledContent("Shelf position:") {
                        Picker("Shelf position", selection: shelfAnchorBinding) {
                            Text("Bottom Left").tag(ShelfWindowController.ShelfAnchor.bottomLeft)
                            Text("Bottom Right").tag(ShelfWindowController.ShelfAnchor.bottomRight)
                            Text("Top Left").tag(ShelfWindowController.ShelfAnchor.topLeft)
                            Text("Top Right").tag(ShelfWindowController.ShelfAnchor.topRight)
                            Text("Center").tag(ShelfWindowController.ShelfAnchor.center)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 160)
                    }
                }
                #endif

                Text("The Dock icon stays visible so you can always reopen Upmarket, change settings, and quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Save Location") {
                SaveLocationSettingsView(
                    destination: saveDestinationBinding,
                    chosenFolderURL: chosenFolderBinding,
                    title: nil,
                    description: nil,
                    onChooseFolder: chooseSaveFolder,
                    showsCardChrome: false
                )
            }

            Section("History") {
                Toggle("Keep conversion history", isOn: Binding(
                    get: { historyStore.isEnabled },
                    set: { historyStore.isEnabled = $0 }
                ))

                Text("Completed Markdown stays on this Mac for search and copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Saved conversions:") {
                    HStack(spacing: 8) {
                        Text("\(historyStore.records.count)")
                            .foregroundStyle(.secondary)
                        Button("Clear History") {
                            historyStore.clear()
                        }
                        .foregroundStyle(.red)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(historyStore.records.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { AppVisibilityPreference.showDockIcon },
            set: { value in
                AppVisibilityPreference.showDockIcon = value
                showDockIcon = AppVisibilityPreference.showDockIcon
            }
        )
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarIcon },
            set: { value in
                showMenuBarIcon = value
            }
        )
    }

    private var shelfAnchorBinding: Binding<ShelfWindowController.ShelfAnchor> {
        Binding(
            get: { ShelfWindowController.ShelfAnchor(rawValue: shelfAnchorRaw) ?? .center },
            set: { anchor in
                shelfAnchorRaw = anchor.rawValue
                ShelfWindowController.shared.anchor = anchor
                ShelfWindowController.shared.reposition()
            }
        )
    }

    // MARK: - Conversion

    private var conversionTab: some View {
        Form {
            Section("Output") {
                LabeledContent("Format:") {
                    Picker("Output format", selection: outputModeBinding) {
                        ForEach(OutputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }
            }

            MCPIntegrationSection(integration: mcpIntegration)

            Section("AI Models") {
                Text("Advanced models for layout detection and table structure. Required for \"Upmarket + AI\" features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                modelRows
                aiModelStatusRows
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Automation

    private var automationTab: some View {
        Form {
            Section("Watch Folders") {
                if watchedFolderService.folders.isEmpty {
                    watchFolderEmptyRow
                } else {
                    ForEach(watchedFolderService.folders) { folder in
                        watchedFolderRow(folder)
                    }

                    Button {
                        chooseWatchedFolder()
                    } label: {
                        Label("Add Folder…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Section("File Types") {
                Picker("Convert:", selection: watchedInputPresetBinding) {
                    Text("All supported").tag(WatchedInputPreset.all)
                    Text("Documents only").tag(WatchedInputPreset.documents)
                    Text("Documents + images").tag(WatchedInputPreset.documentsAndImages)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Toggle("Skip temporary files", isOn: defaultWatchedExclusionsBinding)
                    .toggleStyle(.checkbox)
                    .font(.subheadline)

                if let watchedFolderError {
                    Label(watchedFolderError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var outputModeBinding: Binding<OutputMode> {
        Binding(
            get: { OutputPreference.shared.mode },
            set: { OutputPreference.shared.mode = $0 }
        )
    }

    private var saveDestinationBinding: Binding<SavePreference.Destination> {
        Binding(
            get: { SavePreference.shared.destination },
            set: { SavePreference.shared.destination = $0 }
        )
    }

    private var chosenFolderBinding: Binding<URL?> {
        Binding(
            get: { SavePreference.shared.chosenFolderURL },
            set: { SavePreference.shared.chosenFolderURL = $0 }
        )
    }

    private var watchedInputPreset: WatchedInputPreset {
        if usesAllWatchedFileTypes {
            return .all
        }
        if patternsEqual(Self.watchDocumentOptions.flatMap(\.patterns), watchedFolderService.includePatterns) {
            return .documents
        }
        if patternsEqual(Self.watchDocumentAndImagePatterns, watchedFolderService.includePatterns) {
            return .documentsAndImages
        }
        return .all
    }

    private var watchedInputPresetBinding: Binding<WatchedInputPreset> {
        Binding(
            get: { watchedInputPreset },
            set: { preset in
                switch preset {
                case .all:
                    watchedFolderService.includePatterns = ""
                case .documents:
                    watchedFolderService.includePatterns = Self.watchDocumentOptions
                        .flatMap(\.patterns)
                        .joined(separator: ", ")
                case .documentsAndImages:
                    watchedFolderService.includePatterns = Self.watchDocumentAndImagePatterns
                        .joined(separator: ", ")
                case .custom:
                    break
                }
            }
        )
    }

    private static var watchDocumentAndImagePatterns: [String] {
        (watchDocumentOptions + watchImageOptions).flatMap(\.patterns)
    }

    private var watchedInputSummary: String {
        let selected = Self.watchIncludeOptions
            .filter { containsAll($0.patterns, in: watchedFolderService.includePatterns) }
            .map(\.title)
        return selected.isEmpty ? "No file types selected" : selected.joined(separator: ", ")
    }

    private var usesAllWatchedFileTypes: Bool {
        watchedFolderService.includePatterns
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var defaultWatchedExclusionPatterns: [String] {
        Self.watchExcludeOptions.flatMap(\.patterns)
    }

    private var usesDefaultWatchedExclusions: Bool {
        containsAll(defaultWatchedExclusionPatterns, in: watchedFolderService.excludePatterns)
    }

    private var defaultWatchedExclusionsBinding: Binding<Bool> {
        Binding(
            get: { usesDefaultWatchedExclusions },
            set: { enabled in
                watchedFolderService.excludePatterns = enabled
                    ? defaultWatchedExclusionPatterns.joined(separator: ", ")
                    : ""
            }
        )
    }

    private func watchedIncludeBinding(for option: WatchPatternOption) -> Binding<Bool> {
        Binding(
            get: {
                usesAllWatchedFileTypes || containsAll(
                    option.patterns,
                    in: watchedFolderService.includePatterns
                )
            },
            set: { enabled in
                if usesAllWatchedFileTypes {
                    watchedFolderService.includePatterns = Self.watchIncludeOptions
                        .flatMap(\.patterns)
                        .joined(separator: ", ")
                }
                watchedFolderService.includePatterns = updatedPatterns(
                    watchedFolderService.includePatterns,
                    setting: option.patterns,
                    enabled: enabled
                )
            }
        )
    }

    private func watchedExcludeBinding(for option: WatchPatternOption) -> Binding<Bool> {
        Binding(
            get: { containsAll(option.patterns, in: watchedFolderService.excludePatterns) },
            set: { enabled in
                watchedFolderService.excludePatterns = updatedPatterns(
                    watchedFolderService.excludePatterns,
                    setting: option.patterns,
                    enabled: enabled
                )
            }
        )
    }

    @ViewBuilder
    private func watchPatternListRow(_ option: WatchPatternOption, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Text(option.title)
                Spacer()
                Text(option.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .help(option.patterns.joined(separator: ", "))
    }

    private func containsAll(_ patterns: [String], in rawPatterns: String) -> Bool {
        let tokens = Set(patternTokens(rawPatterns))
        return patterns
            .map { $0.lowercased() }
            .allSatisfy { tokens.contains($0) }
    }

    private func patternsEqual(_ patterns: [String], _ rawPatterns: String) -> Bool {
        Set(patterns.map { $0.lowercased() }) == Set(patternTokens(rawPatterns))
    }

    private func updatedPatterns(_ rawPatterns: String, setting patterns: [String], enabled: Bool) -> String {
        var tokens = patternTokens(rawPatterns)
        let target = Set(patterns.map { $0.lowercased() })
        if enabled {
            for pattern in patterns.map({ $0.lowercased() }) where !tokens.contains(pattern) {
                tokens.append(pattern)
            }
        } else {
            tokens.removeAll { target.contains($0) }
        }
        return tokens.joined(separator: ", ")
    }

    private func patternTokens(_ rawPatterns: String) -> [String] {
        var seen = Set<String>()
        return rawPatterns
            .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
            .map { String($0).lowercased() }
            .filter { token in
                guard !seen.contains(token) else { return false }
                seen.insert(token)
                return true
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

    private var watchFolderEmptyRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("No folders are being watched.")
                    .font(.subheadline)
                Text("Add a folder to convert new documents as they arrive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Add Folder…") {
                chooseWatchedFolder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func watchedFolderRow(_ folder: WatchedFolder) -> some View {
        HStack(spacing: 8) {
            Label(folder.displayName, systemImage: "folder")
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Picker("Output", selection: Binding(
                get: {
                    watchedFolderService.folder(id: folder.id)?.outputDestination ?? .historyOnly
                },
                set: { destination in
                    if destination == .chosenFolder {
                        chooseWatchedOutputFolder(for: folder.id)
                    } else {
                        watchedFolderService.setOutputDestination(destination, for: folder.id)
                    }
                }
            )) {
                ForEach(WatchedFolderOutputDestination.allCases) { destination in
                    Text(destination.displayName).tag(destination)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 130)

            if (watchedFolderService.folder(id: folder.id)?.outputDestination ?? .historyOnly) == .chosenFolder {
                Button {
                    chooseWatchedOutputFolder(for: folder.id)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(folder.outputDisplayName ?? "Choose output folder")
            }

            Toggle("Notify", isOn: Binding(
                get: {
                    watchedFolderService.folder(id: folder.id)?.notificationsEnabled ?? false
                },
                set: { enabled in
                    watchedFolderService.setNotificationsEnabled(enabled, for: folder.id)
                }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Button(role: .destructive) {
                watchedFolderService.removeFolder(id: folder.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove watched folder")
        }
        .padding(.vertical, 2)
    }

    private func chooseWatchedFolder() {
        watchedFolderError = nil
        guard let url = FileAccessService.shared.chooseDirectory(
            message: "Choose a folder for Upmarket to watch.",
            prompt: "Watch"
        ) else { return }

        do {
            try watchedFolderService.addFolder(url)
        } catch {
            watchedFolderError = FileAccessService.userVisibleMessage(for: error)
        }
    }

    private func chooseWatchedOutputFolder(for id: UUID) {
        watchedFolderError = nil
        guard let url = FileAccessService.shared.chooseDirectory(
            message: "Choose where Upmarket should save watched-folder conversions.",
            prompt: "Choose",
            canCreateDirectories: true
        ) else { return }

        do {
            try watchedFolderService.setOutputFolder(url, for: id)
        } catch {
            watchedFolderError = FileAccessService.userVisibleMessage(for: error)
        }
    }

    @ViewBuilder private var modelRows: some View {
        if !device.supportsAdvancedRuntime {
            Label("Fast conversion available. AI models require Apple Silicon.",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if case .checking = modelManager.installState, modelManager.models.isEmpty {
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
                        Text("Est. \(model.sizeMB) MB")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if model.isDownloaded {
                            Button("Delete") { modelManager.deleteModel(key: model.key) }
                                .foregroundStyle(.red)
                                .buttonStyle(.bordered).controlSize(.mini)
                        } else if modelManager.downloadingModelKey == model.key {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Downloading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            let unavailable = downloadUnavailable(for: model)
                            Button("Download") {
                                modelManager.downloadModel(key: model.key, hasPro: store.hasProOrAbove)
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                            .disabled(unavailable != nil || modelManager.isDownloading)
                            .help(unavailable ?? (modelManager.isDownloading ? "Another model is downloading." : ""))
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
                                    AppBadge("PRO", variant: .accent)
                                }
                            }
                            Text(modelDetail(for: model))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let unavailable = downloadUnavailable(for: model) {
                                Text(unavailable)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var aiModelStatusRows: some View {
        if device.supportsAdvancedRuntime {
            if modelManager.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: modelManager.downloadProgress, total: 100)
                    Text(modelManager.downloadMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let error = modelManager.downloadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if modelManager.downloadedModelCount > 0 {
                LabeledContent("Installed storage:") {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(modelManager.totalStorageUsedFormatted)
                                .foregroundStyle(.secondary)
                            Text(downloadedModelStorageSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button("Delete All") { modelManager.deleteAllModels() }
                            .foregroundStyle(.red)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            }
        }
    }

    private var downloadedModelStorageSummary: String {
        let count = modelManager.downloadedModelCount
        let noun = count == 1 ? "model" : "models"
        return "\(count) \(noun) installed · est. \(modelManager.downloadedModelEstimatedSizeMB) MB"
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

    private func modelDetail(for model: ModelStatus) -> String {
        if model.isDownloaded { return "Ready" }
        if model.error == nil || model.error == "not downloaded" {
            return model.description
        }
        return model.error ?? model.description
    }

    // MARK: - About

    @State private var showAttributions = false

    private var aboutTab: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upmarket").font(.headline)
                        Text(appVersionLabel)
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
        case .none:  return "Not Purchased"
        }
    }

    private var planDetail: String {
        switch store.entitlement {
        case .pro:   return "Unlimited · AI included"
        case .basic: return "Unlimited · One-time purchase"
        case .none:  return "Unlock to continue converting"
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        let baseLabel: String
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            baseLabel = "Version \(version) (\(build))"
        case let (.some(version), .none):
            baseLabel = "Version \(version)"
        case let (.none, .some(build)):
            baseLabel = "Build \(build)"
        case (.none, .none):
            baseLabel = "Version unknown"
        }

        if BuildMetadata.shouldShowCommitInAbout,
           let commit = BuildMetadata.displayCommit {
            return "\(baseLabel) · \(commit)"
        }
        return baseLabel
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

private struct WatchPatternOption: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let patterns: [String]
}

private enum WatchedInputPreset: String, CaseIterable, Identifiable {
    case all
    case documents
    case documentsAndImages
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All supported"
        case .documents: return "Documents"
        case .documentsAndImages: return "Documents + images"
        case .custom: return "Custom…"
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(ModelManager.shared)
        .environmentObject(StoreManager.shared)
        .environmentObject(ConversionHistoryStore.shared)
        .environmentObject(WatchedFolderService.shared)
}
