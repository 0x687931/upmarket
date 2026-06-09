import SwiftUI
import StoreKit
import UniformTypeIdentifiers
import AppKit
import OSLog

struct ContentView: View {

    @EnvironmentObject private var conversion: ConversionQueue
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var primaryJobID: UUID?
    @State private var isAnalysingPrimary = false
    @State private var isTargeted = false
    @State private var showModelDownload = false
    @State private var showPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var pendingFileURL: URL?
    @State private var showAISuggestion = false
    @State private var pendingAdvice: ComplexityAdvice?
    @State private var languageWarning: String?

    // Animation state
    @State private var ringProgress: Double = 0
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            Divider()
            ZStack {
                if isAnalysingPrimary {
                    convertingView(nil)
                } else if let job = primaryJob {
                    jobView(job)
                } else {
                    dropZoneView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("PrimaryConversionView")
        .frame(
            minWidth: isOutputPhase ? 560 : 400,
            idealWidth: isOutputPhase ? 640 : 400,
            maxWidth: isOutputPhase ? 900 : 400,
            minHeight: 500,
            maxHeight: .infinity
        )
        .animation(.spring(duration: 0.4), value: isOutputPhase)
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
        .onChange(of: isAnalysingPrimary) { analysing in
            if analysing { startProgressAnimation() }
        }
        .onChange(of: primaryJob?.stage) { stage in
            if stage?.isRunning == true { startProgressAnimation() }
        }
        .onChange(of: primaryJob?.result) { result in
            guard let result else { return }
            if result.errorMessage == ConversionError.passwordRequired.errorDescription {
                showPasswordPrompt = true
            }
            if case .success = result, store.shouldShowTrialPaywallAfterConversion() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    NotificationCenter.default.post(name: .showPaywall, object: nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFilePicker)) { _ in
            openFilePicker()
        }
    }

    private var primaryJob: ConversionJob? {
        guard let primaryJobID else { return nil }
        return conversion.job(id: primaryJobID)
    }

    private var isOutputPhase: Bool {
        primaryJob?.result?.output != nil
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        ZStack {
            dropZoneBackground

            VStack(spacing: 0) {
                Spacer()

                // App icon + headline
                VStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .scaleEffect(isTargeted ? 1.06 : 1.0)
                        .animation(.spring(duration: 0.3), value: isTargeted)

                    VStack(spacing: 6) {
                        Text(isTargeted ? "Release to convert" : "Drop a file to convert it.")
                            .font(.title2)
                            .fontWeight(.bold)
                            .animation(.easeInOut(duration: 0.15), value: isTargeted)

                        Text("Or click Choose File below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .opacity(isTargeted ? 0 : 1)
                            .animation(.easeInOut(duration: 0.15), value: isTargeted)
                    }
                }

                Spacer()

                // Format rows
                VStack(alignment: .leading, spacing: 12) {
                    formatRow(symbol: "doc.fill",       color: .blue,   label: "Documents",  detail: "PDF, Word, PowerPoint, Excel, EPUB")
                    formatRow(symbol: "photo.fill",     color: .purple, label: "Images",      detail: "PNG, JPEG, TIFF and scanned PDFs")
                    formatRow(symbol: "waveform",       color: .orange, label: "Audio",       detail: "MP3, M4A, WAV — transcribed to text")
                }
                .padding(.horizontal, 40)
                .opacity(isTargeted ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

                Spacer()

                // CTA button
                chooseFileButton
                    .opacity(isTargeted ? 0 : 1)
                    .animation(.easeInOut(duration: 0.15), value: isTargeted)

                Spacer().frame(height: 36)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .onTapGesture { openFilePicker() }
        .onChange(of: isTargeted) { targeted in
            if targeted { triggerRipple() }
        }
    }

    @ViewBuilder private var dropZoneBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                isTargeted ? Color.accentColor : Color.secondary.opacity(0.12),
                style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [10, 6])
            )
            .padding(24)
            .animation(.easeInOut(duration: 0.2), value: isTargeted)

        // Ripple on drop
        Circle()
            .strokeBorder(Color.accentColor.opacity(rippleOpacity), lineWidth: 2)
            .frame(width: 90 * rippleScale, height: 90 * rippleScale)
    }

    private func formatRow(symbol: String, color: Color, label: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var chooseFileButton: some View {
        if #available(macOS 26, *) {
            Button {
                openFilePicker()
            } label: {
                Text("Choose File")
                    .fontWeight(.semibold)
                    .frame(width: 200)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityIdentifier("ChooseDocumentButton")
        } else {
            Button {
                openFilePicker()
            } label: {
                Text("Choose File")
                    .fontWeight(.semibold)
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("ChooseDocumentButton")
        }
    }

    // MARK: - Converting View

    private func jobView(_ job: ConversionJob) -> some View {
        if job.isRunning {
            return AnyView(convertingView(job))
        }
        if let result = job.result {
            return AnyView(outputView(result, job: job))
        }
        return AnyView(convertingView(job))
    }

    private func convertingView(_ job: ConversionJob?) -> some View {
        let isStalled = job?.isStalled == true
        let ringColor: Color = isStalled ? .orange : .accentColor

        return VStack(spacing: 24) {
            ZStack {
                // Progress ring
                Circle()
                    .stroke(ringColor.opacity(0.1), lineWidth: 3)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: ringProgress)

                Text("#")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(0.9 + (ringProgress * 0.1))
            }

            VStack(spacing: 6) {
                Text(job?.name ?? "Checking document")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)

                Text(job.map(stageText) ?? "Checking file access and document complexity")
                    .font(.caption)
                    .foregroundStyle(isStalled ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            }

            if let job, job.isRunning {
                Button("Cancel") {
                    conversion.cancel(job.id)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Output View

    private func outputView(_ result: ConversionResult, job: ConversionJob) -> some View {
        switch result {
        case .success(let output):
            return AnyView(successView(output))
        case .failure(let message):
            return AnyView(errorView(message, job: job))
        }
    }

    private func successView(_ output: ConversionOutput) -> some View {
        VStack(spacing: 0) {
            // Compact toolbar — icons only with tooltips
            HStack(spacing: 10) {
                // File info
                HStack(spacing: 6) {
                    Text(output.format)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))

                    Text(output.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if output.usedAI {
                        Image(symbol: UpmarketSymbols.ai)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Spacer()

                Text("\(wordCount(output.markdown)) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Divider().frame(height: 16)

                // Icon-only actions
                Group {
                    Button {
                        FileAccessService.shared.copyMarkdown(formattedOutput(output).text)
                    } label: {
                        Image(symbol: UpmarketSymbols.copy)
                    }
                    .help("Copy Output  ⌘C")
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                    Button { saveOutput(output) } label: {
                        Image(symbol: UpmarketSymbols.save)
                    }
                    .help("Save Output  ⌘S")
                    .keyboardShortcut("s", modifiers: .command)

                    Button { resetToIdle() } label: {
                        Image(systemName: "plus")
                    }
                    .help("Convert Another  ⌘N")
                    .keyboardShortcut("n", modifiers: .command)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 15))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    Text(output.markdown)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .padding(.bottom, 28)
                }

                pathwayBadge(output)
                    .padding(14)
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity
        ))
    }

    private func pathwayBadge(_ output: ConversionOutput) -> some View {
        Text(output.provenanceLabel)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(pathwayBadgeTint(output), in: Capsule())
            .accessibilityLabel("Conversion pathway \(output.provenanceLabel)")
    }

    private func pathwayBadgeTint(_ output: ConversionOutput) -> Color {
        switch output.selectedPathway.displayPipeline {
        case .fast:
            return Color.accentColor
        case .enhanced:
            return Color(nsColor: .systemBlue)
        case .ai:
            return Color(nsColor: .systemPurple)
        case .none:
            return Color.secondary
        }
    }

    // MARK: - Error View

    private func errorKind(for message: String) -> ConversionError? {
        let known: [ConversionError] = [
            .inaccessible, .passwordRequired, .cancelled, .noProgress,
            .memoryPressure, .fileTooLarge, .sourceUnavailable,
            .unsupportedOnThisMac, .modelUnavailable, .downloadFailed,
            .upgradeRequired, .pythonRuntime(""), .failed(message)
        ]
        return known.first { $0.errorDescription == message }
    }

    private func errorView(_ message: String, job: ConversionJob?) -> some View {
        let kind = errorKind(for: message)

        return VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            HStack(spacing: 10) {
                Button("Convert Another") { resetToIdle() }
                    .buttonStyle(.borderedProminent)

                // Contextual secondary actions
                switch kind {
                case .upgradeRequired:
                    Button("Upgrade to Pro") {
                        NotificationCenter.default.post(name: .showPaywall, object: nil)
                    }
                    .buttonStyle(.bordered)

                case .modelUnavailable, .downloadFailed:
                    Button("Open Settings") {
                        PreferencesWindowController.shared.show()
                    }
                    .buttonStyle(.bordered)

                case .passwordRequired:
                    if job != nil {
                        Button("Enter Password") { showPasswordPrompt = true }
                            .buttonStyle(.bordered)
                    }

                case .inaccessible, .sourceUnavailable:
                    if let url = job?.sourceURL, FileManager.default.fileExists(atPath: url.path) {
                        Button("Show in Finder") {
                            FileAccessService.shared.revealInFinder(url)
                        }
                        .buttonStyle(.bordered)
                    }

                case .cancelled, .fileTooLarge:
                    EmptyView()

                case .memoryPressure:
                    if let job {
                        Button("Retry") { retry(job) }
                            .buttonStyle(.bordered)
                    }

                default:
                    if let job {
                        Button("Retry") { retry(job) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    resetToIdle()
                }
                .buttonStyle(.bordered)
                Button("Convert") {
                    guard let job = primaryJob else { return }
                    showPasswordPrompt = false
                    let id = conversion.add(job.sourceURL, useAI: job.useAI, password: passwordInput)
                    primaryJobID = id
                    passwordInput = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(passwordInput.isEmpty)
            }
        }
        .padding(32).frame(width: 320)
    }

    // MARK: - Animations

    private func triggerRipple() {
        rippleScale = 0.3
        rippleOpacity = 0.8
        withAnimation(.easeOut(duration: 0.6)) {
            rippleScale = 1.6
            rippleOpacity = 0
        }
    }

    private func startProgressAnimation() {
        ringProgress = 0.15
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            ringProgress = 0.85
        }
    }

    private func resetToIdle() {
        conversion.reset()
        languageWarning = nil
        pendingFileURL = nil
        pendingAdvice = nil
        primaryJobID = nil
        isAnalysingPrimary = false
        withAnimation(.easeInOut(duration: 0.3)) {
            ringProgress = 0
        }
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
            primaryJobID = conversion.addRejected(url, message: message)
            isAnalysingPrimary = false
            pendingFileURL = nil
            languageWarning = nil
            return
        }
        store.consumeConversion()
        pendingFileURL = url
        languageWarning = nil
        primaryJobID = nil
        isAnalysingPrimary = true

        conversion.analyse(fileURL: url) { advice in
            self.isAnalysingPrimary = false
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
            primaryJobID = conversion.add(url, useAI: shouldUseAI)
        }
    }

    private func retry(_ job: ConversionJob) {
        primaryJobID = conversion.retry(job.id)
    }

    private func stageText(_ job: ConversionJob) -> String {
        if job.isStalled {
            return "No progress detected. You can cancel and retry."
        }
        switch job.stage {
        case .queued: return "Queued"
        case .copying: return "Preparing document"
        case .analysing: return "Analysing document"
        case .extracting: return "Reading document"
        case .python: return "Processing document"
        case .postProcessing: return "Cleaning Markdown"
        case .complete: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private func saveOutput(_ output: ConversionOutput) {
        let formatted = formattedOutput(output)
        _ = FileAccessService.shared.saveMarkdown(
            formatted.text,
            title: output.title,
            fileExtension: formatted.fileExtension
        )
    }

    private func formattedOutput(_ output: ConversionOutput) -> FormattedConversionOutput {
        OutputFormatter.format(
            output,
            sourceDisplayName: primaryJob?.sourceURL.lastPathComponent,
            mode: OutputPreference.shared.mode
        )
    }

    private func wordCount(_ text: String) -> String {
        let n = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return n > 999 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

#Preview {
    ContentView()
        .environmentObject(ConversionQueue.shared)
        .environmentObject(StoreManager.shared)
        .environmentObject(ModelManager.shared)
}
