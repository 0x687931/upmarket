import SwiftUI

struct ModelDownloadView: View {

    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager

    private let device = DeviceCapability.shared
    private let windowSize: AppTheme.WindowSize = .modal

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                header

                if !device.supportsAdvancedRuntime {
                    machineUnavailableView
                } else if modelManager.isDownloading {
                    downloadingView
                } else if let checkError = modelManager.checkError {
                    checkErrorView(checkError)
                } else if let error = modelManager.downloadError {
                    errorView(error)
                } else if case .checking = modelManager.installState {
                    checkingView
                } else {
                    modelList
                    downloadButton
                }
            }
        }
        .padding(windowSize.contentPadding)
        .frame(width: windowSize.width)
        .onAppear { modelManager.checkModels() }
    }

    // MARK: - Header

    private var header: some View {
        AppSectionCard {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(L("models.setup.title"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Upmarket runs entirely on your Mac. Fast conversion works without downloads; optional local models can improve complex documents after a one-time install.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var machineUnavailableView: some View {
        AppSectionCard {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.green)
                Text("Fast conversion is ready")
                    .fontWeight(.medium)
                Text("Enhanced conversion and Upmarket AI require Apple Silicon. This Mac uses native fast conversion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Model List

    private var modelList: some View {
        AppSectionCard(title: "Available Models") {
            VStack(spacing: AppTheme.Spacing.sm) {
                if modelManager.models.isEmpty {
                    AppSectionCard {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text("Fast conversion ready")
                                    .fontWeight(.medium)
                                Text("No optional local models were reported for this build.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                // Pro tier: Python runtime + layout models (required for Enhanced conversion)
                ForEach(modelManager.models.filter { $0.tier == "pro" && $0.key != "upmarket_ai" }, id: \.key) { model in
                    let asset = ModelAsset(rawValue: model.key)
                    let gateReason = asset.flatMap { modelManager.gate(tier: store.tier).downloadUnavailableReason(for: $0) }
                    modelRow(
                        key: model.key,
                        icon: model.key == ModelAsset.pythonRuntime.rawValue ? "cpu" : "doc.text.magnifyingglass",
                        title: model.name,
                        description: gateReason ?? model.error ?? model.description,
                        sizeMB: model.sizeMB,
                        isDownloaded: model.isDownloaded,
                        badge: nil,
                        available: model.isAvailable && gateReason == nil
                    )
                }

                if store.tier >= .max {
                    ForEach(modelManager.models.filter { $0.tier == "max" }, id: \.key) { model in
                        let gateReason = modelManager.gate(tier: store.tier).downloadUnavailableReason(for: .upmarketAI)
                        modelRow(
                            key: model.key,
                            icon: "sparkles",
                            title: model.name,
                            description: gateReason ?? model.error ?? model.description,
                            sizeMB: model.sizeMB,
                            isDownloaded: model.isDownloaded,
                            badge: "MAX",
                            available: model.isAvailable && gateReason == nil
                        )
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
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if let badge {
                            AppBadge(badge, variant: .accent)
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(isDownloaded ? "Ready" : available ? "\(sizeMB) MB" : "Unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isDownloaded ? Color.green : .secondary)

                    if isDownloaded {
                        Button("Delete") {
                            modelManager.deleteModel(key: key)
                        }
                        .buttonStyle(AppActionButtonStyle())
                        .controlSize(.small)
                    } else if available {
                        Button("Download") {
                            modelManager.downloadAsset(ModelAsset(rawValue: key) ?? .upmarketAI, gate: modelManager.gate(tier: store.tier))
                        }
                        .buttonStyle(AppActionButtonStyle())
                        .controlSize(.small)
                    }
                }
            }
        }
        .opacity(available ? 1.0 : 0.75)
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        AppSectionCard(title: "Downloads") {
            VStack(spacing: AppTheme.Spacing.sm) {
            // Basic tier: Python runtime — shown to Basic+ users on Apple Silicon
            if modelManager.gate(tier: store.tier).downloadUnavailableReason(for: .pythonRuntime) == nil {
                let runtimeReady = modelManager.downloadedAssets.contains(.pythonRuntime)
                if !runtimeReady {
                    Button {
                        modelManager.downloadAssets(for: .enhanced, gate: modelManager.gate(tier: store.tier))
                    } label: {
                        Label("Download Upmarket Runtime — \(modelManager.runtimeSizeMB) MB", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .controlSize(.large)
                }
            }

            // Max tier: AI model weights — shown to Max users once runtime is ready
            if modelManager.gate(tier: store.tier).downloadUnavailableReason(for: .upmarketAI) == nil {
                let proReady = modelManager.models.filter { $0.tier == "max" }.allSatisfy(\.isDownloaded)
                if !proReady {
                    Button {
                        modelManager.downloadAssets(for: .ai, gate: modelManager.gate(tier: store.tier))
                    } label: {
                        Label("Download Upmarket AI — \(modelManager.proSizeMB) MB", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .controlSize(.large)
                }
            }

            Text("Requires internet for initial download only. All processing is offline.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        }
    }

    // MARK: - Downloading

    private var checkingView: some View {
        AppSectionCard {
            VStack(spacing: AppTheme.Spacing.md) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking local model files…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var downloadingView: some View {
        AppSectionCard {
            VStack(spacing: AppTheme.Spacing.lg) {
                // Variable Colour symbol fills as download progresses (macOS 15+)
                // Falls back to standard progress bar on older OS
                if #available(macOS 15.0, *) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "arrow.down.circle", variableValue: modelManager.downloadProgress / 100)
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse, isActive: true)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(modelManager.downloadMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(Int(modelManager.downloadProgress))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                    }
                }
                ProgressView(value: modelManager.downloadProgress, total: 100)
                    .progressViewStyle(.linear)

                HStack {
                    Text(modelManager.downloadMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(modelManager.downloadProgress))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }

    // MARK: - Error

    private func checkErrorView(_ error: String) -> some View {
        AppSectionCard {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                Text("Model check failed")
                    .fontWeight(.medium)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Check Again") {
                    modelManager.checkModels()
                }
                .buttonStyle(AppActionButtonStyle())
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        AppSectionCard {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                Text(L("models.status.failed"))
                    .fontWeight(.medium)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    if modelManager.gate(tier: store.tier).downloadUnavailableReason(for: .upmarketAI) == nil {
                        modelManager.downloadAssets(for: .ai, gate: modelManager.gate(tier: store.tier))
                    } else {
                        modelManager.checkModels()
                    }
                }
                .buttonStyle(AppActionButtonStyle())
            }
        }
    }

}

#Preview {
    ModelDownloadView()
        .environmentObject(ModelManager.shared)
        .environmentObject(StoreManager.shared)
}
