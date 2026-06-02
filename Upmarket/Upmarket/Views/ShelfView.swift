import SwiftUI
import UniformTypeIdentifiers
import AppKit
import OSLog

struct ShelfView: View {

    @EnvironmentObject private var conversion: ConversionQueue
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false
    @State private var showPaywall = false
    @State private var isExpanded = false
    @State private var dragScale: CGFloat = 1.0

    // Hover states per button
    @State private var hoverClose  = false
    @State private var hoverAdd    = false
    @State private var hoverToggle = false
    @State private var floatOffset: CGFloat = -2

    // UI-5: asymmetric closed state
    // Left: narrow control strip  |  Right: peek panel showing live job state
    private let controlStripWidth: CGFloat = 48
    private let peekPanelWidth:    CGFloat = 168
    private let closedHeight:      CGFloat = 132
    private let itemWidth:         CGFloat = 64
    private let itemSpacing:       CGFloat = 8
    private let maxVisible:        Int     = 5

    private var buttonHeight: CGFloat { closedHeight / 3 }  // 44pt each

    private var isAnyConverting: Bool { conversion.isConverting }

    private var closedWidth: CGFloat { controlStripWidth + 1 + peekPanelWidth }

    private var totalWidth: CGFloat {
        guard isExpanded else { return closedWidth }
        let count = min(conversion.jobs.count, maxVisible)
        let content: CGFloat = count > 0
            ? CGFloat(count) * (itemWidth + itemSpacing) + itemSpacing
            : 200
        let overflow: CGFloat = conversion.jobs.count > maxVisible ? itemWidth + itemSpacing : 0
        return closedWidth + 8 + content + overflow
    }

