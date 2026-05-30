import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {

    @EnvironmentObject private var conversion: ConversionService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false
    @State private var showPaywall = false
    @State private var showModelDownload = false
    @State private var showPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var pendingFileURL: URL?
    @State private var showAISuggestion = false
    @State private var pendingAdvice: ComplexityAdvice?

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            Divider()
            ZStack {
                if conversion.isConverting || conversion.isAnalysing {
                    progressView
                } else if let result = conversion.result {
                    outputView(result)
                } else {
                    dropZone
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 520)
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
                        if store.hasProOrAbove {
                            conversion.convert(fileURL: url, useAI: true)
                        } else {
                            showPaywall = true
                        }
                    },
                    onBasic: {
                        showAISuggestion = false
                        beginConversion(url: url, useAI: false)
                    },
                    onDismiss: { showAISuggestion = false }
                )
            }
        }
        .onAppear {
            modelManager.checkModels()
            if !modelManager.allRequiredDownloaded {
                showModelDownload = true
            }
        }
        .onChange(of: modelManager.allRequiredDownloaded) { ready in
            if ready { showModelDownload = false }
        }
        .onChange(of: conversion.needsPassword) { needs in
            if needs { showPasswordPrompt = true }
        }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        if store.hasBasicOrAbove {
            EmptyView()
        } else if store.freeDocsRemaining > 0 {
            bannerView(
                icon: "sparkles",
                message: store.freeDocsRemaining == 1
                    ? "1 free conversion remaining"
                    : "\(store.freeDocsRemaining) free conversions remaining — no sign-up needed",
                buttonLabel: "Upgrade",
                color: Color.accentColor.opacity(0.08),
                action: { showPaywall = true }
            )
        } else if let nudge = store.nudgeMessage {
            bannerView(
                icon: "arrow.up.circle.fill",
                message: nudge,
                buttonLabel: "See Plans",
                color: Color.accentColor.opacity(0.08),
                action: { showPaywall = true }
            )
        } else if store.packCredits > 0 {
            EmptyView()
        } else {
            bannerView(
                icon: "lock.fill",
                message: "You've used your free conversions",
                buttonLabel: "Unlock",
                color: Color.red.opacity(0.07),
                action: { showPaywall = true }
            )
        }
    }

    private func bannerView(icon: String, message: String, buttonLabel: String, color: Color, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Button(buttonLabel, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(color)
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(isTargeted ? 0.15 : 0.08))
                        .frame(width: 88, height: 88)
                        .animation(.easeInOut(duration: 0.2), value: isTargeted)
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.accentColor)
                }

                // Text
                VStack(spacing: 6) {
                    Text(isTargeted ? "Release to convert" : "Drop a document")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .animation(.easeInOut(duration: 0.15), value: isTargeted)

                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)

                    Button("Choose File") { openFilePicker() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }

                // Format chips
                HStack(spacing: 8) {
                    ForEach(["PDF", "Word", "PowerPoint", "Excel", "HTML", "Images"], id: \.self) { format in
                        Text(format)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }
            }
            Spacer()

            // Keyboard hint
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "command")
                    Text("O")
                }
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [8, 4])
                )
                .animation(.easeInOut(duration: 0.2), value: isTargeted)
                .padding(20)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .keyboardShortcut("o", modifiers: .command)
        .onTapGesture { openFilePicker() }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .controlSize(.large)

            VStack(spacing: 6) {
                Text(conversion.isAnalysing ? "Analysing document…" : "Converting…")
                    .font(.title3)
                    .fontWeight(.medium)

                Text(conversion.isAnalysing
                     ? "Checking complexity — usually a few seconds"
                     : "This usually takes 5–30 seconds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Output

    private func outputView(_ result: ConversionResult) -> some View {
        switch result {
        case .success(let output):
            return AnyView(successView(output))
        case .failure(let error):
            return AnyView(errorView(error))
        }
    }

    private func successView(_ output: ConversionOutput) -> some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(output.title)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if output.usedAI {
                            Label("AI", systemImage: "sparkles")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1), in: Capsule())
                        }
                    }
                    Text("\(output.format) · \(output.pages) page\(output.pages == 1 ? "" : "s") · \(wordCount(output.markdown)) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output.markdown, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    saveMarkdown(output)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    conversion.reset()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                Text(output.markdown)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.red.opacity(0.8))

            VStack(spacing: 6) {
                Text("Couldn't convert this document")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: 10) {
                Button("Try Another") { conversion.reset() }
                    .buttonStyle(.borderedProminent)
                if conversion.needsPassword {
                    Button("Enter Password") {
                        showPasswordPrompt = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Password Sheet

    private var passwordSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.doc")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("This PDF is password-protected")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Enter the document password to convert it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Password", text: $passwordInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            HStack(spacing: 10) {
                Button("Cancel") {
                    showPasswordPrompt = false
                    passwordInput = ""
                    conversion.reset()
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
        .padding(32)
        .frame(width: 360)
    }

    // MARK: - Actions

    private func openFilePicker() {
        guard store.canConvert else { showPaywall = true; return }
        guard modelManager.allRequiredDownloaded else { showModelDownload = true; return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .html, .png, .jpeg,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            handleFile(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { showPaywall = true; return false }
        guard modelManager.allRequiredDownloaded else { showModelDownload = true; return false }
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

        // Analyse complexity first — show AI suggestion if warranted
        conversion.analyse(fileURL: url) { advice in
            if let advice, advice.suggestAI, !self.store.hasProOrAbove,
               DeviceCapability.shared.supportsUpmarketAI {
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
        let count = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        return count > 1000
            ? String(format: "%.1fk", Double(count) / 1000)
            : "\(count)"
    }
}

#Preview {
    ContentView()
        .environmentObject(ConversionService.shared)
        .environmentObject(StoreManager.shared)
        .environmentObject(ModelManager.shared)
}
