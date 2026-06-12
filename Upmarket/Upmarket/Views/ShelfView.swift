import SwiftUI
import UniformTypeIdentifiers
import AppKit
import OSLog

enum ShelfLayout {
    static let controlStripWidth: CGFloat = 48
    static let peekPanelWidth: CGFloat = 168
    static let expandedPanelWidth: CGFloat = 420
    static let closedHeight: CGFloat = 132
    static let itemWidth: CGFloat = 64
    static let itemSpacing: CGFloat = 8
    static let maxVisible = 5

    static var closedWidth: CGFloat {
        controlStripWidth + 1 + peekPanelWidth
    }

    static var closedSize: CGSize {
        CGSize(width: closedWidth, height: closedHeight)
    }
}

private enum ShelfTourSpotlight: String {
    case closeButton
    case addButton
    case expandButton
}

private enum ShelfDisplayMode: Equatable {
    case peek
    case queue
}

struct ShelfView: View {

    @EnvironmentObject private var conversion: ConversionQueue
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false
    @State private var isShelfHovered = false
    @State private var displayMode: ShelfDisplayMode = .peek
    @State private var dragScale: CGFloat = 1.0
    @State private var tourSpotlight: ShelfTourSpotlight?

    // Hover states per button
    @State private var hoverClose  = false
    @State private var hoverAdd    = false
    @State private var hoverToggle = false

    // UI-5: asymmetric closed state
    // Left: narrow control strip  |  Right: peek panel showing live job state
    private let windowSize: AppTheme.WindowSize = .compact
    private let controlStripWidth = ShelfLayout.controlStripWidth
    private let peekPanelWidth = ShelfLayout.peekPanelWidth
    private let closedHeight = ShelfLayout.closedHeight
    private let itemWidth = ShelfLayout.itemWidth
    private let itemSpacing = ShelfLayout.itemSpacing
    private let maxVisible = ShelfLayout.maxVisible

    private var buttonHeight: CGFloat { closedHeight / 3 }  // 44pt each

    private var hasError: Bool {
        conversion.jobs.contains { $0.stage == .failed }
    }

    private var hasQueueItems: Bool { !conversion.jobs.isEmpty }

    private var effectiveMode: ShelfDisplayMode {
        if displayMode == .queue, hasQueueItems {
            return .queue
        }
        return .peek
    }

    private var isShelfActive: Bool {
        effectiveMode == .queue || isTargeted
    }

    private var shelfGlassOpacity: CGFloat {
        isShelfActive ? 1.0 : 0.72
    }

    private var shelfSolidFillOpacity: Double {
        isShelfActive ? 0.72 : 0
    }

    private var closedWidth: CGFloat { controlStripWidth + 1 + peekPanelWidth }

    private var totalWidth: CGFloat {
        switch effectiveMode {
        case .peek:
            return closedWidth
        case .queue:
            return closedWidth + ShelfLayout.expandedPanelWidth
        }
    }

    private var totalHeight: CGFloat {
        closedHeight
    }

