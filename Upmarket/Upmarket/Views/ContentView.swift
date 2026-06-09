import SwiftUI
import StoreKit
import UniformTypeIdentifiers
import AppKit
import OSLog

struct ContentView: View {

    @EnvironmentObject private var conversion: ConversionQueue
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false
    @State private var showModelDownload = false
    @State private var showPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var pendingFileURL: URL?
    @State private var showAISuggestion = false
    @State private var pendingAdvice: ComplexityAdvice?
    @State private var languageWarning: String?
    @State private var selectedJobID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            Divider()
            VStack(spacing: 0) {
                dropZoneView
                    .frame(height: 160)

                Divider()

                queueListView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("PrimaryConversionView")
        .frame(
            minWidth: 500,
            idealWidth: 680,
            maxWidth: .infinity,
            minHeight: 500,
            maxHeight: .infinity
        )
        .sheet(isPresented: $showModelDownload) {
            ModelDownloadView()
                .environmentObject(modelManager)
                .environmentObject(store)
        }
        .sheet(isPresented: $showPasswordPrompt) {
            passwordSheet
        }
        .sheet(isPresented: $showAISuggestion) {
            if let advice = pendingAdvice, let url = pendingFileURL {
                AISuggestionView(
                    advice: advice,
                    proPrice: store.proProduct?.displayPrice ?? "$9.99",
                    onUseAI: {
                        showAISuggestion = false
                        PaywallWindowController.shared.show()
                    },
                    onBasic: {
                        showAISuggestion = false
                        beginConversion(url: url, useAI: false)
                    },
                    onDismiss: { showAISuggestion = false }
                )
            }
        }
        .overlay(alignment: .bottom) { languageWarningBanner }
        .onReceive(NotificationCenter.default.publisher(for: .openFilePicker)) { _ in
            openFilePicker()
        }
    }


    // MARK: - Drop Zone

    private var dropZoneView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(isTargeted ? "Release to convert" : "Drop files here")
                    .font(.headline)
                    .animation(.easeInOut(duration: 0.15), value: isTargeted)

                Button("or choose file…") {
                    openFilePicker()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .contentShape(Rectangle())
        .background(Color.secondary.opacity(isTargeted ? 0.06 : 0.02))
        .cornerRadius(8)
        .padding(12)
        .onTapGesture { openFilePicker() }
    }

    // MARK: - Queue List

    private var queueListView: some View {
        Group {
            if conversion.jobs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No conversions yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(conversion.jobs) { job in
                            QueueItemRow(
                                job: job,
                                isSelected: selectedJobID == job.id,
                                onSelect: { selectedJobID = job.id },
                                onRemove: { conversion.remove(job.id) },
                                onCancel: { conversion.cancel(job.id) },
                                onRetry: { _ in _ = conversion.retry(job.id) }
                            )
                            .background(selectedJobID == job.id ? Color.accentColor.opacity(0.08) : .clear)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }


    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        if store.hasBasicOrAbove {
            EmptyView()
        } else if store.freeDocsRemaining > 0 {
            let n = store.freeDocsRemaining
            let text = n == 1 ? "1 free conversion remaining" : "\(n) free conversions remaining"
            bannerRow(icon: "gift.fill", text: text,
                      action: ("See Plans", { PaywallWindowController.shared.show() }),
                      tint: Color.accentColor.opacity(0.06))
        } else if let nudge = store.nudgeMessage {
            bannerRow(icon: "arrow.up.circle.fill", text: nudge,
                      action: ("See Plans", { PaywallWindowController.shared.show() }),
                      tint: Color.accentColor.opacity(0.07))
        } else {
            bannerRow(icon: "lock.fill", text: "Free trial ended — unlock to keep converting",
                      action: ("Unlock", { PaywallWindowController.shared.show() }),
                      tint: Color.red.opacity(0.06))
        }
    }

    private func bannerRow(icon: String, text: String, action: (String, () -> Void), tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).font(.caption)
            Text(text).font(.caption).fontWeight(.medium)
            Spacer()
            Button(action.0, action: action.1)
                .buttonStyle(.borderedProminent).controlSize(.mini)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(tint)
    }

    // MARK: - Language Warning

    @ViewBuilder
    private var languageWarningBanner: some View {
        if let warning = languageWarning {
            HStack(spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.orange).font(.caption)
                Text(warning).font(.caption).lineLimit(2)
                Spacer()
                Button { languageWarning = nil } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.regularMaterial)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Password Sheet

    private var passwordSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.doc")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Password protected")
                .font(.title3).fontWeight(.semibold)
            SecureField("Document password", text: $passwordInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack(spacing: 10) {
                Button("Cancel") {
                    showPasswordPrompt = false
                    passwordInput = ""
                    if let url = pendingFileURL {
                        conversion.addRejected(url, message: "Password required")
                    }
                }
                .buttonStyle(.bordered)
                Button("Convert") {
                    guard let url = pendingFileURL else { return }
                    showPasswordPrompt = false
                    _ = conversion.add(url, useAI: store.hasProOrAbove, password: passwordInput)
                    passwordInput = ""
                    pendingFileURL = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(passwordInput.isEmpty)
            }
        }
        .padding(32).frame(width: 320)
    }


