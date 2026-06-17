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
    @State private var passwordError: String? = nil
    @State private var pendingFileURL: URL?
    @State private var showAISuggestion = false
    @State private var pendingAdvice: ComplexityAdvice?
    @State private var languageWarning: String?
    @FocusState private var passwordFieldIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            dropZoneView

            Rectangle()
                .fill(AppTheme.Colour.separator)
                .frame(height: 0.5)

            queueListView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBanner
        }
        .accessibilityIdentifier("PrimaryConversionView")
        .frame(width: 480, height: 560)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
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
                    proPrice: store.maxProduct?.displayPrice ?? "$14.99",
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
        .onReceive(NotificationCenter.default.publisher(for: .upmarketOpenFiles)) { note in
            guard let urls = note.object as? [URL] else { return }
            for url in urls { handleFile(url) }
        }
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        VStack(spacing: 16) {
            let dropZone = RoundedRectangle(cornerRadius: 16)

            ZStack {
                // Background fill
                dropZone
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.accentColor.opacity(0.04))

                // Dashed border (idle) or solid border (targeted)
                dropZone
                    .stroke(
                        isTargeted ? Color.accentColor : AppTheme.Colour.separator,
                        style: StrokeStyle(
                            lineWidth: isTargeted ? 2 : 1.5,
                            dash: isTargeted ? [] : [8, 4]
                        )
                    )

                // Pulse ring (targeted only)
                if isTargeted {
                    PulseRingView(active: true)
                        .clipShape(dropZone)
                }

                // Content
                VStack(spacing: 12) {
                    Image(systemName: isTargeted ? "arrow.down" : "doc.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

                    VStack(spacing: 4) {
                        Text(isTargeted ? "Release to convert" : "Drop documents here")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isTargeted ? Color.accentColor : .primary)
                        if !isTargeted {
                            Text("or click below to choose")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(capabilityLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .frame(height: 160)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .scaleEffect(isTargeted ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isTargeted)
            .onTapGesture { openFilePicker() }
            .accessibilityIdentifier("ContentDropZone")
            .accessibilityLabel("Drop zone for document conversion")
            .accessibilityHint("Drop documents here to convert them, or click to select files")
            .accessibilityAddTraits(.isButton)

            Button("Choose File") {
                openFilePicker()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.accentColor)
            .frame(minWidth: 180)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("ChooseDocumentButton")
        }
    }

    // MARK: - Queue List

    private var queueListView: some View {
        ScrollView {
            if conversion.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No conversions yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Drop files above or use Choose File to start")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(conversion.jobs) { job in
                        FileRowView(job: job)
                    }
                }
                .padding(12)
            }
        }
    }


    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        Divider()
        HStack(spacing: 8) {
            switch store.tier {
            case .basic:
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                Text("Upmarket Basic — Standard conversion")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("See Plans") {
                    PaywallWindowController.shared.show()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .pro:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                Text("Upmarket Pro — Enhanced conversion")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            case .max:
                Image(systemName: "crown.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.Colour.sectionAmber)
                Text("Upmarket Max — AI-powered conversion")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(store.tier == .basic
            ? Color.accentColor.opacity(0.05)
            : (store.tier == .pro ? Color.accentColor.opacity(0.04) : AppTheme.Colour.sectionAmber.opacity(0.04)))
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
                .buttonStyle(AppActionButtonStyle())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(AppTheme.Colour.warning.opacity(0.08))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.Colour.border)
                    .frame(height: 1)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var capabilityLabel: String {
        switch store.tier {
        case .basic:
            return "Native conversion"
        case .pro:
            return "Enhanced conversion"
        case .max:
            return "AI-powered conversion"
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
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Document password", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .focused($passwordFieldIsFocused)
                    .onAppear { passwordFieldIsFocused = true }
                    .onChange(of: passwordInput) { _ in passwordError = nil }
                if let error = passwordError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 8)
                }
            }
            HStack(spacing: 10) {
                Button("Cancel") {
                    showPasswordPrompt = false
                    passwordInput = ""
                    passwordError = nil
                    if let url = pendingFileURL {
                        conversion.addRejected(url, message: "Password required")
                    }
                }
                .buttonStyle(AppBorderedButtonStyle())
                Button("Convert") {
                    guard let url = pendingFileURL else { return }
                    showPasswordPrompt = false
                    _ = conversion.add(url, useAI: store.tier >= .max, password: passwordInput)
                    passwordInput = ""
                    passwordError = nil
                    pendingFileURL = nil
                }
                .buttonStyle(AppProminentButtonStyle())
                .disabled(passwordInput.isEmpty)
            }
        }
        .padding(32).frame(width: 320)
    }


    // MARK: - Actions

    private func openFilePicker() {
        guard store.canConvert else { PaywallWindowController.shared.show(); return }
        let urls = FileAccessService.shared.chooseDocuments(allowsMultipleSelection: true)
        for url in urls { handleFile(url) }
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
        guard store.consumeTrialConversion() else {
            PaywallWindowController.shared.show()
            return
        }
        pendingFileURL = url

        conversion.analyse(fileURL: url) { advice in
            if let warning = advice?.languageQualityWarning {
                withAnimation { self.languageWarning = warning }
            }
            if let advice, advice.suggestAI, self.store.tier < .max,
               FeatureFlags.shared.aiAvailable {
                self.pendingAdvice = advice
                self.showAISuggestion = true
            } else {
                self.beginConversion(url: url, useAI: self.store.tier >= .max)
            }
        }
    }

    private func beginConversion(url: URL, useAI: Bool) {
        Task { @MainActor in
            var shouldUseAI = useAI
            if useAI, let reason = await modelManager.gateAfterChecking(tier: store.tier).unavailableReason(for: .ai) {
                shouldUseAI = false
                withAnimation {
                    languageWarning = reason
                }
            }
            _ = conversion.add(url, useAI: shouldUseAI)
        }
    }

}