    var body: some View {
        HStack(spacing: 0) {
            closedPanel
                .transition(.move(edge: .leading).combined(with: .opacity))

            if effectiveMode == .queue {
                itemsView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: totalWidth, height: totalHeight)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: effectiveMode)
        .animation(.spring(duration: 0.25), value: conversion.jobs.count)
        .background(
            ContextualLiquidGlassBackground(
                cornerRadius: AppTheme.Radius.lg,
                opacity: shelfGlassOpacity,
                solidFillOpacity: shelfSolidFillOpacity,
                isTargeted: isTargeted,
                isConverting: conversion.isConverting,
                hasError: hasError
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg + 2)
                .strokeBorder(Color.primary.opacity(isTargeted ? 0.28 : 0), lineWidth: 1.5)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        )
        .scaleEffect(dragScale)
        .onHover { hovering in
            isShelfHovered = hovering
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .onChange(of: isTargeted) { targeted in
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                dragScale = targeted ? 1.05 : 1.0
            }
        }
        .onAppear {
            resizeShelfWindow()
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
            handleReprocessRequest(req)
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketSetShelfExpanded)) { note in
            guard let expanded = note.object as? Bool else { return }
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                displayMode = expanded ? (hasQueueItems ? .queue : .peek) : .peek
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketSetShelfSpotlight)) { note in
            withAnimation(.easeInOut(duration: 0.18)) {
                tourSpotlight = (note.object as? String).flatMap(ShelfTourSpotlight.init(rawValue:))
            }
        }
        .onChange(of: conversion.jobs.count) { count in
            if count == 0 {
                withAnimation(.spring(duration: 0.25)) {
                    displayMode = .peek
                }
            }
        }
        .onChange(of: totalWidth) { _ in
            resizeShelfWindow()
        }
        .onChange(of: totalHeight) { _ in
            resizeShelfWindow()
        }
    }

    private func resizeShelfWindow() {
        let width = totalWidth
        let height = totalHeight
        DispatchQueue.main.async {
            ShelfWindowController.shared.resizeToContent(width: width, height: height)
        }
    }

    // MARK: - Closed panel: [control strip] | [peek panel]

    private var closedPanel: some View {
        HStack(spacing: 0) {
            controlStrip

            Rectangle()
                .fill(AppTheme.Colour.separator)
                .frame(width: 0.5, height: closedHeight)

            peekPanel
                .frame(width: peekPanelWidth, height: closedHeight)
                .clipped()
        }
    }

    // MARK: - Control strip (left column)

    private var controlStrip: some View {
        VStack(spacing: 14) {
            controlButton(symbol: "xmark",
                          hoverColor: AppTheme.Colour.shelfHoverClose,
                          isHovered: hoverClose,
                          isSpotlighted: tourSpotlight == .closeButton,
                          help: "Hide shelf",
                          accessibilityHint: "Hides the conversion shelf from the screen") {
                ShelfWindowController.shared.hide()
            }
            .onHover { hoverClose = $0 }

            controlButton(symbol: "plus",
                          hoverColor: AppTheme.Colour.shelfHoverAdd,
                          isHovered: hoverAdd,
                          isSpotlighted: tourSpotlight == .addButton,
                          help: "Add files",
                          accessibilityHint: "Opens a file picker to add documents to the conversion queue") {
                openFilePicker()
            }
            .onHover { hoverAdd = $0 }

            controlButton(symbol: queueControlSymbol,
                          hoverColor: AppTheme.Colour.shelfHoverToggle,
                          isHovered: hoverToggle,
                          isSpotlighted: tourSpotlight == .expandButton,
                          help: queueControlHelp,
                          accessibilityHint: queueControlA11yHint) {
                toggleQueueMode()
            }
            .onHover { hoverToggle = $0 }
        }
        .frame(width: controlStripWidth, height: closedHeight)
        .background(AppTheme.Colour.shelfControlStripFill)
    }

    private var queueControlSymbol: String {
        if effectiveMode == .queue || !hasQueueItems {
            return "arrow.left"
        }
        return "arrow.right"
    }

    private var queueControlHelp: String {
        if effectiveMode == .queue || !hasQueueItems {
            return "Collapse shelf"
        }
        return "Show queue"
    }

    private var queueControlA11yHint: String {
        if effectiveMode == .queue || !hasQueueItems {
            return "Collapses the conversion queue panel"
        }
        return "Expands to show all queued documents"
    }

    private func toggleQueueMode() {
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            if effectiveMode == .queue || !hasQueueItems {
                displayMode = .peek
            } else {
                displayMode = .queue
            }
        }
    }

    private func controlButton(
        symbol: String,
        hoverColor: Color,
        isHovered: Bool,
        isSpotlighted: Bool,
        isEnabled: Bool = true,
        help: String,
        accessibilityHint: String = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? hoverColor : Color.clear)
                    .frame(width: 26, height: 26)

                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(controlSymbolColor(hoverColor: hoverColor, isHovered: isHovered, isSpotlighted: isSpotlighted, isEnabled: isEnabled))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityHint(accessibilityHint)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.18), value: isSpotlighted)
    }

    private func controlSymbolColor(
        hoverColor: Color,
        isHovered: Bool,
        isSpotlighted: Bool,
        isEnabled: Bool
    ) -> Color {
        guard isEnabled else { return .primary.opacity(0.26) }
        if isHovered { return .white }
        return .primary.opacity(isSpotlighted ? 0.88 : 0.68)
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

    // Float driven by TimelineView — starts immediately, never double-starts
    // on re-appear, self-contained with no @State offset variable.
    private var peekIdleView: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let float = sin(t * .pi / 1.5) * 2   // ±2pt, 3s period
            VStack(spacing: AppTheme.Spacing.sm) {
                Group {
                    if #available(macOS 14.0, *) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: windowSize.iconSize))
                            .foregroundStyle(.primary.opacity(isTargeted ? 0.65 : 0.45))
                            .symbolEffect(.bounce, value: isTargeted)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: windowSize.iconSize))
                            .foregroundStyle(.primary.opacity(isTargeted ? 0.65 : 0.45))
                    }
                }
                .offset(y: float)

                Text(isTargeted ? "Release to convert" : "Drop documents here")
                    .font(windowSize.fontCaption)
                    .foregroundStyle(.primary.opacity(isTargeted ? 0.65 : 0.4))
                    .multilineTextAlignment(.center)
            }
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, AppTheme.Spacing.md)
        }
    }

    private func peekJobView(_ job: ConversionJob) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack(alignment: .topTrailing) {
                ArcRingView(
                    progress: job.isRunning ? job.progress : 1,
                    size: 42,
                    lineWidth: 2.5,
                    ringColor: peekRingColor(job)
                ) {
                    peekGlyph(job)
                        .frame(width: 18, height: 18)
                }

                if conversion.jobs.count > 1 {
                    AppBadge("\(conversion.jobs.count)", variant: .count)
                        .offset(x: 8, y: -8)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(job.name)
                    .font(windowSize.fontBody)
                    .lineLimit(1)
                    .truncationMode(.middle)

                peekStageLabel(job)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private func peekGlyph(_ job: ConversionJob) -> some View {
        Image(systemName: job.glyphName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.Colour.iconGlyphTint)
    }

    private func peekStageLabel(_ job: ConversionJob) -> some View {
        Group {
            switch job.stage {
            case .complete:
                Label("Done", systemImage: "checkmark")
                    .foregroundStyle(AppTheme.Status.complete)
            case .failed:
                Label("Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.Status.failed)
            case .cancelled:
                Label("Cancelled", systemImage: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            default:
                Text(peekStageName(job.stage))
                    .foregroundStyle(.secondary)
            }
        }
        .font(windowSize.fontCaption)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: job.stage)
    }

    private func peekStageName(_ stage: ConversionStage) -> String {
        switch stage {
        case .queued:         return "Queued"
        case .copying, .analysing: return "Preparing…"
        case .extracting:     return "Reading…"
        case .python:         return "Processing…"
        case .postProcessing: return "Refining…"
        default:              return ""
        }
    }

    // MARK: - Expanded queue

    private var itemsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: itemSpacing) {
                let ordered = Array(conversion.jobs.reversed())
                let visible = Array(ordered.prefix(maxVisible))
                let extra = max(0, ordered.count - visible.count)
                let doneCount = conversion.jobs.filter { !$0.isRunning }.count

                ForEach(visible) { item in
                    ShelfItemView(
                        item: item,
                        onCancel: { conversion.cancel(item.id) },
                        onRetry: { _ = conversion.retry(item.id) }
                    ) {
                        withAnimation(.spring(duration: 0.25)) {
                            conversion.remove(item.id)
                        }
                    }
                    .frame(width: itemCardWidth(for: item))
                    .transition(.asymmetric(
                        insertion: .push(from: .trailing).combined(with: .opacity),
                        removal:   .push(from: .leading).combined(with: .opacity)
                    ))
                }
                if extra > 0 {
                    overflowBadge(extra: extra)
                }
                if doneCount > 0 {
                    clearDoneButton
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
        }
        .frame(width: ShelfLayout.expandedPanelWidth, height: closedHeight)
    }

    private func overflowBadge(extra: Int) -> some View {
        return ZStack {
            ForEach(0..<min(3, extra), id: \.self) { i in
                RoundedRectangle(cornerRadius: windowSize.cornerRadius)
                    .fill(AppTheme.Colour.shelfOverflowFill)
                    .overlay(RoundedRectangle(cornerRadius: windowSize.cornerRadius).strokeBorder(AppTheme.Colour.separator, lineWidth: 0.5))
                    .frame(width: 38, height: 48)
                    .offset(x: CGFloat(i) * 3, y: CGFloat(-i) * 2)
            }
            Text("+\(extra)")
                .font(windowSize.fontCaption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .frame(width: overflowCardWidth)
        .help("\(extra) more queued")
        .accessibilityLabel("\(extra) more items queued")
        .accessibilityHint("Double-tap to show all queued items")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { withAnimation { displayMode = .queue } }
    }

    private var clearDoneButton: some View {
        Button {
            clearTerminalJobs()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colour.glassFillThin)
                        .overlay(
                            Circle()
                                .strokeBorder(AppTheme.Colour.border, lineWidth: 0.5)
                        )
                        .frame(width: 30, height: 30)
                    Image(systemName: "broom")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                Text("Clear")
                    .font(windowSize.fontCaption)
            }
            .frame(width: clearButtonWidth)
        }
        .buttonStyle(AppPlainButtonStyle())
        .help("Clear completed")
        .accessibilityLabel("Clear completed")
        .accessibilityHint("Removes completed, failed, and cancelled items from the shelf")
    }

    private func clearTerminalJobs() {
        let ids = conversion.jobs
            .filter { !$0.isRunning }
            .map(\.id)
        guard !ids.isEmpty else { return }
        ids.forEach { conversion.remove($0) }
    }

    private func peekRingColor(_ job: ConversionJob) -> Color {
        if job.isRunning { return .accentColor }
        switch job.stage {
        case .complete:
            return AppTheme.Status.complete
        case .failed:
            return AppTheme.Status.failed
        case .cancelled:
            return .secondary.opacity(0.55)
        default:
            return .accentColor
        }
    }

    // MARK: - File picker (appears near shelf)

    private func openFilePicker() {
        guard store.canConvert else { PaywallWindowController.shared.show(); return }
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            displayMode = hasQueueItems ? .queue : .peek
        }
        FileAccessService.shared
            .chooseDocuments(allowsMultipleSelection: true, positioningNear: ShelfWindowController.shared.window)
            .forEach { addToQueue($0) }
    }

    // MARK: - Drop handler

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { PaywallWindowController.shared.show(); return false }
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            displayMode = .peek
        }
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
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            displayMode = .queue
        }
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
            PaywallWindowController.shared.show()
            return false
        }
        return true
    }

    private func hasJob(with id: UUID) -> Bool {
        conversion.jobs.contains { $0.id == id }
    }

    private func retryJob(id: UUID, useAI: Bool) {
        _ = conversion.retry(id, useAI: useAI)
    }

    private func handleReprocessRequest(_ request: ReprocessRequest) {
        guard hasJob(with: request.itemID) else { return }
        guard consumeConversionOrShowPaywall() else { return }
        Task { @MainActor in
            let useAI = await allowedAISelection(request.useAI)
            retryJob(id: request.itemID, useAI: useAI)
        }
    }

    private func allowedAISelection(_ requested: Bool) async -> Bool {
        guard requested else { return false }
        return await modelManager.aiUseUnavailableReasonAfterChecking(hasPro: store.hasProOrAbove) == nil
    }

    private var clearButtonWidth: CGFloat { 40 }

    private var overflowCardWidth: CGFloat { 56 }

    private func itemCardWidth(for job: ConversionJob) -> CGFloat {
        job.isRunning ? 96 : 72
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
    private let device = DeviceCapability.shared
    private let windowSize: AppTheme.WindowSize = .compact
    private let runningCardWidth: CGFloat = 96
    private let terminalCardWidth: CGFloat = 72
    private let persistentActionsHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            iconWithArc
            Text(item.name)
                .font(windowSize.fontCaption)
                .foregroundStyle(Color.primary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: isRunningCard ? runningCardWidth - 16 : terminalCardWidth - 10)
            actionRow
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, 10)
        .frame(width: cardWidth, height: 104)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colour.shelfCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Colour.separator, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { handleDoubleClick() }
        .contextMenu { contextMenuItems }
    }

    private var isRunningCard: Bool {
        item.isRunning
    }

    private var cardWidth: CGFloat {
        item.isRunning ? runningCardWidth : terminalCardWidth
    }

    // MARK: - Icon with arc ring

    // Wraps the file icon in an arc progress ring while the job is running.
    // The ring sits at 46×46; the icon is 32×32 centred inside it.
    // The state badge is anchored bottom-right of the outer 46pt frame.
    @ViewBuilder private var iconWithArc: some View {
        ArcRingView(
            progress: item.isRunning ? item.progress : 1,
            size: 40,
            lineWidth: 3,
            ringColor: ringColor
        ) {
            fileGlyph
                .frame(width: 18, height: 18)
        }
        .overlay(alignment: .bottomTrailing) {
            stateIndicator
                .offset(x: 3, y: 3)
        }
    }

    private var ringColor: Color {
        switch item.stage {
        case .failed:
            return AppTheme.Status.failed
        case .complete:
            return AppTheme.Status.complete
        case .cancelled:
            return .secondary.opacity(0.55)
        default:
            return .accentColor
        }
    }

    @ViewBuilder private var fileGlyph: some View {
        Image(systemName: item.glyphName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.Colour.iconGlyphTint)
    }

    @ViewBuilder private var stateIndicator: some View {
        switch item.stage {
        case .queued:
            EmptyView()
        case .copying, .analysing, .extracting, .python, .postProcessing:
            EmptyView()
        case .complete:
            if case .success = item.result {
                terminalBadge(color: AppTheme.Status.complete, symbol: "checkmark")
            }
        case .failed, .cancelled:
            terminalBadge(color: item.stage == .cancelled ? .secondary.opacity(0.55) : AppTheme.Status.failed, symbol: "xmark")
        }
    }

    // MARK: - Action rows

    private var actionRow: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if item.isRunning {
                Button(action: onCancel) {
                    Image(systemName: "stop.fill").font(.system(size: 7))
                }
                .buttonStyle(AppActionButtonStyle(size: .compact))
                .help("Cancel")
            } else if let output = item.result?.output {
                Button {
                    copyOutput(output)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 9))
                }
                .buttonStyle(AppActionButtonStyle(size: .compact))
                .help("Copy")

                Button { handleDoubleClick() } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 9))
                }
                .buttonStyle(AppActionButtonStyle(size: .compact))
                .help("Show")

                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(AppActionButtonStyle(size: .compact))
                .help("Delete")
            } else if item.stage == .failed || item.stage == .cancelled {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9))
                }
                .buttonStyle(AppActionButtonStyle(size: .compact))
                .help("Retry")

                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(AppActionButtonStyle(size: .compact))
                .help("Delete")
            } else {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(AppActionButtonStyle(size: .compact))
                .help("Delete")
            }
        }
        .frame(height: persistentActionsHeight)
    }

    // MARK: - Interactions

    private func handleDoubleClick() {
        if let output = item.result?.output {
            openInDefaultApp(output)
        }
    }

    private func openInDefaultApp(_ output: ConversionOutput) {
        Task { @MainActor in
            let formatted = formattedOutput(output)
            let savedURL = SavePreference.shared.save(
                markdown: formatted.text,
                title: output.title,
                sourceURL: item.sourceURL,
                fileExtension: formatted.fileExtension
            )
            if let url = savedURL { FileAccessService.shared.open(url) }
        }
    }

    private func saveOutput(_ output: ConversionOutput) {
        Task { @MainActor in
            let formatted = formattedOutput(output)
            _ = FileAccessService.shared.saveMarkdown(
                formatted.text,
                title: output.title,
                fileExtension: formatted.fileExtension
            )
        }
    }

    private func copyOutput(_ output: ConversionOutput) {
        FileAccessService.shared.copyMarkdown(formattedOutput(output).text)
    }

    private func formattedOutput(_ output: ConversionOutput) -> FormattedConversionOutput {
        OutputFormatter.format(
            output,
            sourceDisplayName: item.sourceURL.lastPathComponent,
            mode: OutputPreference.shared.mode
        )
    }

    private func reprocess(useAI: Bool) {
        NotificationCenter.default.post(
            name: .upmarketReprocessItem,
            object: ReprocessRequest(itemID: item.id, useAI: useAI)
        )
    }

    // MARK: - Context menu

    @ViewBuilder private var contextMenuItems: some View {
        if item.isRunning {
            Button("Cancel Conversion") { onCancel() }
            Divider()
        }
        if let output = item.result?.output {
            Button("Open in Editor") { openInDefaultApp(output) }
            Divider()
            Button("Copy Output") {
                copyOutput(output)
            }
            Button("Copy File Path") {
                FileAccessService.shared.copyFilePath(item.sourceURL)
            }
            Divider()
            Button("Save As…") { saveOutput(output) }
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

    private var stageLabel: String {
        switch item.stage {
        case .queued:         return "Queued"
        case .copying, .analysing: return "Preparing…"
        case .extracting:     return "Reading…"
        case .python:         return "Processing…"
        case .postProcessing: return "Refining…"
        case .complete:       return "Done"
        case .failed:         return "Failed"
        case .cancelled:      return "Cancelled"
        }
    }

    @ViewBuilder private func terminalBadge(color: Color, symbol: String) -> some View {
        AppStatusToken(
            color: color,
            kind: symbol == "checkmark" ? .check : .cross,
            size: 15,
            ringWidth: 1.5,
            glyphStrokeWidth: 1.9,
            glyphSizeRatio: 9.0 / 15.0
        )
    }
}
