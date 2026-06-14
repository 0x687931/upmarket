import SwiftUI
import UniformTypeIdentifiers
import AppKit
import OSLog

// MARK: - Layout Constants

enum ShelfLayout {
    static let miniSize = CGSize(width: 56, height: 56)
    static let controlStripWidth: CGFloat = 48
    static let peekPanelWidth: CGFloat = 168
    static let expandedPanelWidth: CGFloat = 420
    static let closedHeight: CGFloat = 132
    static var closedWidth: CGFloat { controlStripWidth + 1 + peekPanelWidth }
    static var closedSize: CGSize { CGSize(width: closedWidth, height: closedHeight) }
    static let cardGap: CGFloat = 10
    static let panelHorizontalPadding: CGFloat = 14
    static let maxVisible = 5

    // Control strip button dimensions
    static let stripButtonDiameter: CGFloat = 26
    static let stripButtonSpacing: CGFloat = 14
    static let stripButtonIconSize: CGFloat = 11

    // Peek row
    static let peekArcRingSize: CGFloat = 42
    static let peekArcRingStroke: CGFloat = 2.5
    static let peekFileIconSize: CGFloat = 16

    // Card dimensions
    static let activeCardWidth: CGFloat = 96
    static let passiveCardWidth: CGFloat = 72
    static let cardHeight: CGFloat = 104
    // Concentric corner scale, all `.continuous` to match the app-wide design system:
    // panel (outer) > card (inner) > action button. See AppTheme.Radius.
    static let panelCornerRadius: CGFloat = AppTheme.Radius.md   // 12 — outer shelf container
    static let cardCornerRadius: CGFloat = AppTheme.Radius.sm    // 8 — nested file cards
    static let cardPaddingVertical: CGFloat = 10
    static let cardPaddingHorizontal: CGFloat = 8

    // Arc ring in card
    static let cardArcRingSize: CGFloat = 40
    static let cardArcRingStroke: CGFloat = 3
    static let cardFileIconSize: CGFloat = 16

    // Status badge
    static let statusBadgeDiameter: CGFloat = 15
    static let statusBadgeIconSize: CGFloat = 7

    // Action buttons
    static let actionButtonSize: CGFloat = 18
    static let actionButtonIconSize: CGFloat = 9
    static let actionButtonCornerRadius: CGFloat = AppTheme.Radius.xs  // 4 — innermost controls

    // Overflow stack
    static let overflowCardWidth: CGFloat = 56
    static let overflowStackHeight: CGFloat = 104
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
    @State private var displayMode: ShelfDisplayMode = .mini
    @State private var layoutAnchor: ShelfWindowController.ShelfAnchor = .bottomRight

    private var hasQueueItems: Bool { !conversion.jobs.isEmpty }

    private var isConverting: Bool { conversion.isConverting }

    private var effectiveMode: ShelfDisplayMode {
        if displayMode == .queue, hasQueueItems { return .queue }
        if isTargeted { return .peek }
        switch displayMode {
        case .mini:  return .mini
        case .peek:  return .peek
        case .queue: return hasQueueItems ? .queue : .mini
        }
    }

    private var totalWidth: CGFloat {
        switch effectiveMode {
        case .mini:
            return ShelfLayout.miniSize.width
        case .peek:
            return ShelfLayout.controlStripWidth + 1 + ShelfLayout.peekPanelWidth
        case .queue:
            return ShelfLayout.controlStripWidth + 1 + ShelfLayout.expandedPanelWidth
        }
    }

    private var totalHeight: CGFloat {
        effectiveMode == .mini ? ShelfLayout.miniSize.height : ShelfLayout.closedHeight
    }

    private var currentSize: CGSize {
        CGSize(width: totalWidth, height: totalHeight)
    }

    @ViewBuilder
    private var contentPanel: some View {
        if effectiveMode == .queue {
            ExpandedQueue(jobs: conversion.jobs)
                .frame(width: ShelfLayout.expandedPanelWidth, height: ShelfLayout.closedHeight)
        } else if conversion.jobs.isEmpty {
            IdleState()
                .frame(width: ShelfLayout.peekPanelWidth, height: ShelfLayout.closedHeight)
        } else {
            PeekRow(job: frontJob, totalCount: conversion.jobs.count)
                .frame(width: ShelfLayout.peekPanelWidth, height: ShelfLayout.closedHeight)
        }
    }