    // MARK: - Actions

    private func openFilePicker() {
        guard store.canConvert else { PaywallWindowController.shared.show(); return }
        if let url = FileAccessService.shared.chooseDocuments(allowsMultipleSelection: false).first {
            handleFile(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { PaywallWindowController.shared.show(); return false }
        guard !providers.isEmpty else { return false }

        if providers.count == 1, let provider = providers.first {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { self.handleFile(url) }
            }
        } else {
            ShelfWindowController.shared.show()
            FileAccessService.shared.loadFileURLs(from: providers) { url in
                NotificationCenter.default.post(name: .upmarketConvertFile, object: url)
            }
        }
        return true
    }

    private func handleFile(_ url: URL) {
        do {
            try FileAccessService.shared.validateReadableInput(url)
        } catch {
            let message = FileAccessService.userVisibleMessage(for: error)
            AppLog.fileAccess.error("Rejected input before conversion: \(message, privacy: .private)")
            _ = conversion.addRejected(url, message: message)
            return
        }
        store.consumeConversion()
        pendingFileURL = url

        conversion.analyse(fileURL: url) { advice in
            if let warning = advice?.languageQualityWarning {
                withAnimation { self.languageWarning = warning }
            }
            if let advice, advice.suggestAI, !self.store.hasProOrAbove,
               FeatureFlags.shared.aiAvailable {
                self.pendingAdvice = advice
                self.showAISuggestion = true
            } else {
                self.beginConversion(url: url, useAI: self.store.hasProOrAbove)
            }
        }
    }

    private func beginConversion(url: URL, useAI: Bool) {
        Task { @MainActor in
            var shouldUseAI = useAI
            if useAI, let reason = await modelManager.aiUseUnavailableReasonAfterChecking(hasPro: store.hasProOrAbove) {
                shouldUseAI = false
                withAnimation {
                    languageWarning = reason
                }
            }
            _ = conversion.add(url, useAI: shouldUseAI)
        }
    }

}

// MARK: - Queue Item Row

struct QueueItemRow: View {
    let job: ConversionJob
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void
    let onRetry: (_ id: UUID) -> Void

    @State private var hoverActions = false

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            if FileManager.default.fileExists(atPath: job.sourceURL.path),
               let icon = NSWorkspace.shared.icon(forFile: job.sourceURL.path) as NSImage? {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Progress or status
            if job.isRunning {
                ProgressView(value: job.progress)
                    .frame(width: 80)
            } else if job.stage == .complete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            } else if job.stage == .failed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 14))
            }

            // Actions
            HStack(spacing: 6) {
                if job.isRunning {
                    Button(action: onCancel) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if job.stage == .complete, let output = job.result?.output {
                    // Completed: show copy + open + remove
                    Button {
                        let formatted = OutputFormatter.format(
                            output,
                            sourceDisplayName: job.sourceURL.lastPathComponent,
                            mode: OutputPreference.shared.mode
                        )
                        FileAccessService.shared.copyMarkdown(formatted.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy")

                    Button {
                        let formatted = OutputFormatter.format(
                            output,
                            sourceDisplayName: job.sourceURL.lastPathComponent,
                            mode: OutputPreference.shared.mode
                        )
                        let savedURL = SavePreference.shared.save(
                            markdown: formatted.text,
                            title: output.title,
                            sourceURL: job.sourceURL,
                            fileExtension: formatted.fileExtension
                        )
                        if let url = savedURL {
                            FileAccessService.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open")

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Remove")
                } else if job.stage == .failed {
                    // Failed: show retry + remove
                    Button { onRetry(job.id) } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Retry")

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Remove")
                } else {
                    // Queued/processing: just remove on hover
                    if hoverActions {
                        Button(action: onRemove) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoverActions = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }

    private var statusLabel: String {
        switch job.stage {
        case .queued:
            return "Queued"
        case .copying:
            return "Preparing…"
        case .analysing:
            return "Analyzing…"
        case .extracting:
            return "Reading…"
        case .python:
            return "Processing…"
        case .postProcessing:
            return "Refining…"
        case .complete:
            return "Done"
        case .failed:
            return job.result?.errorMessage ?? "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ConversionQueue.shared)
        .environmentObject(StoreManager.shared)
        .environmentObject(ModelManager.shared)
}