    var body: some View {
        HStack(spacing: 0) {
            closedPanel

            if isExpanded {
                expandedContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: totalWidth, height: closedHeight)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: isExpanded)
        .animation(.spring(duration: 0.25), value: conversion.jobs.count)
        .background(LiquidGlassBackground(cornerRadius: 12))
        // Drop glow ring — sits outside the shelf bounds via negative padding
        .overlay(
            PulseRingView(color: .accentColor, lineWidth: 2, isActive: isTargeted)
                .padding(-8)
                .allowsHitTesting(false)
        )
        // Existing accent border kept (complements the glow ring)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(isTargeted ? 0.5 : 0), lineWidth: 1.5)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        )
        .scaleEffect(dragScale)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .onChange(of: isTargeted) { targeted in
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                dragScale = targeted ? 1.05 : 1.0
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketConvertFile)) { note in
            if let handoff = note.object as? QuickActionHandoffFile {
                addToQueue(handoff.fileURL, cleanupDirectory: handoff.handoffDirectory)
            } else if let url = note.object as? URL {
                addToQueue(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketReprocessItem)) { note in
            guard let req = note.object as? ReprocessRequest else { return }
            guard conversion.jobs.contains(where: { $0.id == req.itemID }) else { return }
            guard consumeConversionOrShowPaywall() else { return }
            Task { @MainActor in
                let useAI = await allowedAISelection(req.useAI)
                _ = conversion.retry(req.itemID, useAI: useAI)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketSetShelfExpanded)) { note in
            guard let expanded = note.object as? Bool else { return }
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                isExpanded = expanded
            }
        }
        .onChange(of: totalWidth) { w in
            ShelfWindowController.shared.resizeToContent(width: w)
        }
    }

    // MARK: - Closed panel: [control strip] | [peek panel]

    private var closedPanel: some View {
        HStack(spacing: 0) {
            controlStrip

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: closedHeight * 0.6)

            peekPanel
                .frame(width: peekPanelWidth, height: closedHeight)
                .clipped()
        }
    }

    // MARK: - Control strip (left column)

    private var controlStrip: some View {
        VStack(spacing: 0) {
            controlButton(symbol: "xmark",
                          hoverColor: .red,
                          isHovered: hoverClose,
                          help: "Hide shelf") { ShelfWindowController.shared.hide() }
                .onHover { hoverClose = $0 }

            controlButton(symbol: "plus",
                          hoverColor: .green,
                          isHovered: hoverAdd,
                          help: "Add files") { openFilePicker() }
                .onHover { hoverAdd = $0 }

            controlButton(symbol: isExpanded ? "chevron.left" : "chevron.right",
                          hoverColor: Color(nsColor: .systemBlue),
                          isHovered: hoverToggle,
                          help: isExpanded ? "Collapse" : "Expand") {
                withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isExpanded.toggle() }
            }
            .onHover { hoverToggle = $0 }
        }
        .frame(width: controlStripWidth, height: closedHeight)
    }

    private func controlButton(
        symbol: String,
        hoverColor: Color,
        isHovered: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(hoverColor.opacity(isHovered ? 0.18 : 0))
                    .frame(width: buttonHeight - 8, height: buttonHeight - 8)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? hoverColor : .primary.opacity(0.7))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: controlStripWidth, height: buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    // MARK: - Peek panel (right column)

    private var peekPanel: some View {
        Group {
            if let activeJob = conversion.jobs.first(where: \.isRunning) {
                peekJobView(activeJob)
            } else if let lastJob = conversion.jobs.last {
                peekJobView(lastJob)
            } else {
                peekIdleView
            }
        }
    }

    private var peekIdleView: some View {
        VStack(spacing: 6) {
            Group {
                if #available(macOS 14.0, *) {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.45))
                        .symbolEffect(.bounce, value: isTargeted)
                } else {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.45))
                }
            }
            .offset(y: floatOffset)
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: floatOffset
            )
            .onAppear { floatOffset = 2 }

            Text(isTargeted ? "Release to convert" : "Drop files here")
                .font(.system(size: 11))
                .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    private func peekJobView(_ job: ConversionJob) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if job.isRunning {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
                        .frame(width: 42, height: 42)
                    ArcProgressRing(progress: job.progress)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 42, height: 42)
                        .animation(.linear(duration: 0.4), value: job.progress)
                }
                peekFileIcon(job)
                    .frame(width: 30, height: 30)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                peekStageLabel(job)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private func peekFileIcon(_ job: ConversionJob) -> some View {
        if FileManager.default.fileExists(atPath: job.sourceURL.path),
           let icon = NSWorkspace.shared.icon(forFile: job.sourceURL.path) as NSImage? {
            Image(nsImage: icon).resizable().interpolation(.high).antialiased(true)
        } else {
            Image(systemName: "doc")
                .font(.system(size: 18))
                .foregroundStyle(.primary.opacity(0.5))
        }
    }

    private func peekStageLabel(_ job: ConversionJob) -> some View {
        Group {
            switch job.stage {
            case .complete:
                Label("Done", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label("Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Label("Cancelled", systemImage: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            default:
                Text(peekStageName(job.stage))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10))
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: job.stage)
    }

    private func peekStageName(_ stage: ConversionStage) -> String {
        switch stage {
        case .queued:         return "Queued"
        case .copying:        return "Copying…"
        case .extracting:     return "Reading…"
        case .python:         return "Processing…"
        case .postProcessing: return "Refining…"
        default:              return ""
        }
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        // No extra separator here — the closedPanel divider already separates the two zones.
        Group {
            if conversion.jobs.isEmpty && isAnyConverting {
                conversionView
            } else if conversion.jobs.isEmpty {
                emptyView
            } else {
                itemsView
            }
        }
    }

    private var emptyView: some View {
        Text(isTargeted ? "Release to convert" : "Drop documents here")
            .font(.system(size: 12, weight: isTargeted ? .semibold : .regular))
            .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.6))
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
    }

    private var conversionView: some View {
        HStack(spacing: 8) {
            ConversionIconView(isAnimating: isAnyConverting, size: 36)
            Text("Converting…")
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private var itemsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: itemSpacing) {
                ForEach(conversion.jobs.prefix(maxVisible)) { item in
                    ShelfItemView(
                        item: item,
                        onCancel: { conversion.cancel(item.id) },
                        onRetry: { _ = conversion.retry(item.id) }
                    ) {
                        withAnimation(.spring(duration: 0.25)) {
                            conversion.remove(item.id)
                        }
                    }
                    .frame(width: itemWidth)
                    .transition(.asymmetric(
                        insertion: .push(from: .trailing).combined(with: .opacity),
                        removal:   .push(from: .leading).combined(with: .opacity)
                    ))
                }
                if conversion.jobs.count > maxVisible {
                    overflowBadge
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var overflowBadge: some View {
        let extra = conversion.jobs.count - maxVisible
        return ZStack {
            ForEach(0..<min(3, extra), id: \.self) { i in
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                    .frame(width: 38, height: 44)
                    .offset(x: CGFloat(i) * 3, y: CGFloat(-i) * 2)
            }
            Text("+\(extra)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .frame(width: itemWidth)
        .help("\(extra) more queued")
        .onTapGesture { withAnimation { isExpanded = true } }
    }

    // MARK: - File picker (appears near shelf)

    private func openFilePicker() {
        guard store.canConvert else { showPaywall = true; return }
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isExpanded = true }
        FileAccessService.shared
            .chooseDocuments(allowsMultipleSelection: true, positioningNear: ShelfWindowController.shared.window)
            .forEach { addToQueue($0) }
    }

    // MARK: - Drop handler

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { showPaywall = true; return false }
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isExpanded = true }
        FileAccessService.shared.loadFileURLs(from: providers) { url in
            self.addToQueue(url)
        }
        return true
    }

    // MARK: - Queue management

    private func addToQueue(_ url: URL, cleanupDirectory: URL? = nil) {
        guard !conversion.jobs.contains(where: { $0.sourceURL == url && $0.isRunning }) else { return }
        do {
            try FileAccessService.shared.validateReadableInput(url)
        } catch {
            let message = FileAccessService.userVisibleMessage(for: error)
            AppLog.fileAccess.error("Rejected shelf input before queue: \(message, privacy: .private)")
            conversion.addRejected(url, message: message)
            if let cleanupDirectory {
                cleanupQuickActionHandoffIfDone(cleanupDirectory)
            }
            return
        }
        guard consumeConversionOrShowPaywall() else {
            if let cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanupDirectory)
            }
            return
        }
        NotificationCenter.default.post(name: .upmarketConversionStarted, object: nil)
        let id = conversion.add(url)
        Task { @MainActor in
            while conversion.jobs.first(where: { $0.id == id })?.isRunning == true {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if !conversion.isConverting {
                NotificationCenter.default.post(name: .upmarketConversionEnded, object: nil)
            }
            if store.shouldShowTrialPaywallAfterConversion() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    NotificationCenter.default.post(name: .showPaywall, object: nil)
                }
            }
            if let cleanupDirectory {
                cleanupQuickActionHandoffIfDone(cleanupDirectory)
            }
        }
    }

    private func cleanupQuickActionHandoffIfDone(_ directory: URL) {
        let stillNeeded = conversion.jobs.contains { job in
            job.isRunning && job.sourceURL.deletingLastPathComponent() == directory
        }
        guard !stillNeeded else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func consumeConversionOrShowPaywall() -> Bool {
        guard store.consumeConversion() else {
            showPaywall = true
            return false
        }
        return true
    }

    private func allowedAISelection(_ requested: Bool) async -> Bool {
        guard requested else { return false }
        return await modelManager.aiUseUnavailableReasonAfterChecking(hasPro: store.hasProOrAbove) == nil
    }
}