// MARK: - File Row

struct FileRowView: View {
    let job: ConversionJob

    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            // File type icon — 32×32, rounded rect, blue tint
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(AppTheme.Colour.iconBoxFill)
                    .frame(width: 32, height: 32)
                Image(systemName: job.fileTypeIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.Colour.iconGlyphTint)
            }

            // Filename + stage label
            VStack(alignment: .leading, spacing: 2) {
                Text(job.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(statusLabelText)
                    .font(.system(size: 11))
                    .foregroundStyle(statusLabelColor)
            }

            Spacer()

            // Right slot: resting status indicator ↔ hover action buttons.
            // Same trailing slot — the 32pt file icon governs row height, so the
            // 20pt indicator and 28pt buttons swap without resizing the row.
            ZStack(alignment: .trailing) {
                if hover {
                    actionButtons
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    statusIndicator
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.2), value: hover)
        .onHover { hovering in
            hover = hovering
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch job.stage {
        case .complete:
            ZStack {
                Circle()
                    .fill(AppTheme.Status.complete)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Conversion complete")
        case .failed:
            ZStack {
                Circle()
                    .fill(AppTheme.Status.failed)
                    .frame(width: 20, height: 20)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Conversion failed")
        case .cancelled:
            ZStack {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 20, height: 20)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Conversion cancelled")
        default:
            PulseRingView(size: 20, color: .accentColor)
                .accessibilityLabel("Converting")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            switch job.stage {
            case .complete:
                ActionButton(icon: "doc.on.doc", label: "Copy", action: copyOutput)
                ActionButton(icon: "folder", label: "Reveal", action: revealInFinder)
                ActionButton(icon: "trash", label: "Delete", action: removeJob, danger: true)
            case .failed, .cancelled:
                ActionButton(icon: "arrow.clockwise", label: "Retry", action: retryJob)
                ActionButton(icon: "trash", label: "Delete", action: removeJob, danger: true)
            default: // running/queued
                ActionButton(icon: "stop.fill", label: "Stop", action: cancelJob, danger: true)
            }
        }
    }

    private var statusLabelText: String {
        switch job.stage {
        case .queued:
            return "Queued"
        case .copying:
            return "Preparing…"
        case .analysing:
            return "Analyzing…"
        case .extracting:
            return "Reading…"
        case .processing:
            return "Processing…"
        case .postProcessing:
            return "Refining…"
        case .complete:
            return "Done"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private var statusLabelColor: Color {
        switch job.stage {
        case .failed:
            return AppTheme.Status.failed
        default:
            return .secondary
        }
    }

    private func copyOutput() {
        if let output = job.result?.output {
            let formatted = OutputFormatter.format(
                output,
                sourceDisplayName: job.sourceURL.lastPathComponent,
                mode: OutputPreference.shared.mode
            )
            FileAccessService.shared.copyMarkdown(formatted.text)
        }
    }

    private func revealInFinder() {
        if let output = job.result?.output {
            let formatted = OutputFormatter.format(
                output,
                sourceDisplayName: job.sourceURL.lastPathComponent,
                mode: OutputPreference.shared.mode
            )
            Task { @MainActor in
                let savedURL = await SavePreference.shared.save(
                    markdown: formatted.text,
                    title: job.sourceURL.deletingPathExtension().lastPathComponent,
                    sourceURL: job.sourceURL,
                    fileExtension: formatted.fileExtension
                )
                if let url = savedURL {
                    FileAccessService.shared.revealInFinder(url)
                }
            }
        }
    }

    private func removeJob() {
        ConversionQueue.shared.remove(job.id)
    }

    private func retryJob() {
        _ = ConversionQueue.shared.retry(job.id)
    }

    private func cancelJob() {
        ConversionQueue.shared.cancel(job.id)
    }
}

// MARK: - ActionButton

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var danger: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(danger ? AppTheme.Status.failed : .secondary)
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Action: \(label)")
    }
}

#Preview {
    ContentView()
        .environmentObject(ConversionQueue.shared)
        .environmentObject(StoreManager.shared)
        .environmentObject(ModelManager.shared)
}
