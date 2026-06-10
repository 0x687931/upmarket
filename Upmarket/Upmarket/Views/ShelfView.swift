import SwiftUI
import UniformTypeIdentifiers
import AppKit
import OSLog

enum ShelfLayout {
    static let miniSize = CGSize(width: 56, height: 56)
    static let controlStripWidth: CGFloat = 48
    static let peekPanelWidth: CGFloat = 168
    static let closedHeight: CGFloat = 132
    static let itemWidth: CGFloat = 64
    static let itemSpacing: CGFloat = 8
    static let maxVisible = 5

    static var closedWidth: CGFloat {
        controlStripWidth + 1 + peekPanelWidth
    }
}

private enum ShelfTourSpotlight: String {
    case closeButton
    case addButton
    case expandButton
}

private enum ShelfDisplayMode: Equatable {
    case mini
    case peek
    case queue
}

struct ShelfView: View {

    @EnvironmentObject private var conversion: ConversionQueue
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false
    @State private var isShelfHovered = false
    @State private var displayMode: ShelfDisplayMode = .mini
    @State private var dragScale: CGFloat = 1.0
    @State private var selectedJobID: UUID?
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

        if isShelfHovered || isTargeted || tourSpotlight != nil {
            return .peek
        }

        switch displayMode {
        case .mini:
            return .mini
        case .peek:
            return .peek
        case .queue:
            return hasQueueItems ? .queue : .mini
        }
    }

    private var isShelfActive: Bool {
        effectiveMode != .mini || isTargeted || selectedJobID != nil
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
        case .mini:
            return ShelfLayout.miniSize.width
        case .peek:
            return closedWidth
        case .queue:
            break
        }

        let count = min(conversion.jobs.count, maxVisible)
        let content = CGFloat(count) * (itemWidth + itemSpacing) + itemSpacing
        let overflow: CGFloat = conversion.jobs.count > maxVisible ? itemWidth + itemSpacing : 0
        return closedWidth + 8 + content + overflow
    }

    private var totalHeight: CGFloat {
        effectiveMode == .mini ? ShelfLayout.miniSize.height : closedHeight
    }

    var body: some View {
        HStack(spacing: 0) {
            if effectiveMode == .mini {
                miniShelf
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            } else {
                closedPanel
                    .transition(.move(edge: .leading).combined(with: .opacity))

                if effectiveMode == .queue {
                    itemsView
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
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
                displayMode = expanded ? (hasQueueItems ? .queue : .peek) : .mini
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
                    displayMode = .mini
                    selectedJobID = nil
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

    // MARK: - Mini shelf

    private var miniShelf: some View {
        ZStack(alignment: .topTrailing) {
            miniSymbol

            if hasQueueItems {
                Text("\(min(conversion.jobs.count, 99))")
                    .font(windowSize.fontCaption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .offset(x: 4, y: -4)
            }
        }
        .frame(width: ShelfLayout.miniSize.width, height: ShelfLayout.miniSize.height)
        .contentShape(RoundedRectangle(cornerRadius: windowSize.cornerRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                displayMode = hasQueueItems ? .queue : .peek
            }
        }
        .help(hasQueueItems ? "Show queue" : "Drop files")
        .accessibilityLabel(hasQueueItems ? "Conversion shelf — \(conversion.jobs.count) items" : "Conversion shelf")
        .accessibilityHint(hasQueueItems ? "Double-tap to show the queue" : "Drop files here or double-tap to expand")
    }

    @ViewBuilder private var miniSymbol: some View {
        if let activeJob = conversion.jobs.first(where: \.isRunning) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                    .frame(width: 34, height: 34)
                ArcProgressRing(progress: activeJob.progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: "doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.62))
            }
        } else if hasQueueItems {
            Image(systemName: "tray.full")
                .font(.system(size: windowSize.iconSize, weight: .medium))
                .foregroundStyle(.primary.opacity(0.62))
                .symbolRenderingMode(.hierarchical)
        } else {
            idleMiniSymbol
        }
    }

    private var idleMiniSymbol: some View {
        Image(systemName: "number")
            .font(.system(size: windowSize.iconSize, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.62))
            .symbolRenderingMode(.hierarchical)
    }

    // MARK: - Closed panel: [control strip] | [peek panel]

    private var closedPanel: some View {
        HStack(spacing: 0) {
            controlStrip

            Rectangle()
                .fill(Color.primary.opacity(0.07))
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
                          isSpotlighted: tourSpotlight == .closeButton,
                          help: "Hide shelf",
                          accessibilityHint: "Hides the conversion shelf from the screen") {
                ShelfWindowController.shared.hide()
            }
            .onHover { hoverClose = $0 }

            controlButton(symbol: "plus",
                          hoverColor: Color(nsColor: .labelColor),
                          isHovered: hoverAdd,
                          isSpotlighted: tourSpotlight == .addButton,
                          help: "Add files",
                          accessibilityHint: "Opens a file picker to add documents to the conversion queue") {
                openFilePicker()
            }
            .onHover { hoverAdd = $0 }

            controlButton(symbol: queueControlSymbol,
                          hoverColor: Color(nsColor: .labelColor),
                          isHovered: hoverToggle,
                          isSpotlighted: tourSpotlight == .expandButton,
                          help: queueControlHelp,
                          accessibilityHint: queueControlA11yHint) {
                toggleQueueMode()
            }
            .onHover { hoverToggle = $0 }
        }
        .frame(width: controlStripWidth, height: closedHeight)
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
                displayMode = .mini
                selectedJobID = nil
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
                RoundedRectangle(cornerRadius: windowSize.cornerRadius)
                    .fill(Color.primary.opacity(isSpotlighted ? 0.08 : (isHovered ? 0.045 : 0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: windowSize.cornerRadius)
                            .strokeBorder(Color.primary.opacity(isSpotlighted ? 0.24 : 0), lineWidth: 1)
                    )
                    .frame(width: controlStripWidth - 10, height: buttonHeight - 8)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(controlSymbolColor(hoverColor: hoverColor, isHovered: isHovered, isSpotlighted: isSpotlighted, isEnabled: isEnabled))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: controlStripWidth, height: buttonHeight)
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
        return isHovered ? hoverColor : .primary.opacity(isSpotlighted ? 0.88 : 0.68)
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

                Text(isTargeted ? "Release to convert" : "Drop files here")
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
                Label("Done", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
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
        .font(windowSize.fontCaption)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: job.stage)
    }

    private func peekStageName(_ stage: ConversionStage) -> String {
        switch stage {
        case .queued:         return "Queued"
        case .copying:        return "Copying…"
        case .analysing:      return "Analysing…"
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
                ForEach(conversion.jobs.prefix(maxVisible)) { item in
                    ShelfItemView(
                        item: item,
                        isSelected: selectedJobID == item.id,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                selectedJobID = item.id
                            }
                        },
                        onCancel: { conversion.cancel(item.id) },
                        onRetry: { _ = conversion.retry(item.id) }
                    ) {
                        if selectedJobID == item.id {
                            selectedJobID = nil
                        }
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
            .padding(.horizontal, AppTheme.Spacing.sm)
        }
    }

    private var overflowBadge: some View {
        let extra = conversion.jobs.count - maxVisible
        return ZStack {
            ForEach(0..<min(3, extra), id: \.self) { i in
                RoundedRectangle(cornerRadius: windowSize.cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: windowSize.cornerRadius).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                    .frame(width: 38, height: 44)
                    .offset(x: CGFloat(i) * 3, y: CGFloat(-i) * 2)
            }
            Text("+\(extra)")
                .font(windowSize.fontCaption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .frame(width: itemWidth)
        .help("\(extra) more queued")
        .accessibilityLabel("\(extra) more items queued")
        .accessibilityHint("Double-tap to show all queued items")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { withAnimation { displayMode = .queue } }
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
    let isSelected: Bool
    let onSelect: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    @State private var showActions = false
    @State private var now = Date()
    @State private var showCopied = false
    private let device = DeviceCapability.shared
    private let windowSize: AppTheme.WindowSize = .compact

    private var isStalled: Bool {
        item.isStalled || item.hasNoRecentProgress(referenceDate: now, threshold: 60)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            iconWithArc
            Text(showCopied ? "Copied!" : item.name)
                .font(showCopied ? windowSize.fontBody.weight(.semibold) : windowSize.fontCaption)
                .foregroundStyle(showCopied ? Color.primary : Color.primary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 56)
                .animation(.easeInOut(duration: 0.15), value: showCopied)
            statusText
            if item.isRunning {
                Color.clear.frame(height: persistentActionsHeight)
            } else {
                persistentActions
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(selectionBackground)
        .overlay(alignment: .bottom) {
            if item.isRunning && shouldShowRunningActions {
                runningHoverActions
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .padding(.bottom, AppTheme.Spacing.sm)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: windowSize.cornerRadius)
                .strokeBorder(
                    isSelected ? Color.primary.opacity(0.45) : .clear,
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeInOut(duration: 0.1)) { showActions = h } }
        .onTapGesture(count: 2) { handleDoubleClick() }
        .onTapGesture(count: 1) { handleSingleClick() }
        .contextMenu { contextMenuItems }
        // Liveness ticker — updates `now` while job is running
        .task(id: item.id) {
            while item.isRunning {
                try? await Task.sleep(for: .seconds(5))
                now = Date()
            }
        }
        // showCopied auto-reset — cancels if view disappears
        .task(id: showCopied) {
            guard showCopied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            showCopied = false
        }
    }

    private var shouldShowRunningActions: Bool {
        showActions || isStalled
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: windowSize.cornerRadius)
            .fill(isSelected ? Color.primary.opacity(0.06) : .clear)
            .animation(.easeInOut(duration: 0.12), value: isSelected)
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
        case .copying, .analysing, .extracting, .python, .postProcessing:
            if isStalled {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.yellow)
            } else if #available(macOS 15.0, *) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, isActive: true)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        case .complete:
            if case .success = item.result {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.Status.complete)
            }
        case .failed, .cancelled:
            Image(systemName: "xmark")
                .font(.system(size: 11)).foregroundStyle(AppTheme.Status.failed)
        }
    }

    // MARK: - Action rows

    // Fixed height used to reserve space while a job is running so the card
    // height doesn't shift the moment the job finishes.
    private let persistentActionsHeight: CGFloat = 22

    // Always-visible buttons for terminal (non-running) jobs.
    private var persistentActions: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if let output = item.result?.output {
                Button {
                    copyOutput(output)
                    showCopied = true   // task(id: showCopied) resets after 1.5s
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 9))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Copy Output")

                Button { handleDoubleClick() } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 9))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Open in editor")
            }

            if let errorMessage = item.result?.errorMessage {
                errorActions(for: errorMessage)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Remove")
        }
        .frame(height: persistentActionsHeight)
    }

    @ViewBuilder private func errorActions(for message: String) -> some View {
        if message == ConversionError.upgradeRequired.errorDescription {
            Button {
                NotificationCenter.default.post(name: .showPaywall, object: nil)
            } label: {
                Image(systemName: "arrow.up.forward.circle").font(.system(size: 9))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Upgrade to Pro")
        } else if message == ConversionError.modelUnavailable.errorDescription
                    || message == ConversionError.downloadFailed.errorDescription {
            Button {
                PreferencesWindowController.shared.show()
            } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 9))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help(message == ConversionError.modelUnavailable.errorDescription
                  ? "Download model in Settings"
                  : "Retry download in Settings")
        } else {
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise").font(.system(size: 9))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Retry")
        }
    }

    // Cancel (and Retry when stalled) overlay shown on hover while the job is running.
    private var runningHoverActions: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Button(action: onCancel) {
                Image(systemName: "stop.fill").font(.system(size: 7))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Cancel")

            if isStalled {
                Button {
                    onCancel()
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 7))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Cancel and retry")
            }
        }
    }

    // MARK: - Status text with crossfade

    @ViewBuilder private var statusText: some View {
        Group {
            if isStalled {
                Text("No progress")
                    .foregroundStyle(.yellow)
                    .help("No progress detected — conversion may be stalled. Cancel and retry if this persists.")
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
        .font(windowSize.fontCaption)
        .lineLimit(1)
        .frame(width: 56, height: 10)
        // Stage label crossfades on every stage change
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: item.stage)
    }

    // MARK: - Interactions

    private func handleSingleClick() {
        onSelect()
    }

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
        case .analysing:      return "Analysing"
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
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.95 : 0.78))
            .padding(AppTheme.Spacing.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.12), lineWidth: 0.5)
            )
    }
}
