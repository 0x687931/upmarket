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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colour.background)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(AppTheme.Colour.separator, lineWidth: 0.5)
                )

            VStack(spacing: 0) {
                workbenchTitlebar
                statusBanner
                VStack(spacing: 0) {
                    dropZoneView

                    Rectangle()
                        .fill(AppTheme.Colour.separator)
                        .frame(height: 0.5)

                    queueListView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
            }
        }
        .accessibilityIdentifier("PrimaryConversionView")
        .frame(width: AppTheme.WindowSize.main.width, height: AppTheme.WindowSize.main.height)
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

    // MARK: - Titlebar

    private var workbenchTitlebar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.372, blue: 0.341))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(Color(red: 0.996, green: 0.737, blue: 0.180))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(Color(red: 0.157, green: 0.784, blue: 0.251))
                    .frame(width: 12, height: 12)
            }
            .frame(width: 88, alignment: .leading)

            Text("Upmarket")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Color.clear.frame(width: 88, height: 1)
        }
        .frame(height: 38)
        .padding(.horizontal, 14)
        .background(AppTheme.Colour.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.Colour.separator)
                .frame(height: 0.5)
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
                    ZStack {
                        if isTargeted {
                            PulseRingView(color: .accentColor, lineWidth: 2, isActive: true)
                                .frame(width: 32, height: 32)
                            PulseRingView(color: .accentColor, lineWidth: 2, isActive: true, phaseOffset: 0.22)
                                .frame(width: 32, height: 32)
                        }

                        Image(systemName: isTargeted ? "arrow.down" : "arrow.down.doc.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                            .animation(.easeInOut(duration: 0.15), value: isTargeted)
                    }

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
            }
            .frame(height: AppTheme.Size.dropZoneHeight)
            .contentShape(Rectangle())
            .onTapGesture { openFilePicker() }

            Button(action: openFilePicker) {
                Text("Choose File")
                    .font(AppTheme.Font.body)
                    .frame(minWidth: AppTheme.Size.chooseButtonWidth)
            }
            .buttonStyle(AppProminentButtonStyle())
            .controlSize(.large)
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
                            FileRowView(
                                job: job,
                                isDefaultOpen: false,
                                onRemove: {
                                    conversion.remove(job.id)
                                },
                                onCancel: { conversion.cancel(job.id) },
                                onRetry: { _ = conversion.retry(job.id) }
                            )
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
                      tint: AppTheme.Colour.tintError,
                      iconColor: AppTheme.Colour.error)
        }
    }

    private func bannerRow(icon: String, text: String, action: (String, () -> Void), tint: Color, iconColor: Color = .accentColor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(iconColor).font(.caption)
            Text(text).font(.caption).fontWeight(.medium)
            Spacer()
            Button(action.0, action: action.1)
                .buttonStyle(AppProminentButtonStyle()).controlSize(.mini)
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
                .buttonStyle(AppBorderedButtonStyle())
                Button("Convert") {
                    guard let url = pendingFileURL else { return }
                    showPasswordPrompt = false
                    _ = conversion.add(url, useAI: store.hasProOrAbove, password: passwordInput)
                    passwordInput = ""
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

// MARK: - File Row

struct FileRowView: View {
    let job: ConversionJob
    let isDefaultOpen: Bool
    let glyphName: String? = nil
    let onRemove: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    @State private var hover = false
    @State private var selected = false

    private let tokenSize: CGFloat = 20

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            fileIconTile

            VStack(alignment: .leading, spacing: 0) {
                Text(job.name)
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statusLabel)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(statusTextColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppTheme.Spacing.xs) {
                if open {
                    actions
                } else {
                    statusToken
                }
            }
            .frame(minHeight: tokenSize)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(rowBackground)
        .cornerRadius(AppTheme.Radius.sm)
        .animation(.easeInOut(duration: 0.2), value: open)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.name), \(statusLabel)")
        .onHover { hovering in
            hover = hovering
        }
        .onTapGesture {
            selected.toggle()
        }
    }

    private var open: Bool {
        hover || selected || isDefaultOpen
    }

    private var rowBackground: Color {
        if selected { return AppTheme.Colour.selectedFill }
        if open { return AppTheme.Colour.accentTint10 }
        return AppTheme.Colour.subtleFill
    }

    private var statusTextColor: Color {
        switch job.stage {
        case .failed:
            return AppTheme.Status.failed
        case .complete:
            return .secondary
        default:
            return .secondary
        }
    }

    private var fileIconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .fill(AppTheme.Colour.iconBoxFill)
                .frame(width: AppTheme.Size.fileIconBox, height: AppTheme.Size.fileIconBox)

            Image(systemName: glyphName ?? job.glyphName)
                .font(.system(size: AppTheme.Size.fileIcon, weight: .semibold))
                .foregroundStyle(AppTheme.Colour.iconGlyphTint)
        }
    }

    @ViewBuilder private var statusToken: some View {
        if job.isRunning {
            ArcRingView(
                progress: job.progress,
                size: tokenSize,
                lineWidth: 2.5,
                ringColor: .accentColor
            ) {
                EmptyView()
            }
            .help(statusLabel)
        } else if job.stage == .complete {
            AppStatusToken(color: AppTheme.Status.complete, kind: .check)
                .help("Done")
        } else if job.stage == .failed || job.stage == .cancelled {
            AppStatusToken(color: job.stage == .failed ? AppTheme.Status.failed : .secondary.opacity(0.55), kind: .cross)
                .help(statusLabel)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private var actions: some View {
        if job.isRunning {
            actionButton(symbol: "stop.fill", danger: true, help: "Stop") {
                onCancel()
            }
        } else if job.stage == .complete {
            if let output = job.result?.output {
                actionButton(symbol: "doc.on.doc", help: "Copy") {
                    let formatted = OutputFormatter.format(
                        output,
                        sourceDisplayName: job.sourceURL.lastPathComponent,
                        mode: OutputPreference.shared.mode
                    )
                    FileAccessService.shared.copyMarkdown(formatted.text)
                }

                actionButton(symbol: "arrow.up.right.square", help: "Show") {
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
                }
            }

            actionButton(symbol: "trash", danger: true, help: "Delete") {
                onRemove()
            }
        } else if job.stage == .failed || job.stage == .cancelled {
            actionButton(symbol: "arrow.clockwise", help: "Retry") {
                onRetry()
            }

            actionButton(symbol: "trash", danger: true, help: "Delete") {
                onRemove()
            }
        }
    }

    private func actionButton(symbol: String, danger: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(AppActionButtonStyle())
        .foregroundStyle(
            danger
                ? AppTheme.Status.failed.opacity(0.82)
                : .primary.opacity(0.78)
        )
        .help(help)
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
            return "Failed"
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
