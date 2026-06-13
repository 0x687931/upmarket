import SwiftUI
import AppKit

// MARK: - Tab model

private enum PrefTab: CaseIterable, Equatable {
    case general, conversion, automation, about

    var label: String {
        switch self {
        case .general:    return "General"
        case .conversion: return "Conversion"
        case .automation: return "Automation"
        case .about:      return "About"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "gearshape.fill"
        case .conversion: return "doc.text.fill"
        case .automation: return "cpu.fill"
        case .about:      return "info.circle.fill"
        }
    }
}

// MARK: - Main view

struct PreferencesView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var watchedFolderService: WatchedFolderService

    @StateObject private var mcpIntegration = MCPIntegrationService.shared
    private let device = DeviceCapability.shared
    @State private var selectedTab: PrefTab = .general
    @State private var watchedFolderError: String?
    @State private var showAttributions = false
    @AppStorage(AppVisibilityPreference.showDockIconKey) private var showDockIcon = AppVisibilityPreference.defaultShowDockIcon
    @AppStorage(AppVisibilityPreference.showMenuBarIconKey) private var showMenuBarIcon = AppVisibilityPreference.defaultShowMenuBarIcon
    @AppStorage(AppVisibilityPreference.showShelfKey) private var showShelf = AppVisibilityPreference.defaultShowShelf
    @AppStorage("upmarket.shelfAnchor") private var shelfAnchorRaw: Int = ShelfWindowController.ShelfAnchor.center.rawValue

    private static let watchDocumentOptions: [WatchPatternOption] = [
        WatchPatternOption(title: "PDF",    detail: ".pdf",  patterns: ["*.pdf"]),
        WatchPatternOption(title: "Word",   detail: ".docx", patterns: ["*.docx"]),
        WatchPatternOption(title: "Slides", detail: ".pptx", patterns: ["*.pptx"]),
        WatchPatternOption(title: "Sheets", detail: ".xlsx", patterns: ["*.xlsx"]),
        WatchPatternOption(title: "HTML",   detail: ".html", patterns: ["*.html", "*.htm"]),
        WatchPatternOption(title: "Text",   detail: ".txt",  patterns: ["*.txt"]),
        WatchPatternOption(title: "EPUB",   detail: ".epub", patterns: ["*.epub"]),
        WatchPatternOption(title: "ZIP",    detail: ".zip",  patterns: ["*.zip"]),
        WatchPatternOption(title: "CSV",    detail: ".csv",  patterns: ["*.csv"]),
        WatchPatternOption(title: "XML",    detail: ".xml",  patterns: ["*.xml"]),
    ]
    private static let watchImageOptions: [WatchPatternOption] = [
        WatchPatternOption(title: "PNG",  detail: ".png",  patterns: ["*.png"]),
        WatchPatternOption(title: "JPEG", detail: ".jpg",  patterns: ["*.jpg", "*.jpeg"]),
        WatchPatternOption(title: "GIF",  detail: ".gif",  patterns: ["*.gif"]),
        WatchPatternOption(title: "TIFF", detail: ".tiff", patterns: ["*.tif", "*.tiff"]),
    ]
    private static let watchAudioOptions: [WatchPatternOption] = [
        WatchPatternOption(title: "MP3/M4A",  detail: ".mp3 .m4a", patterns: ["*.mp3", "*.m4a"]),
        WatchPatternOption(title: "WAV/AIFF", detail: "+ Opus",     patterns: ["*.wav", "*.aiff", "*.opus"]),
    ]
    private static let watchIncludeOptions = watchDocumentOptions + watchImageOptions + watchAudioOptions
    private static let watchExcludeOptions: [WatchPatternOption] = [
        WatchPatternOption(title: "Converted outputs",   detail: "Markdown and JSON",          patterns: ["*.md", "*.markdown", "*.json"]),
        WatchPatternOption(title: "Temporary downloads", detail: "Partial download files",      patterns: ["*.tmp", "*.download", "*.part", "*.crdownload", "~$*"]),
        WatchPatternOption(title: "Drafts",              detail: "Files with 'draft' in name",  patterns: ["*draft*"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:    generalTabContent
                    case .conversion: conversionTabContent
                    case .automation: automationTabContent
                    case .about:      aboutTabContent
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: AppTheme.WindowSize.preferences.width,
               maxWidth: AppTheme.WindowSize.preferences.width,
               minHeight: 400)
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
            if !showShelf { ShelfWindowController.shared.hide(animate: false) }
            modelManager.checkModels()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PrefTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
    }

    private func tabButton(_ tab: PrefTab) -> some View {
        let isActive = selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13))
                    Text(tab.label)
                        .font(isActive ? .body.weight(.semibold) : .body.weight(.medium))
                }
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 9)

                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("PrefsTab_\(tab.label)")
    }

    // MARK: - Section header

    private func sectionHeader(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
        }
    }

    // MARK: - General tab

    private var generalTabContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            // App Visibility
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "app.badge", color: AppTheme.Colour.sectionBlue, title: "App Visibility")
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show Dock icon", isOn: dockIconBinding)
                        .toggleStyle(.checkbox)
                        .disabled(AppVisibilityPreference.requiresDockIcon)
                        .accessibilityIdentifier("PrefsDockIconToggle")
                    Toggle("Show menu bar icon", isOn: menuBarIconBinding)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("PrefsMenuBarIconToggle")
                    Text("The Dock icon stays visible so you can always reopen Upmarket, change settings, and quit.")
                        .font(AppTheme.Font.caption).foregroundStyle(.secondary)
                }
                .padding(.leading, 38)
            }

            // Shelf Widget
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "sidebar.right", color: Color.accentColor, title: "Shelf Widget")
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show shelf", isOn: $showShelf)
                        .toggleStyle(.checkbox)
                        .onChange(of: showShelf) { show in
                            if show { ShelfWindowController.shared.show() }
                            else    { ShelfWindowController.shared.hide(animate: false) }
                        }
                    if showShelf {
                        LabeledContent("Position:") {
                            Picker("", selection: shelfAnchorBinding) {
                                Text("Bottom Left").tag(ShelfWindowController.ShelfAnchor.bottomLeft)
                                Text("Bottom Right").tag(ShelfWindowController.ShelfAnchor.bottomRight)
                                Text("Top Left").tag(ShelfWindowController.ShelfAnchor.topLeft)
                                Text("Top Right").tag(ShelfWindowController.ShelfAnchor.topRight)
                                Text("Center").tag(ShelfWindowController.ShelfAnchor.center)
                            }
                            .pickerStyle(.menu).labelsHidden().frame(maxWidth: 160)
                        }
                    }
                }
                .padding(.leading, 38)
            }

            // Save Location
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "folder.fill", color: AppTheme.Colour.sectionGreen, title: "Save Location")
                VStack(alignment: .leading, spacing: 10) {
                    SaveLocationSettingsView(
                        destination: saveDestinationBinding,
                        chosenFolderURL: chosenFolderBinding,
                        title: nil,
                        description: nil,
                        onChooseFolder: chooseSaveFolder,
                        showsCardChrome: false
                    )
                }
                .padding(.leading, 38)
            }
        }
    }

    // MARK: - Conversion tab

    private var conversionTabContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Output Format
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "doc.text", color: Color.accentColor, title: "Output Format")
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Format:") {
                        Picker("", selection: outputModeBinding) {
                            ForEach(OutputMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
                    }
                    Divider()
                    Toggle("Advertise to LM Studio (MCP)", isOn: Binding(
                        get: { mcpIntegration.isEnabled },
                        set: { mcpIntegration.setAdvertisementEnabled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    if mcpIntegration.isEnabled {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Label(mcpIntegration.status.displayText, systemImage: mcpIntegration.status.systemImage)
                                .font(AppTheme.Font.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Add to LM Studio…") { mcpIntegration.addToLMStudio() }
                                .buttonStyle(AppBorderedButtonStyle()).controlSize(.mini)
                                .disabled(mcpIntegration.status == .commandMissing)
                        }
                    }
                }
                .padding(.leading, 38)
            }

            // AI Models
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "sparkles", color: AppTheme.Colour.sectionPurple, title: "AI Models")
                VStack(spacing: AppTheme.Spacing.sm) {
                    modelsContent
                }
                .padding(.leading, 38)
            }
        }
    }

    // MARK: - Models content (moved from dedicated tab)

    @ViewBuilder private var modelsContent: some View {
        if !device.isAppleSilicon {
            AppSectionCard {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32)).foregroundStyle(Color.green)
                    Text("Fast conversion is ready").fontWeight(.medium)
                    Text("Enhanced conversion requires Apple Silicon.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        } else if modelManager.isDownloading {
            AppSectionCard { downloadProgressRow }
        } else if let error = modelManager.checkError {
            AppSectionCard {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32)).foregroundStyle(.red)
                    Text("Model check failed").fontWeight(.medium)
                    Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Check Again") { modelManager.checkModels() }
                        .buttonStyle(AppActionButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
        } else if let error = modelManager.downloadError {
            AppSectionCard {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32)).foregroundStyle(.red)
                    Text("Download failed").fontWeight(.medium)
                    Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try Again") {
                        if modelManager.gate(tier: store.tier).downloadUnavailableReason(for: .upmarketAI) == nil {
                            modelManager.downloadAssets(for: .ai, gate: modelManager.gate(tier: store.tier))
                        } else { modelManager.checkModels() }
                    }
                    .buttonStyle(AppActionButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
        } else if case .checking = modelManager.installState {
            AppSectionCard {
                VStack(spacing: AppTheme.Spacing.md) {
                    ProgressView().controlSize(.small)
                    Text("Checking local model files…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            modelsListCard
            modelsDownloadCard
        }
    }

    private var modelsListCard: some View {
        AppSectionCard(title: "Available") {
            VStack(spacing: AppTheme.Spacing.sm) {
                if modelManager.models.isEmpty {
                    AppSectionCard {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green).font(.title3)
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text("Fast conversion ready").fontWeight(.medium)
                                Text("No optional models for this build.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                ForEach(modelManager.models.filter { $0.tier == "pro" && $0.key != "upmarket_ai" }, id: \.key) { model in
                    let asset = ModelAsset(rawValue: model.key)
                    let reason = asset.flatMap { modelManager.gate(tier: store.tier).downloadUnavailableReason(for: $0) }
                    modelRow(key: model.key,
                             icon: model.key == ModelAsset.pythonRuntime.rawValue ? "cpu" : "doc.text.magnifyingglass",
                             title: model.name,
                             description: reason ?? model.error ?? model.description,
                             sizeMB: model.sizeMB, isDownloaded: model.isDownloaded,
                             badge: nil, available: model.isAvailable && reason == nil)
                }
                if store.tier >= .max {
                    ForEach(modelManager.models.filter { $0.tier == "max" }, id: \.key) { model in
                        let reason = modelManager.gate(tier: store.tier).downloadUnavailableReason(for: .upmarketAI)
                        modelRow(key: model.key, icon: "sparkles", title: model.name,
                                 description: reason ?? model.error ?? model.description,
                                 sizeMB: model.sizeMB, isDownloaded: model.isDownloaded,
                                 badge: "MAX", available: model.isAvailable && reason == nil)
                    }
                }
            }
        }
    }

    private func modelRow(key: String, icon: String, title: String, description: String, sizeMB: Int, isDownloaded: Bool, badge: String?, available: Bool) -> some View {
        AppSectionCard {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill((isDownloaded ? Color.green : Color.accentColor).opacity(0.10))
                        .frame(width: 28, height: 28)
                    Image(systemName: isDownloaded ? "checkmark" : icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isDownloaded ? Color.green : Color.accentColor)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(title).font(.subheadline.weight(.semibold))
                        if let badge { AppBadge(badge, variant: .accent) }
                    }
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(isDownloaded ? "Ready" : available ? "\(sizeMB) MB" : "Unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isDownloaded ? Color.green : .secondary)
                    if isDownloaded {
                        Button("Delete") { modelManager.deleteModel(key: key) }
                            .buttonStyle(AppActionButtonStyle()).controlSize(.small)
                    } else if available {
                        Button("Download") { modelManager.downloadAsset(ModelAsset(rawValue: key) ?? .upmarketAI, gate: modelManager.gate(tier: store.tier)) }
                            .buttonStyle(AppActionButtonStyle()).controlSize(.small)
                    }
                }
            }
        }
        .opacity(available ? 1.0 : 0.75)
    }

    private var modelsDownloadCard: some View {
        AppSectionCard(title: "Downloads") {
            VStack(spacing: AppTheme.Spacing.sm) {
                if modelManager.gate(tier: store.tier).downloadUnavailableReason(for: .pythonRuntime) == nil,
                   !modelManager.downloadedAssets.contains(.pythonRuntime) {
                    Button {
                        modelManager.downloadAssets(for: .enhanced, gate: modelManager.gate(tier: store.tier))
                    } label: {
                        Label("Download Enhanced Runtime — \(modelManager.runtimeSizeMB) MB",
                              systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity).fontWeight(.semibold)
                    }
                    .buttonStyle(AppProminentButtonStyle()).controlSize(.large)
                }
                if modelManager.gate(tier: store.tier).downloadUnavailableReason(for: .upmarketAI) == nil {
                    let proReady = modelManager.models.filter { $0.tier == "max" }.allSatisfy(\.isDownloaded)
                    if !proReady {
                        Button {
                            modelManager.downloadAssets(for: .ai, gate: modelManager.gate(tier: store.tier))
                        } label: {
                            Label("Download Upmarket AI — \(modelManager.proSizeMB) MB", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppBorderedButtonStyle()).controlSize(.large)
                    }
                }
                Text("Internet required only for initial download. All conversion runs offline.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var downloadProgressRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 10) {
                if #available(macOS 15.0, *) {
                    Image(systemName: "arrow.down.circle", variableValue: modelManager.downloadProgress / 100)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.pulse, isActive: true)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(modelManager.downloadMessage)
                    .font(AppTheme.Font.body)
                Spacer()
                Text("\(Int(modelManager.downloadProgress))%")
                    .font(AppTheme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: modelManager.downloadProgress, total: 100)
                .progressViewStyle(.linear)
        }
    }

    // MARK: - Automation tab

    private var automationTabContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Watched Folders
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "folder.badge.gearshape", color: AppTheme.Colour.sectionAmber, title: "Watched Folders")
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if watchedFolderService.folders.isEmpty {
                        watchFolderEmptyState
                    } else {
                        ForEach(watchedFolderService.folders) { folder in watchedFolderRow(folder) }
                        Button {
                            chooseWatchedFolder()
                        } label: {
                            Label("Add Folder…", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(AppBorderedButtonStyle()).controlSize(.small)
                    }
                    if let watchedFolderError {
                        Label(watchedFolderError, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTheme.Font.caption).foregroundStyle(.red)
                    }
                }
                .padding(.leading, 38)
            }

            // File Types
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "slider.horizontal.3", color: AppTheme.Colour.sectionRed, title: "File Types")
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: watchedInputPresetBinding) {
                        Text("All supported").tag(WatchedInputPreset.all)
                        Text("Documents only").tag(WatchedInputPreset.documents)
                        Text("Documents + images").tag(WatchedInputPreset.documentsAndImages)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Toggle("Skip temporary files", isOn: defaultWatchedExclusionsBinding)
                        .toggleStyle(.checkbox)
                }
                .padding(.leading, 38)
            }
        }
    }

    private var watchFolderEmptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            VStack(spacing: 6) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 24))
                    .foregroundStyle(AppTheme.Colour.textTertiary)
                Text("No folders watched yet")
                    .font(AppTheme.Font.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .strokeBorder(AppTheme.Colour.separator, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .background(AppTheme.Colour.subtleFill.clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)))

            Button("Add Folder…") { chooseWatchedFolder() }
                .buttonStyle(AppBorderedButtonStyle())
                .controlSize(.small)
        }
    }

    private func watchedFolderRow(_ folder: WatchedFolder) -> some View {
        HStack(spacing: 8) {
            Label(folder.displayName, systemImage: "folder")
                .font(AppTheme.Font.body).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Picker("Output", selection: Binding(
                get: { watchedFolderService.folder(id: folder.id)?.outputDestination ?? .historyOnly },
                set: { destination in
                    if destination == .chosenFolder { chooseWatchedOutputFolder(for: folder.id) }
                    else { watchedFolderService.setOutputDestination(destination, for: folder.id) }
                }
            )) {
                ForEach(WatchedFolderOutputDestination.allCases) { d in Text(d.displayName).tag(d) }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.small).frame(width: 120)
            if (watchedFolderService.folder(id: folder.id)?.outputDestination ?? .historyOnly) == .chosenFolder {
                Button { chooseWatchedOutputFolder(for: folder.id) } label: { Image(systemName: "folder") }
                    .buttonStyle(AppActionButtonStyle()).controlSize(.small)
                    .help(folder.outputDisplayName ?? "Choose output folder")
            }
            Toggle("Notify", isOn: Binding(
                get: { watchedFolderService.folder(id: folder.id)?.notificationsEnabled ?? false },
                set: { watchedFolderService.setNotificationsEnabled($0, for: folder.id) }
            )).toggleStyle(.checkbox).controlSize(.small)
            Button(role: .destructive) { watchedFolderService.removeFolder(id: folder.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(AppActionButtonStyle()).foregroundStyle(.red).controlSize(.small)
            .help("Remove watched folder")
        }
    }

    // MARK: - About tab

    private var aboutTabContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            // App
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "shippingbox.fill", color: Color.accentColor, title: "App")
                HStack(spacing: 14) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable().frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.appIcon, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upmarket").font(AppTheme.Font.body.weight(.semibold))
                        Text(appVersionLabel).font(AppTheme.Font.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.Colour.subtleFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.Colour.separator, lineWidth: 1)
                )
                .padding(.leading, 38)
            }

            // Plan
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(icon: "crown.fill", color: AppTheme.Colour.sectionAmber, title: "Plan")
                VStack(alignment: .leading, spacing: 10) {
                    planCard
                    if store.tier < .max {
                        Button("Upgrade") {
                            NotificationCenter.default.post(name: .showPaywall, object: nil)
                        }
                        .buttonStyle(AppProminentButtonStyle()).controlSize(.small)
                    }
                    Button("Restore Purchases") { Task { await store.restorePurchases() } }
                        .buttonStyle(AppPlainButtonStyle()).foregroundStyle(.secondary)
                        .controlSize(.small)
                        .accessibilityIdentifier("PrefsRestorePurchasesButton")
                }
                .padding(.leading, 38)
            }

            // Links
            AppSectionCard {
                HStack(spacing: 0) {
                    linkButton(icon: "lock.shield", label: "Privacy",
                               url: "https://0x687931.github.io/upmarket/privacy")
                    Divider().frame(height: 28)
                    linkButton(icon: "envelope", label: "Support", url: "mailto:support@upmarket.app")
                    Divider().frame(height: 28)
                    linkButton(icon: "star", label: "Rate", url: "macappstore://")
                    if !openSourcePackages.isEmpty {
                        Divider().frame(height: 28)
                        Button {
                            showAttributions = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 14)).foregroundStyle(Color.accentColor)
                                Text("Licenses")
                                    .font(AppTheme.Font.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(AppSubtleRowButtonStyle())
                        .sheet(isPresented: $showAttributions) {
                            AttributionsSheet(groups: licenseGroups)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Plan card

    private var planCard: some View {
        let config = planCardConfig
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: config.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(config.iconColor)
                Text(config.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Text(config.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
                .padding(.leading, 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(config.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(config.borderColor, lineWidth: config.borderWidth)
        )
    }

    private var planCardConfig: PlanCardConfig {
        switch store.tier {
        case .basic:
            return PlanCardConfig(
                name: "Upmarket Basic",
                detail: "Unlimited · Native conversion",
                icon: "checkmark.circle",
                iconColor: .secondary,
                fill: AppTheme.Colour.subtleFill,
                borderColor: AppTheme.Colour.separator,
                borderWidth: 1
            )
        case .pro:
            return PlanCardConfig(
                name: "Upmarket Pro",
                detail: "Unlimited · Enhanced conversion",
                icon: "checkmark.circle.fill",
                iconColor: Color.accentColor,
                fill: Color.accentColor.opacity(0.06),
                borderColor: Color.accentColor,
                borderWidth: 1.5
            )
        case .max:
            return PlanCardConfig(
                name: "Upmarket Max",
                detail: "Unlimited · AI pipeline included",
                icon: "crown.fill",
                iconColor: AppTheme.Colour.sectionAmber,
                fill: AppTheme.Colour.sectionAmber.opacity(0.06),
                borderColor: AppTheme.Colour.sectionAmber,
                borderWidth: 1.5
            )
        }
    }

    private func linkButton(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor)
                Text(label).font(AppTheme.Font.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(AppSubtleRowButtonStyle())
    }

    // MARK: - Bindings

    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { AppVisibilityPreference.showDockIcon },
            set: { AppVisibilityPreference.showDockIcon = $0; showDockIcon = AppVisibilityPreference.showDockIcon }
        )
    }
    private var menuBarIconBinding: Binding<Bool> {
        Binding(get: { showMenuBarIcon }, set: { showMenuBarIcon = $0 })
    }
    private var shelfAnchorBinding: Binding<ShelfWindowController.ShelfAnchor> {
        Binding(
            get: { ShelfWindowController.ShelfAnchor(rawValue: shelfAnchorRaw) ?? .center },
            set: { anchor in shelfAnchorRaw = anchor.rawValue; ShelfWindowController.shared.anchor = anchor; ShelfWindowController.shared.reposition() }
        )
    }
    private var outputModeBinding: Binding<OutputMode> {
        Binding(get: { OutputPreference.shared.mode }, set: { OutputPreference.shared.mode = $0 })
    }
    private var saveDestinationBinding: Binding<SavePreference.Destination> {
        Binding(get: { SavePreference.shared.destination }, set: { SavePreference.shared.destination = $0 })
    }
    private var chosenFolderBinding: Binding<URL?> {
        Binding(get: { SavePreference.shared.chosenFolderURL }, set: { SavePreference.shared.chosenFolderURL = $0 })
    }
    private var watchedInputPreset: WatchedInputPreset {
        if usesAllWatchedFileTypes { return .all }
        if patternsEqual(Self.watchDocumentOptions.flatMap(\.patterns), watchedFolderService.includePatterns) { return .documents }
        if patternsEqual(Self.watchDocumentAndImagePatterns, watchedFolderService.includePatterns) { return .documentsAndImages }
        return .all
    }
    private var watchedInputPresetBinding: Binding<WatchedInputPreset> {
        Binding(
            get: { watchedInputPreset },
            set: { preset in
                switch preset {
                case .all:                watchedFolderService.includePatterns = ""
                case .documents:          watchedFolderService.includePatterns = Self.watchDocumentOptions.flatMap(\.patterns).joined(separator: ", ")
                case .documentsAndImages: watchedFolderService.includePatterns = Self.watchDocumentAndImagePatterns.joined(separator: ", ")
                case .custom:             break
                }
            }
        )
    }
    private static var watchDocumentAndImagePatterns: [String] {
        (watchDocumentOptions + watchImageOptions).flatMap(\.patterns)
    }
    private var usesAllWatchedFileTypes: Bool {
        watchedFolderService.includePatterns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var defaultWatchedExclusionPatterns: [String] { Self.watchExcludeOptions.flatMap(\.patterns) }
    private var usesDefaultWatchedExclusions: Bool {
        containsAll(defaultWatchedExclusionPatterns, in: watchedFolderService.excludePatterns)
    }
    private var defaultWatchedExclusionsBinding: Binding<Bool> {
        Binding(
            get: { usesDefaultWatchedExclusions },
            set: { watchedFolderService.excludePatterns = $0 ? defaultWatchedExclusionPatterns.joined(separator: ", ") : "" }
        )
    }

    // MARK: - Pattern helpers

    private func containsAll(_ patterns: [String], in rawPatterns: String) -> Bool {
        let tokens = Set(patternTokens(rawPatterns))
        return patterns.map { $0.lowercased() }.allSatisfy { tokens.contains($0) }
    }
    private func patternsEqual(_ patterns: [String], _ rawPatterns: String) -> Bool {
        Set(patterns.map { $0.lowercased() }) == Set(patternTokens(rawPatterns))
    }
    private func patternTokens(_ rawPatterns: String) -> [String] {
        var seen = Set<String>()
        return rawPatterns
            .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
            .map { String($0).lowercased() }
            .filter { seen.insert($0).inserted }
    }

    // MARK: - Folder actions

    private func chooseSaveFolder() {
        if let url = FileAccessService.shared.chooseSaveDirectory(message: "Upmarket will save converted files here.") {
            SavePreference.shared.chosenFolderURL = url
            SavePreference.shared.destination = .chosenFolder
        }
    }
    private func chooseWatchedFolder() {
        watchedFolderError = nil
        guard let url = FileAccessService.shared.chooseDirectory(message: "Choose a folder for Upmarket to watch.", prompt: "Watch") else { return }
        do { try watchedFolderService.addFolder(url) } catch { watchedFolderError = FileAccessService.userVisibleMessage(for: error) }
    }
    private func chooseWatchedOutputFolder(for id: UUID) {
        watchedFolderError = nil
        guard let url = FileAccessService.shared.chooseDirectory(message: "Choose where Upmarket should save watched-folder conversions.", prompt: "Choose", canCreateDirectories: true) else { return }
        do { try watchedFolderService.setOutputFolder(url, for: id) } catch { watchedFolderError = FileAccessService.userVisibleMessage(for: error) }
    }

    // MARK: - About helpers

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let base: String
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(v), .some(b)): base = "Version \(v) (\(b))"
        case let (.some(v), .none):    base = "Version \(v)"
        case let (.none,    .some(b)): base = "Build \(b)"
        case (.none, .none):           base = "Version unknown"
        }
        if BuildMetadata.shouldShowCommitInAbout, let commit = BuildMetadata.displayCommit {
            return "\(base) · \(commit)"
        }
        return base
    }
    private var openSourcePackages: [LicenseEntry] {
        guard let url = Bundle.main.url(forResource: "licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([LicenseEntry].self, from: data)
        else { return [] }
        return entries
    }
    private var licenseGroups: [LicenseGroup] {
        let packages = openSourcePackages
        guard !packages.isEmpty else { return [] }
        var buckets: [String: [LicenseEntry]] = [:]
        for pkg in packages { buckets[normalisedFamily(pkg.license), default: []].append(pkg) }
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
}

// MARK: - Plan card config

private struct PlanCardConfig {
    let name: String
    let detail: String
    let icon: String
    let iconColor: Color
    let fill: Color
    let borderColor: Color
    let borderWidth: CGFloat
}

// MARK: - Attributions sheet

struct AttributionsSheet: View {
    let groups: [LicenseGroup]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attributions").font(.headline)
                    Text("Open-source packages used by Upmarket.")
                        .font(AppTheme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    ForEach(groups) { group in
                        AppSectionCard(title: group.family) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.packages.enumerated()), id: \.element.id) { index, pkg in
                                    Button {
                                        if let url = URL(string: pkg.url) { NSWorkspace.shared.open(url) }
                                    } label: {
                                        HStack(spacing: AppTheme.Spacing.md) {
                                            Text(pkg.name).foregroundStyle(.primary)
                                            Spacer()
                                            Text(pkg.version).foregroundStyle(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                        .padding(.horizontal, AppTheme.Spacing.md)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(AppSubtleRowButtonStyle())
                                    if index < group.packages.count - 1 {
                                        Divider().padding(.leading, AppTheme.Spacing.md)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
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
    case all, documents, documentsAndImages, custom
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .all:                return "All supported"
        case .documents:          return "Documents"
        case .documentsAndImages: return "Documents + images"
        case .custom:             return "Custom…"
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(ModelManager.shared)
        .environmentObject(StoreManager.shared)
        .environmentObject(WatchedFolderService.shared)
}
