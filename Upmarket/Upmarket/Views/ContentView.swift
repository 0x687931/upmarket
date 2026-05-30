import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {

    @EnvironmentObject private var conversion: ConversionService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var phase: AppPhase = .idle
    @State private var isTargeted = false
    @State private var showPaywall = false
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

    enum AppPhase {
        case idle, targeting, analysing, converting, result(ConversionResult), error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            Divider()
            ZStack {
                switch phase {
                case .idle, .targeting:
                    dropZoneView
                case .analysing, .converting:
                    convertingView
                case .result(let result):
                    outputView(result)
                case .error(let message):
                    errorView(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(
            minWidth: isOutputPhase ? 560 : 400,
            idealWidth: isOutputPhase ? 640 : 400,
            maxWidth: isOutputPhase ? 900 : 400,
            minHeight: 500,
            maxHeight: .infinity
        )
        .animation(.spring(duration: 0.4), value: isOutputPhase)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
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
                    onUseAI: {
                        showAISuggestion = false
                        beginConversion(url: url, useAI: true)
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
        .onChange(of: conversion.isAnalysing) { analysing in
            if analysing { transitionToAnalysing() }
        }
        .onChange(of: conversion.isConverting) { converting in
            if converting { transitionToConverting() }
            else if let result = conversion.result { transitionToResult(result) }
        }
        .onChange(of: conversion.needsPassword) { needs in
            if needs { showPasswordPrompt = true }
        }
    }

    private var isOutputPhase: Bool {
        if case .result = phase { return true }
        return false
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
                        Text("Choose File")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
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

    private var convertingView: some View {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Output View

    private func outputView(_ result: ConversionResult) -> some View {
        switch result {
        case .success(let output):
            return AnyView(successView(output))
        case .failure(let message):
            return AnyView(errorView(message))
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
                        Image(systemName: "sparkles")
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
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output.markdown, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy Markdown  ⌘C")
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                    Button { saveMarkdown(output) } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save as .md  ⌘S")
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

            ScrollView {
                Text(output.markdown)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity
        ))
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
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
                Button("Try Again") { resetToIdle() }
                    .buttonStyle(.borderedProminent)
                if conversion.needsPassword {
                    Button("Enter Password") { showPasswordPrompt = true }
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
        } else if store.freeDocsRemaining > 0 {
            bannerRow(
                icon: "sparkles",
                text: store.freeDocsRemaining == 1
                    ? "1 free conversion remaining"
                    : "\(store.freeDocsRemaining) free conversions",
                action: ("Upgrade", { showPaywall = true }),
                tint: Color.accentColor.opacity(0.07)
            )
        } else if let nudge = store.nudgeMessage {
            bannerRow(icon: "arrow.up.circle.fill", text: nudge,
                      action: ("See Plans", { showPaywall = true }),
                      tint: Color.accentColor.opacity(0.07))
        } else if store.packCredits == 0 {
            bannerRow(icon: "lock.fill", text: "Free conversions used",
                      action: ("Unlock", { showPaywall = true }),
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
                    guard let url = pendingFileURL else { return }
                    showPasswordPrompt = false
                    conversion.convert(fileURL: url, password: passwordInput)
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

    private func transitionToAnalysing() {
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .analysing
            ringProgress = 0.15
        }
        // Animate ring to show activity
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            ringProgress = 0.85
        }
    }

    private func transitionToConverting() {
        withAnimation(.easeInOut(duration: 0.2)) {
            phase = .converting
        }
    }

    private func transitionToResult(_ result: ConversionResult) {
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            phase = .result(result)
        }
    }

    private func resetToIdle() {
        conversion.reset()
        languageWarning = nil
        pendingFileURL = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .idle
            ringProgress = 0
        }
        startIdleAnimation()
    }

    // MARK: - Actions

    private func openFilePicker() {
        guard store.canConvert else { showPaywall = true; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .pdf, .html, .png, .jpeg, .gif, .tiff,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "epub") ?? .data,
            UTType(filenameExtension: "csv")  ?? .data,
            UTType(filenameExtension: "json") ?? .data,
            UTType(filenameExtension: "xml")  ?? .data,
            UTType(filenameExtension: "zip")  ?? .data,
            UTType(filenameExtension: "mp3")  ?? .data,
            UTType(filenameExtension: "m4a")  ?? .data,
            UTType(filenameExtension: "wav")  ?? .data,
        ]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            handleFile(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { showPaywall = true; return false }
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { self.handleFile(url) }
        }
        return true
    }

    private func handleFile(_ url: URL) {
        store.consumeConversion()
        pendingFileURL = url
        languageWarning = nil

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
        conversion.convert(fileURL: url, useAI: useAI)
    }

    private func saveMarkdown(_ output: ConversionOutput) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = output.title + ".md"
        if panel.runModal() == .OK, let url = panel.url {
            try? output.markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func wordCount(_ text: String) -> String {
        let n = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return n > 999 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

#Preview {
    ContentView()
        .environmentObject(ConversionService.shared)
        .environmentObject(StoreManager.shared)
        .environmentObject(ModelManager.shared)
}