    private var frontJob: ConversionJob {
        conversion.jobs.first(where: \.isRunning) ?? conversion.jobs.last ?? conversion.jobs[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            if effectiveMode == .mini {
                miniShelf
                    .transition(.scale(scale: 0.86).combined(with: .opacity))

            } else if layoutAnchor == .bottomRight || layoutAnchor == .topRight {
                // Right-anchored: content grows LEFT, control strip on RIGHT
                contentPanel
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Rectangle()
                    .fill(AppTheme.Colour.separator)
                    .frame(width: 0.5, height: ShelfLayout.closedHeight)

                ControlStrip(
                    onHide: { ShelfWindowController.shared.hide() },
                    onAdd: { openFilePicker() },
                    onToggle: { toggleQueue() },
                    expanded: displayMode == .queue
                )

            } else {
                // Left-anchored: control strip on LEFT, content grows RIGHT
                ControlStrip(
                    onHide: { ShelfWindowController.shared.hide() },
                    onAdd: { openFilePicker() },
                    onToggle: { toggleQueue() },
                    expanded: displayMode == .queue
                )

                Rectangle()
                    .fill(AppTheme.Colour.separator)
                    .frame(width: 0.5, height: ShelfLayout.closedHeight)

                contentPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: totalWidth, height: totalHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ShelfLayout.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShelfLayout.panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(
            color: isConverting ? AppTheme.Colour.amberShadow.opacity(0.35) : .black.opacity(0.18),
            radius: isConverting ? 24 : 12,
            y: 4
        )
        .animation(.easeOut(duration: 0.28), value: effectiveMode)
        .animation(.spring(duration: 0.25), value: conversion.jobs.count)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .onAppear {
            DispatchQueue.main.async {
                layoutAnchor = ShelfWindowController.shared.anchor
            }
            resizeShelfWindow()
        }
        .onChange(of: currentSize) { _ in
            resizeShelfWindow()
        }
        .onChange(of: conversion.jobs.count) { count in
            if count == 0 {
                withAnimation(.spring(duration: 0.25)) {
                    displayMode = .mini
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketShelfAnchorChanged)) { notification in
            if let rawValue = notification.object as? Int,
               let newAnchor = ShelfWindowController.ShelfAnchor(rawValue: rawValue) {
                withAnimation(.easeOut(duration: 0.25)) {
                    layoutAnchor = newAnchor
                }
            }
        }
    }

    private var miniShelf: some View {
        ZStack(alignment: .topTrailing) {
            miniSymbol

            if hasQueueItems {
                Text("\(min(conversion.jobs.count, 99))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .offset(x: 4, y: -4)
            }
        }
        .frame(width: 56, height: 56)
        .contentShape(RoundedRectangle(cornerRadius: ShelfLayout.panelCornerRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                displayMode = hasQueueItems ? .queue : .peek
            }
        }
        .transition(.scale(scale: 0.86).combined(with: .opacity))
    }

    @ViewBuilder
    private var miniSymbol: some View {
        if let activeJob = conversion.jobs.first(where: \.isRunning) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                    .frame(width: 34, height: 34)
                Circle()
                    .trim(from: 0, to: activeJob.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.62))
            }
        } else if hasQueueItems {
            Image(systemName: "tray.full")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary.opacity(0.62))
                .symbolRenderingMode(.hierarchical)
        } else {
            Image(nsImage: NSImage(named: "MenuBarHash") ?? NSImage())
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(.primary.opacity(0.62))
        }
    }

    private func resizeShelfWindow() {
        DispatchQueue.main.async {
            ShelfWindowController.shared.resizeToContent(width: currentSize.width, height: currentSize.height)
        }
    }

    private func toggleQueue() {
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            displayMode = displayMode == .queue ? .peek : .queue
        }
    }

    private func openFilePicker() {
        guard store.canConvert else { PaywallWindowController.shared.show(); return }
        FileAccessService.shared
            .chooseDocuments(allowsMultipleSelection: true, positioningNear: ShelfWindowController.shared.window)
            .forEach { addToQueue($0) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { PaywallWindowController.shared.show(); return false }
        FileAccessService.shared.loadFileURLs(from: providers) { url in
            self.addToQueue(url)
        }
        return true
    }

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
        _ = conversion.add(url)
    }

    private func cleanupQuickActionHandoffIfDone(_ directory: URL) {
        let stillNeeded = conversion.jobs.contains { job in
            job.isRunning && job.sourceURL.deletingLastPathComponent() == directory
        }
        guard !stillNeeded else { return }
        try? FileManager.default.removeItem(at: directory)
    }


}

// MARK: - Control Strip (48pt wide, 3 traffic-light buttons)

struct ControlStrip: View {
    let onHide: () -> Void
    let onAdd: () -> Void
    let onToggle: () -> Void
    let expanded: Bool

