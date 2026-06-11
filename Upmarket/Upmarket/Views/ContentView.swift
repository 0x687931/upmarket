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
        VStack(spacing: AppTheme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .fill(isTargeted ? AppTheme.Colour.dropFillActive : AppTheme.Colour.dropFill)

                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(
                        isTargeted ? AppTheme.Colour.borderActive : AppTheme.Colour.border,
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [8, 4])
                    )

                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                        .animation(.easeInOut(duration: 0.15), value: isTargeted)

                    VStack(spacing: AppTheme.Spacing.xs) {
                        Text(isTargeted ? "Release to convert" : "Drop documents here")
                            .font(AppTheme.Font.title)
                            .animation(.easeInOut(duration: 0.15), value: isTargeted)

                        if !isTargeted {
                            Text("or click below to choose")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
            .contentShape(Rectangle())
            .onTapGesture { openFilePicker() }

            Button(action: openFilePicker) {
                Text("Choose File")
                    .font(AppTheme.Font.body)
                    .frame(minWidth: AppTheme.Size.chooseButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.accentColor)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.lg)
    }

    // MARK: - Queue List

    private var queueListView: some View {
        Group {
            if conversion.jobs.isEmpty {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No conversions yet")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.secondary)
                    Text("Drop files above or use Choose File to start")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.Colour.background)
            } else {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(conversion.jobs) { job in
                            QueueItemRow(
                                job: job,
                                isSelected: selectedJobID == job.id,
                                onSelect: { selectedJobID = job.id },
                                onRemove: { conversion.remove(job.id) },
                                onCancel: { conversion.cancel(job.id) },
                                onRetry: { _ in _ = conversion.retry(job.id) }
                            )
                            .cornerRadius(AppTheme.Radius.sm)
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
                .background(AppTheme.Colour.background)
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
        guard store.consumeConversion() else {
            PaywallWindowController.shared.show()
            return
        }
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

    private let windowSize: AppTheme.WindowSize = .main
    @State private var hoverActions = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            // File icon in colored box
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.Colour.iconBoxFill)
                    .frame(width: AppTheme.Size.fileIconBox, height: AppTheme.Size.fileIconBox)

                if FileManager.default.fileExists(atPath: job.sourceURL.path),
                   let icon = NSWorkspace.shared.icon(forFile: job.sourceURL.path) as NSImage? {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: AppTheme.Size.fileIcon, height: AppTheme.Size.fileIcon)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                }
            }

            // File info
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(job.name)
                    .font(AppTheme.Font.body)
                    .lineLimit(1)

                Text(statusLabel)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(job.stage == .failed ? AppTheme.Status.failed : Color.secondary)
            }

            Spacer()

            // Progress or status icon
            if job.isRunning {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: AppTheme.Size.strokeRingThin)
                    ArcProgressRing(progress: job.progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: AppTheme.Size.strokeRingThin, lineCap: .round))
                        .animation(.linear(duration: 0.4), value: job.progress)
                }
                .frame(width: AppTheme.Size.statusIcon + 4, height: AppTheme.Size.statusIcon + 4)
            } else if job.stage == .complete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.Status.complete)
                    .font(.system(size: AppTheme.Size.statusIcon, weight: .semibold))
            } else if job.stage == .failed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.Status.failed)
                    .font(.system(size: AppTheme.Size.statusIcon, weight: .semibold))
            }

            // Actions
            HStack(spacing: AppTheme.Spacing.xs) {
                if job.isRunning {
                    Button(action: onCancel) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(AppActionButtonStyle())
                } else if job.stage == .complete, let output = job.result?.output {
                    Button {
                        let formatted = OutputFormatter.format(
                            output,
                            sourceDisplayName: job.sourceURL.lastPathComponent,
                            mode: OutputPreference.shared.mode
                        )
                        FileAccessService.shared.copyMarkdown(formatted.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(AppActionButtonStyle())
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
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .help("Open")

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .help("Remove")
                } else if job.stage == .failed {
                    Button { onRetry(job.id) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .help("Retry")

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .help("Remove")
                } else {
                    if hoverActions {
                        Button(action: onRemove) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(AppActionButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoverActions = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }

    private var rowBackground: Color {
        if isSelected { return AppTheme.Colour.selectedFill }
        if hoverActions { return AppTheme.Colour.accentTint10 }
        return AppTheme.Colour.subtleFill
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
