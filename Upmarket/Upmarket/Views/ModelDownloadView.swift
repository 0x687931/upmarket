import SwiftUI

struct ModelDownloadView: View {

    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager

    private let device = DeviceCapability.shared

    var body: some View {
        VStack(spacing: 24) {
            header

            if modelManager.isDownloading {
                downloadingView
            } else if let error = modelManager.downloadError {
                errorView(error)
            } else {
                modelList
                downloadButton
            }
        }
        .padding(32)
        .frame(width: 480)
        .onAppear { modelManager.checkModels() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("#")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)

            Text("Set Up Upmarket")
                .font(.title2)
                .fontWeight(.bold)

            Text("Upmarket uses on-device AI — your documents never leave your Mac. Download once, work offline forever.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Model List

    private var modelList: some View {
        VStack(spacing: 10) {
            modelRow(
                icon: "doc.text.magnifyingglass",
                title: "Upmarket",
                description: "Document understanding, tables, and layout detection",
                sizeMB: modelManager.requiredSizeMB,
                isDownloaded: modelManager.models.filter(\.isRequired).allSatisfy(\.isDownloaded),
                isAI: false,
                available: true
            )

            if store.hasProOrAbove {
                modelRow(
                    icon: "sparkles",
                    title: "Upmarket AI",
                    description: "Advanced understanding for complex and scanned documents",
                    sizeMB: modelManager.proSizeMB,
                    isDownloaded: modelManager.models.filter { $0.tier == "pro" }.allSatisfy(\.isDownloaded),
                    isAI: true,
                    available: device.supportsUpmarketAI
                )
            }
        }
    }

    private func modelRow(icon: String, title: String, description: String, sizeMB: Int, isDownloaded: Bool, isAI: Bool, available: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isDownloaded ? "checkmark.circle.fill" : icon)
                .foregroundStyle(isDownloaded ? Color.green : Color.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .fontWeight(.medium)
                    if isAI {
                        Text("PRO")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text(available ? description : device.upmarketAIUnavailableReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(isDownloaded ? "Ready" : available ? "\(sizeMB) MB" : "—")
                .font(.caption)
                .foregroundStyle(isDownloaded ? Color.green : .secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .opacity(available ? 1.0 : 0.5)
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        VStack(spacing: 10) {
            let requiredReady = modelManager.models.filter(\.isRequired).allSatisfy(\.isDownloaded)

            if !requiredReady {
                Button {
                    modelManager.downloadRequiredModels()
                } label: {
                    Label("Download Upmarket — \(modelManager.requiredSizeMB) MB", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if store.hasProOrAbove && device.supportsUpmarketAI {
                let proReady = modelManager.models.filter { $0.tier == "pro" }.allSatisfy(\.isDownloaded)
                if !proReady {
                    Button {
                        modelManager.downloadProModels()
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

    private var downloadingView: some View {
        VStack(spacing: 16) {
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
        .padding(.vertical, 8)
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("Download failed")
                .fontWeight(.medium)
            Text("Please check your internet connection and try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                modelManager.downloadRequiredModels()
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