    var body: some View {
        VStack(spacing: ShelfLayout.stripButtonSpacing) {
            StripButton(
                color: AppTheme.Colour.trafficRed,
                icon: "xmark",
                action: onHide,
                tooltip: "Hide shelf"
            )

            StripButton(
                color: AppTheme.Colour.trafficGreen,
                icon: "plus",
                action: onAdd,
                tooltip: "Add files"
            )

            StripButton(
                color: AppTheme.Colour.iconGlyphTint,
                icon: expanded ? "chevron.left" : "chevron.right",
                action: onToggle,
                tooltip: expanded ? "Collapse" : "Show queue"
            )
        }
        .frame(width: ShelfLayout.controlStripWidth)
        .background(Color.white.opacity(0.25))
    }
}

struct StripButton: View {
    let color: Color
    let icon: String
    let action: () -> Void
    let tooltip: String
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(hovered ? color : Color.clear)
                    .frame(width: ShelfLayout.stripButtonDiameter, height: ShelfLayout.stripButtonDiameter)
                Image(systemName: icon)
                    .font(.system(size: ShelfLayout.stripButtonIconSize, weight: .bold))
                    .foregroundStyle(hovered ? .white : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovered = $0 }
    }
}

// MARK: - Panel (Peek or Expanded)

fileprivate struct Panel: View {
    @Binding var displayMode: ShelfDisplayMode
    let jobs: [ConversionJob]

    var body: some View {
        ZStack {
            if jobs.isEmpty {
                IdleState()
            } else if displayMode == .peek {
                PeekRow(job: frontJob, totalCount: jobs.count)
            } else {
                ExpandedQueue(jobs: jobs)
            }
        }
        .frame(width: displayMode == .queue ? ShelfLayout.expandedPanelWidth : ShelfLayout.peekPanelWidth)
    }

    private var frontJob: ConversionJob {
        jobs.first(where: \.isRunning) ?? jobs.last ?? jobs[0]
    }
}

// MARK: - Peek Row (168pt wide, single job summary)

struct PeekRow: View {
    let job: ConversionJob
    let totalCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if job.isRunning {
                    ArcProgressRing(progress: job.progress)
                        .stroke(Color.accentColor, lineWidth: ShelfLayout.peekArcRingStroke)
                        .frame(width: ShelfLayout.peekArcRingSize, height: ShelfLayout.peekArcRingSize)
                } else {
                    Circle()
                        .stroke(statusColor(job), lineWidth: ShelfLayout.peekArcRingStroke)
                        .frame(width: ShelfLayout.peekArcRingSize, height: ShelfLayout.peekArcRingSize)
                }
                Image(systemName: job.fileTypeIcon)
                    .font(.system(size: ShelfLayout.peekFileIconSize))
                    .foregroundStyle(AppTheme.Colour.iconGlyphTint)
            }
            .overlay(alignment: .bottomTrailing) {
                if totalCount > 1 {
                    Text("\(totalCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.Colour.separator, lineWidth: 0.5))
                        .offset(x: 8, y: 8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(job.filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 96, alignment: .leading)
                Text(job.stageLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(job.stage == .failed ? AppTheme.Status.failed : .secondary)
            }
        }
        .padding(.horizontal, ShelfLayout.panelHorizontalPadding)
    }

    private func statusColor(_ job: ConversionJob) -> Color {
        switch job.stage {
        case .complete:
            return AppTheme.Status.complete
        case .failed:
            return AppTheme.Status.failed
        case .cancelled:
            return .secondary
        default:
            return .accentColor
        }
    }
}

// MARK: - Expanded Queue (420pt wide, horizontal scroll of cards)

struct ExpandedQueue: View {
    let jobs: [ConversionJob]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ShelfLayout.cardGap) {
                let visible = Array(jobs.prefix(ShelfLayout.maxVisible))
                let overflow = max(0, jobs.count - visible.count)

                ForEach(visible) { job in
                    ShelfCard(job: job)
                }

                if overflow > 0 {
                    OverflowStack(count: overflow)
                }

                // ClearDoneButton placeholder for now
            }
            .padding(.horizontal, ShelfLayout.panelHorizontalPadding)
        }
        .frame(width: ShelfLayout.expandedPanelWidth)
    }
}

// MARK: - Shelf Card (Active: 96pt, Passive: 72pt)

struct ShelfCard: View {
    let job: ConversionJob
    @EnvironmentObject private var conversion: ConversionQueue

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Spacer()