// MARK: - Resize cursor

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Shelf Item View

struct ShelfItemView: View {
    let item: ConversionJob
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    @State private var showActions = false
    @State private var now = Date()
    @State private var showCopied = false
    private let device = DeviceCapability.shared

    private var isStalled: Bool {
        item.isStalled || item.hasNoRecentProgress(referenceDate: now, threshold: 60)
    }

    var body: some View {
        VStack(spacing: 3) {
            iconWithArc
            Text(showCopied ? "Copied!" : item.name)
                .font(.system(size: 9, weight: showCopied ? .semibold : .regular))
                .foregroundStyle(showCopied ? Color.accentColor : .primary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 56)
                .animation(.easeInOut(duration: 0.15), value: showCopied)
            statusText
            // Persistent action row for terminal states; hover cancel for running
            if item.isRunning {
                // Reserve the same height so card doesn't shift when a job finishes
                Color.clear.frame(height: persistentActionsHeight)
            } else {
                persistentActions
            }
        }
        .padding(.vertical, 6)
        // Cancel button on hover for running jobs only
        .overlay(alignment: .bottom) {
            if item.isRunning && showActions {
                runningHoverActions
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .padding(.bottom, 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { showActions = $0 }
        .onTapGesture(count: 2) { handleDoubleClick() }
        .onTapGesture(count: 1) { handleSingleClick() }
        .contextMenu { contextMenuItems }
        .task(id: item.id) {
            while item.isRunning {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                now = Date()
            }
        }
    }

    // MARK: - Icon with arc ring

    // Wraps the file icon in an arc progress ring while the job is running.
    // The ring sits at 46×46; the icon is 32×32 centred inside it.
    // The state badge is anchored bottom-right of the outer 46pt frame.
    @ViewBuilder private var iconWithArc: some View {
        ZStack {
            if item.isRunning {
                // Track
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 3)
                    .frame(width: 46, height: 46)
                // Progress arc
                ArcProgressRing(progress: item.progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 46, height: 46)
                    .animation(.linear(duration: 0.4), value: item.progress)
            }
            // File icon — 32pt when ring active, 36pt when not (existing size)
            fileIcon
                .frame(width: item.isRunning ? 32 : 36, height: item.isRunning ? 32 : 36)
            // State badge offset to bottom-right corner of the 46pt frame
            stateIndicator
                .offset(x: 13, y: 13)
        }
        .frame(width: 46, height: 46)
    }

    @ViewBuilder private var fileIcon: some View {
        if FileManager.default.fileExists(atPath: item.sourceURL.path),
           let icon = NSWorkspace.shared.icon(forFile: item.sourceURL.path) as NSImage? {
            Image(nsImage: icon).resizable().interpolation(.high).antialiased(true)
        } else {
            Image(systemName: extensionIcon)
                .font(.system(size: 24)).foregroundStyle(.primary.opacity(0.6))
        }
    }

    @ViewBuilder private var stateIndicator: some View {
        switch item.stage {
        case .queued:
            EmptyView()
        case .copying, .extracting, .python, .postProcessing:
            if isStalled {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.yellow)
                    .background(Color.black.opacity(0.4), in: Circle())
            } else if #available(macOS 15.0, *) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(2).background(Color.accentColor, in: Circle())
                    .symbolEffect(.rotate, isActive: true)
            } else {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
            }
        case .complete:
            if case .success = item.result {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.green)
                    .background(Color.black.opacity(0.4), in: Circle())
            }
        case .failed, .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.red)
                .background(Color.black.opacity(0.4), in: Circle())
        }
    }

    // MARK: - Action rows

    // Fixed height used to reserve space while a job is running so the card
    // height doesn't shift the moment the job finishes.
    private let persistentActionsHeight: CGFloat = 22

    // Always-visible buttons for terminal (non-running) jobs.
    private var persistentActions: some View {
        HStack(spacing: 4) {
            if let output = item.result?.output {
                Button {
                    FileAccessService.shared.copyMarkdown(output.markdown)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Copy Markdown")

                Button { handleDoubleClick() } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 10))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Open in editor")
            }

            if item.result?.errorMessage != nil {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Retry")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Remove")
        }
        .frame(height: persistentActionsHeight)
    }

    // Cancel-only overlay shown on hover while the job is running.
    private var runningHoverActions: some View {
        HStack(spacing: 3) {
            Button(action: onCancel) {
                Image(systemName: "stop.fill").font(.system(size: 8))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Cancel")
        }
    }

    // MARK: - Status text with crossfade

    @ViewBuilder private var statusText: some View {
        Group {
            if isStalled {
                Text("No progress")
                    .foregroundStyle(.yellow)
                    .help("No progress detected. Conversion is still running; you can cancel and retry.")
            } else if let message = item.result?.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .truncationMode(.tail)
                    .help(message)
            } else if item.isRunning {
                Text(stageLabel)
                    .foregroundStyle(.primary.opacity(0.65))
                    .help("Still working: \(stageLabel)")
            } else {
                Text(stageLabel)
                    .foregroundStyle(.primary.opacity(0.65))
            }
        }
        .font(.system(size: 9))
        .lineLimit(1)
        .frame(width: 56, height: 10)
        // Stage label crossfades on every stage change
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: item.stage)
    }

    // MARK: - Interactions

    private func handleSingleClick() {
        if let output = item.result?.output {
            FileAccessService.shared.copyMarkdown(output.markdown)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        }
    }

    private func handleDoubleClick() {
        if let output = item.result?.output {
            openInDefaultApp(output.markdown, title: output.title)
        }
    }

    private func openInDefaultApp(_ markdown: String, title: String) {
        Task { @MainActor in
            let savedURL = SavePreference.shared.save(markdown: markdown, title: title, sourceURL: item.sourceURL)
            if let url = savedURL { FileAccessService.shared.open(url) }
        }
    }

    private func saveMarkdown(_ markdown: String, title: String) {
        Task { @MainActor in
            _ = FileAccessService.shared.saveMarkdown(markdown, title: title)
        }
    }

    private func reprocess(useAI: Bool) {
        NotificationCenter.default.post(
            name: .upmarketReprocessItem,
            object: ReprocessRequest(url: item.sourceURL, itemID: item.id, useAI: useAI, enhanced: useAI)
        )
    }

    // MARK: - Context menu

    @ViewBuilder private var contextMenuItems: some View {
        if item.isRunning {
            Button("Cancel Conversion") { onCancel() }
            Divider()
        } else if item.result?.errorMessage != nil {
            Button("Retry Conversion") { onRetry() }
            Divider()
        }
        if let output = item.result?.output {
            Button("Open in Markdown Editor") { openInDefaultApp(output.markdown, title: output.title) }
            Divider()
            Button("Copy Markdown") {
                FileAccessService.shared.copyMarkdown(output.markdown)
            }
            Button("Copy File Path") {
                FileAccessService.shared.copyFilePath(item.sourceURL)
            }
            Divider()
            Button("Save As…") { saveMarkdown(output.markdown, title: output.title) }
            Divider()
            if sourceExists {
                Menu("Reprocess") {
                    Button("Fast (instant)")       { reprocess(useAI: false) }
                    if device.supportsUpmarketAI {
                        Button("Upmarket AI (best)")   { reprocess(useAI: true)  }
                    }
                }
                Divider()
            }
        }
        if sourceExists {
            Button("Show Original in Finder") {
                FileAccessService.shared.revealInFinder(item.sourceURL)
            }
            Divider()
        }
        Button("Remove from Shelf", role: .destructive) { onRemove() }
    }

    // MARK: - Helpers

    private var sourceExists: Bool {
        FileManager.default.fileExists(atPath: item.sourceURL.path)
    }

    private var extensionIcon: String {
        switch item.sourceURL.pathExtension.lowercased() {
        case "pdf":                return "doc.richtext"
        case "docx", "doc":        return "doc.text"
        case "pptx", "ppt":        return "rectangle.on.rectangle"
        case "xlsx", "xls":        return "tablecells"
        case "html", "htm":        return "globe"
        case "mp3", "m4a", "wav":  return "waveform"
        case "png", "jpg", "jpeg": return "photo"
        default:                   return "doc"
        }
    }

    private var stageLabel: String {
        switch item.stage {
        case .queued:         return "Queued"
        case .copying:        return "Copying"
        case .extracting:     return "Reading"
        case .python:         return "Processing"
        case .postProcessing: return "Refining"
        case .complete:       return "Done"
        case .failed:         return "Failed"
        case .cancelled:      return "Cancelled"
        }
    }
}

// MARK: - Button style

struct ShelfActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(4)
            .background(Color.black.opacity(configuration.isPressed ? 0.85 : 0.65), in: Circle())
    }
}
