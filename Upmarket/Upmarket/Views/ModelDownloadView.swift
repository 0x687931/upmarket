import SwiftUI

struct ModelDownloadView: View {

    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var store: StoreManager

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
            Image(systemName: "cpu.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("Download AI Models")
                .font(.title2)
                .fontWeight(.bold)

            Text("Upmarket uses on-device AI — your documents never leave your Mac. Models are downloaded once and used offline forever.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Model List

    private var modelList: some View {
        VStack(spacing: 10) {
            ForEach(modelManager.models, id: \.key) { model in
                HStack(spacing: 12) {
                    Image(systemName: model.isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(model.isDownloaded ? .green : Color.accentColor)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.name)
                                .fontWeight(.medium)
                            if model.tier == "pro" {
                                Text("PRO")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor, in: Capsule())
                            }
                        }
                        Text(model.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(model.isDownloaded ? "Ready" : "\(model.sizeMB) MB")
                        .font(.caption)
                        .foregroundStyle(model.isDownloaded ? .green : .secondary)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        VStack(spacing: 10) {
            let requiredReady = modelManager.models.filter(\.isRequired).allSatisfy(\.isDownloaded)

            if !requiredReady {
                Button {
                    modelManager.downloadRequiredModels()
                } label: {
                    Label("Download Basic Models (\(modelManager.requiredSizeMB) MB)", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if store.hasProOrAbove {
                let proReady = modelManager.models.filter { $0.tier == "pro" }.allSatisfy(\.isDownloaded)
                if !proReady {
                    Button {
                        modelManager.downloadProModels()
                    } label: {
                        Label("Download Pro Models (\(modelManager.proSizeMB) MB)", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Text("Requires internet connection for initial download only.")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            Text(error)
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