            ZStack {
                ArcProgressRing(progress: job.isRunning ? job.progress : 1.0)
                    .stroke(ringColor(), lineWidth: ShelfLayout.cardArcRingStroke)
                    .frame(width: ShelfLayout.cardArcRingSize, height: ShelfLayout.cardArcRingSize)
                Image(systemName: job.fileTypeIcon)
                    .font(.system(size: ShelfLayout.cardFileIconSize))
                    .foregroundStyle(AppTheme.Colour.iconGlyphTint)
            }
            .overlay(alignment: .bottomTrailing) {
                if job.stage == .complete {
                    StatusBadge(color: AppTheme.Status.complete, icon: "checkmark")
                } else if job.stage == .failed {
                    StatusBadge(color: AppTheme.Status.failed, icon: "xmark")
                }
            }

            Spacer().frame(height: 8)

            Text(job.filename)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)

            Spacer()

            HStack(spacing: 3) {
                switch job.stage {
                case .complete:
                    ShelfActionButton(icon: "doc.on.doc", label: "Copy", action: { copyOutput(job) })
                    ShelfActionButton(icon: "arrow.up.right.square", label: "Open", action: { openOutput(job) })
                    ShelfActionButton(icon: "xmark", label: "Remove", action: { conversion.remove(job.id) }, danger: true)
                case .failed, .cancelled:
                    ShelfActionButton(icon: "arrow.clockwise", label: "Retry", action: { _ = conversion.retry(job.id) })
                    ShelfActionButton(icon: "xmark", label: "Remove", action: { conversion.remove(job.id) }, danger: true)
                default:
                    ShelfActionButton(icon: "stop.fill", label: "Cancel", action: { conversion.cancel(job.id) }, danger: true)
                }
            }
        }
        .padding(.vertical, ShelfLayout.cardPaddingVertical)
        .padding(.horizontal, ShelfLayout.cardPaddingHorizontal)
        .frame(width: job.isRunning ? ShelfLayout.activeCardWidth : ShelfLayout.passiveCardWidth, height: ShelfLayout.cardHeight)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: ShelfLayout.cardCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ShelfLayout.cardCornerRadius, style: .continuous).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: job.isRunning)
    }

    private func ringColor() -> Color {
        switch job.stage {
        case .failed:
            return AppTheme.Status.failed
        case .complete:
            return AppTheme.Status.complete
        case .cancelled:
            return .secondary
        default:
            return .accentColor
        }
    }

    private func copyOutput(_ job: ConversionJob) {
        if let output = job.result?.output {
            FileAccessService.shared.copyMarkdown(formattedOutput(output).text)
        }
    }

    private func openOutput(_ job: ConversionJob) {
        if let output = job.result?.output {
            let formatted = formattedOutput(output)
            Task { @MainActor in
                let savedURL = await SavePreference.shared.save(
                    markdown: formatted.text,
                    title: job.sourceURL.deletingPathExtension().lastPathComponent,
                    sourceURL: job.sourceURL,
                    fileExtension: formatted.fileExtension
                )
                if let url = savedURL {
                    FileAccessService.shared.open(url)
                }
            }
        }
    }

    private func formattedOutput(_ output: ConversionOutput) -> FormattedConversionOutput {
        OutputFormatter.format(
            output,
            sourceDisplayName: job.sourceURL.lastPathComponent,
            mode: OutputPreference.shared.mode
        )
    }
}

// MARK: - Status Badge (15pt circle with icon, bottom-right of ring)

struct StatusBadge: View {
    let color: Color
    let icon: String

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: ShelfLayout.statusBadgeDiameter, height: ShelfLayout.statusBadgeDiameter)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            Image(systemName: icon)
                .font(.system(size: ShelfLayout.statusBadgeIconSize, weight: .bold))
                .foregroundStyle(.white)
        }
        .offset(x: 3, y: 3)
    }
}

// MARK: - Shelf Action Button (tiny icon buttons in card footer)

struct ShelfActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var danger: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: ShelfLayout.actionButtonIconSize))
                .foregroundStyle(danger ? AppTheme.Status.failed : .secondary)
                .frame(width: ShelfLayout.actionButtonSize, height: ShelfLayout.actionButtonSize)
                .background(Color.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: ShelfLayout.actionButtonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Overflow Stack (+N more)

struct OverflowStack: View {
    let count: Int

    var body: some View {
        ZStack {
            ForEach(0..<min(3, count), id: \.self) { i in
                RoundedRectangle(cornerRadius: ShelfLayout.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 38, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: ShelfLayout.cardCornerRadius, style: .continuous).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
                    .offset(x: CGFloat(i) * 3, y: CGFloat(-i) * 2)
            }
            Text("+\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: ShelfLayout.overflowCardWidth, height: ShelfLayout.overflowStackHeight)
    }
}

// MARK: - Idle State (no jobs)

struct IdleState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("Drop documents here")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
