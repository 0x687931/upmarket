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
    @State private var symbolScale: CGFloat = 1.0
    @State private var symbolOpacity: Double = 1.0
    @State private var glowRadius: CGFloat = 0
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
        .onAppear { startIdleAnimation() }
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
            // Drop target border
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.15),
                    style: StrokeStyle(
                        lineWidth: isTargeted ? 2 : 1.5,
                        dash: isTargeted ? [] : [10, 6]
                    )
                )
                .padding(24)
                .animation(.easeInOut(duration: 0.2), value: isTargeted)

            VStack(spacing: 28) {
                // Animated # symbol
                ZStack {
                    // Glow ring
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 100 + glowRadius, height: 100 + glowRadius)
                        .blur(radius: 12)
                        .opacity(isTargeted ? 1 : 0.6)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: glowRadius)

                    // Ripple on drop target
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(rippleOpacity), lineWidth: 2)
                        .frame(width: 90 * rippleScale, height: 90 * rippleScale)

                    // Main symbol
                    Text("#")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .opacity(isTargeted ? 1.0 : 0.85)
                        .scaleEffect(symbolScale)
                        .opacity(symbolOpacity)
                        .animation(.easeInOut(duration: 0.2), value: isTargeted)
                }

                // Format chips — no text label needed
                HStack(spacing: 6) {
                    ForEach(["PDF", "DOCX", "PPTX", "XLSX", "HTML", "EPUB", "CSV", "Images", "Audio"], id: \.self) { fmt in
                        Text(fmt)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.08), in: Capsule())
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(isTargeted ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

                // Choose file button — minimal
                Button {
                    openFilePicker()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                        Text(L("dropzone.button"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L("dropzone.button"))
                    .accessibilityIdentifier("ChooseDocumentButton")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ChooseDocumentButton")
                .opacity(isTargeted ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
            }

            // Cmd+O hint
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "command")
                            .font(.system(size: 9))
                        Text("O")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.quaternary)
                    .padding(12)
                }
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .onTapGesture { openFilePicker() }
        .onChange(of: isTargeted) { targeted in
            if targeted { triggerRipple() }
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
        VStack(spacing: 24) {
            ZStack {
                // Progress ring
                Circle()
                    .stroke(Color.accentColor.opacity(0.1), lineWidth: 3)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        Color.accentColor,
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
                    .foregroundStyle(.secondary)
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

    private func errorView(_ message: String, job: ConversionJob?) -> some View {
        VStack(spacing: 20) {
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
                if job != nil, message == ConversionError.passwordRequired.errorDescription {
                    Button("Enter Password") { showPasswordPrompt = true }
                        .buttonStyle(.bordered)
                } else if let job, job.stage != .cancelled {
                    Button("Retry") { retry(job) }
                        .buttonStyle(.bordered)
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
        } else if let nudge = store.nudgeMessage {
            bannerRow(icon: "arrow.up.circle.fill", text: nudge,
                      action: ("See Plans", { PaywallWindowController.shared.show() }),
                      tint: Color.accentColor.opacity(0.07))
        } else {
            bannerRow(icon: "lock.fill", text: "Unlock Upmarket to convert",
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

    private func startIdleAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowRadius = 20
        }
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(0.5)) {
            symbolScale = 1.04
            symbolOpacity = 0.85
        }
    }

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
        startIdleAnimation()
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
