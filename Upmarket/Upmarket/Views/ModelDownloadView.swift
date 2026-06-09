import SwiftUI

struct ModelDownloadView: View {

    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager

    private let device = DeviceCapability.shared
    private let windowSize: AppTheme.WindowSize = .thin

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
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
        .padding(windowSize.contentPadding)
        .frame(width: 480)
        .onAppear { modelManager.checkModels() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("#")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)

            Text(L("models.setup.title"))
                .font(.title2)
                .fontWeight(.bold)

            Text("Upmarket runs entirely on your Mac. Fast conversion works without downloads; optional local models can improve complex documents after a one-time install.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var machineUnavailableView: some View {
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
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    // MARK: - Model List

    private var modelList: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if modelManager.models.isEmpty {
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
                .padding(AppTheme.Spacing.md)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }

            // Basic tier: Python runtime (required for Enhanced + AI)
            ForEach(modelManager.models.filter { $0.tier == "basic" }, id: \.key) { model in
                let gateReason = modelManager.basicDownloadUnavailableReason(hasBasic: store.hasBasicOrAbove)
                modelRow(
                    icon: "cpu",
                    title: model.name,
                    description: gateReason ?? model.error ?? model.description,
                    sizeMB: model.sizeMB,
                    isDownloaded: model.isDownloaded,
                    badge: nil,
                    available: model.isAvailable && gateReason == nil
                )
            }

            // Enhanced tier: layout/table models
            ForEach(modelManager.models.filter { $0.tier == "enhanced" }, id: \.key) { model in
                modelRow(
                    icon: "doc.text.magnifyingglass",
                    title: model.name,
                    description: model.error ?? model.description,
                    sizeMB: model.sizeMB,
                    isDownloaded: model.isDownloaded,
                    badge: nil,
                    available: model.isAvailable
                )
            }

            if store.hasProOrAbove {
                ForEach(modelManager.models.filter { $0.tier == "pro" }, id: \.key) { model in
                    let gateReason = modelManager.proDownloadUnavailableReason(hasPro: store.hasProOrAbove)
                    modelRow(
                        icon: "sparkles",
                        title: model.name,
                        description: gateReason ?? model.error ?? model.description,
                        sizeMB: model.sizeMB,
                        isDownloaded: model.isDownloaded,
                        badge: "PRO",
                        available: model.isAvailable && gateReason == nil
                    )
                }
            }
        }
    }

    private func modelRow(icon: String, title: String, description: String, sizeMB: Int, isDownloaded: Bool, badge: String?, available: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: isDownloaded ? "checkmark.circle.fill" : icon)
                .foregroundStyle(isDownloaded ? Color.green : Color.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(title)
                        .fontWeight(.medium)
                    if let badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppTheme.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(isDownloaded ? "Ready" : available ? "\(sizeMB) MB" : "—")
                .font(.caption)
                .foregroundStyle(isDownloaded ? Color.green : .secondary)
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .opacity(available ? 1.0 : 0.5)
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Basic tier: Python runtime — shown to Basic+ users on Apple Silicon
            if modelManager.basicDownloadUnavailableReason(hasBasic: store.hasBasicOrAbove) == nil {
                let runtimeReady = modelManager.runtimeDownloaded
                if !runtimeReady {
                    Button {
                        modelManager.downloadBasicRuntime(hasBasic: store.hasBasicOrAbove)
                    } label: {
                        Label("Download Upmarket Runtime — \(modelManager.runtimeSizeMB) MB", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            // Pro tier: AI model weights — shown to Pro users once runtime is ready
            if modelManager.proDownloadUnavailableReason(hasPro: store.hasProOrAbove) == nil {
                let proReady = modelManager.models.filter { $0.tier == "pro" }.allSatisfy(\.isDownloaded)
                if !proReady {
                    Button {
                        modelManager.downloadProModels(hasPro: store.hasProOrAbove)
                    } label: {
                        Label("Download Upmarket AI — \(modelManager.proSizeMB) MB", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Text("Requires internet for initial download only. All processing is offline.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Downloading

    private var checkingView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView()
                .controlSize(.small)
            Text("Checking local model files...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var downloadingView: some View {
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

    // MARK: - Error

    private func checkErrorView(_ error: String) -> some View {
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
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorView(_ error: String) -> some View {
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
                if modelManager.proDownloadUnavailableReason(hasPro: store.hasProOrAbove) == nil {
                    modelManager.downloadProModels(hasPro: store.hasProOrAbove)
                } else {
                    modelManager.checkModels()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ModelDownloadView()
        .environmentObject(ModelManager.shared)
        .environmentObject(StoreManager.shared)
}
