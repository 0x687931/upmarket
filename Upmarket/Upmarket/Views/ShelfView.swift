import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ShelfView: View {

    @EnvironmentObject private var conversion: ConversionService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false
    @State private var queue: [QueueItem] = []
    @State private var showPaywall = false
    @State private var isCollapsed = false
    @State private var showControls = false  // traffic-light controls on hover

    // Item sizing
    private let itemWidth: CGFloat  = 64
    private let itemSpacing: CGFloat = 8
    private let shelfHeight: CGFloat = 68
    private let collapsedWidth: CGFloat = 120  // +  |logo|  >
    private let maxVisibleItems = 5

    private var isAnyConverting: Bool {
        queue.contains { $0.state == .converting }
    }

    // Dynamic width: expands to fit items up to maxVisible, collapses when toggled
    private var currentWidth: CGFloat {
        if isCollapsed { return collapsedWidth }
        let itemCount = min(queue.count, maxVisibleItems)
        let itemsWidth: CGFloat = itemCount > 0
            ? CGFloat(itemCount) * (itemWidth + itemSpacing) + 16
            : 220
        let chrome: CGFloat = 40 + 1 + 1 + 60 + 8
        return max(220, min(700, itemsWidth + chrome))
    }

    var body: some View {
        ZStack {
            // 1. Liquid glass background
            LiquidGlassBackground(cornerRadius: 12)

            // 2. Drop highlight ring
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }

            // 3. Main shelf content row
            HStack(spacing: 0) {
                addButton
                thinDivider
                mainContent
                thinDivider
                collapseButton
                resizeHandle
            }

            // 4. Traffic-light controls — overlay inside shelf, top-left
            // Only visible on hover
            if showControls {
                HStack(spacing: 5) {
                    // Red: hide shelf
                    trafficButton(color: .systemRed) {
                        ShelfWindowController.shared.hide()
                    }
                }
                .padding(.leading, 8)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
        }
        .frame(width: currentWidth, height: shelfHeight)
        .animation(.spring(duration: 0.3), value: isCollapsed)
        .animation(.spring(duration: 0.25), value: queue.count)
        .onHover { showControls = $0 }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketConvertFile)) { note in
            if let url = note.object as? URL { addToQueue(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .upmarketReprocessItem)) { note in
            guard let req = note.object as? ReprocessRequest else { return }
            if let idx = queue.firstIndex(where: { $0.id == req.itemID }) {
                queue[idx].state = .converting
                reprocessItem(queue[idx], useAI: req.useAI)
            }
        }
        // Resize window to match content width
        .onChange(of: currentWidth) { w in
            ShelfWindowController.shared.resizeToContent(width: w)
        }
        .onChange(of: isCollapsed) { _ in
            ShelfWindowController.shared.resizeToContent(width: currentWidth)
        }
    }

    // MARK: - Traffic light button

    private func trafficButton(color: NSColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add button (+)

    private var addButton: some View {
        Button { openFilePicker() } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.65))
                .frame(width: 38, height: shelfHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add files  (+)")
    }

    // MARK: - Main content area

    @ViewBuilder
    private var mainContent: some View {
        if isCollapsed {
            // Collapsed: drop target arrow (communicates function)
            if #available(macOS 14.0, *) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.12), value: isTargeted)
            } else {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.45))
                    .frame(maxWidth: .infinity)
            }
        } else if queue.isEmpty && isAnyConverting {
            conversionAnimation
        } else if queue.isEmpty {
            emptyDropZone
        } else {
            itemsArea
        }
    }

    // MARK: - Empty drop zone

    private var emptyDropZone: some View {
        HStack(spacing: 6) {
            if #available(macOS 14.0, *) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace.offUp))
            } else {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary.opacity(0.4))
            }
            Text(isTargeted ? "Release to convert" : "Drop documents here")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.12), value: isTargeted)
    }

    // MARK: - Conversion animation

    private var conversionAnimation: some View {
        HStack(spacing: 8) {
            ConversionIconView(isAnimating: isAnyConverting, size: 44)
            Text("Converting…")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Items area (springs open per item count)

    private var itemsArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: itemSpacing) {
                ForEach(queue.prefix(maxVisibleItems)) { item in
                    ShelfItemView(item: item) {
                        withAnimation(.spring(duration: 0.25)) {
                            queue.removeAll { $0.id == item.id }
                        }
                    }
                    .frame(width: itemWidth)
                }

                // Overflow badge — shows when >maxVisible items queued
                if queue.count > maxVisibleItems {
                    overflowBadge
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // Dockside-style stack badge for overflow
    private var overflowBadge: some View {
        let extra = queue.count - maxVisibleItems
        return ZStack {
            // Stacked cards effect
            ForEach(0..<min(3, extra), id: \.self) { i in
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .frame(width: 38, height: 44)
                    .offset(x: CGFloat(i) * 3, y: CGFloat(-i) * 2)
            }
            // Count badge
            Text("+\(extra)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 38, height: 44)
        }
        .frame(width: itemWidth)
        .help("\(extra) more document\(extra == 1 ? "" : "s") queued")
        .onTapGesture {
            // Show all items by expanding
            withAnimation { isCollapsed = false }
        }
    }

    // MARK: - Collapse/expand button (now an arrow)

    private var collapseButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: isCollapsed ? "arrow.right" : "arrow.left")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.5))
                .frame(width: 30, height: shelfHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Expand shelf" : "Collapse shelf")
    }

    // MARK: - Thin divider

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 32)
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5, height: shelfHeight)
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard !isCollapsed else { return }
                        let newW = currentWidth + value.translation.width
                        let clamped = max(220, min(700, newW))
                        ShelfWindowController.shared.resizeToContent(width: clamped)
                    }
            )
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { showPaywall = true; return false }
        // Spring open when files are dropped
        if isCollapsed {
            withAnimation(.spring(duration: 0.25)) { isCollapsed = false }
        }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { self.addToQueue(url) }
            }
        }
        return true
    }

    private func openFilePicker() {
        guard store.canConvert else { showPaywall = true; return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .pdf, .html, .png, .jpeg,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "epub") ?? .data,
            UTType(filenameExtension: "csv")  ?? .data,
            UTType(filenameExtension: "mp3")  ?? .data,
            UTType(filenameExtension: "m4a")  ?? .data,
        ]
        panel.orderFrontRegardless()
        if isCollapsed { withAnimation(.spring(duration: 0.25)) { isCollapsed = false } }
        if panel.runModal() == .OK { panel.urls.forEach { addToQueue($0) } }
    }

    private func addToQueue(_ url: URL) {
        guard !queue.contains(where: { $0.url == url }) else { return }
        let item = QueueItem(url: url)
        store.consumeConversion()
        withAnimation(.spring(duration: 0.3)) { queue.insert(item, at: 0) }
        NotificationCenter.default.post(name: .upmarketConversionStarted, object: nil)
        convertItem(item)
    }

    private func convertItem(_ item: QueueItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[idx].state = .converting

        Task.detached(priority: .userInitiated) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(item.url.pathExtension)
            try? FileManager.default.copyItem(at: item.url, to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            await ConversionService.shared.convert(fileURL: tempURL)
            while await ConversionService.shared.isConverting {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            await MainActor.run {
                guard let idx = self.queue.firstIndex(where: { $0.id == item.id }) else { return }
                switch ConversionService.shared.result {
                case .success(let output):
                    self.queue[idx].state = .done(output.markdown, output.title)
                case .failure(let error):
                    self.queue[idx].state = .failed(error)
                case .none:
                    self.queue[idx].state = .failed("Conversion failed")
                }
                if !self.queue.contains(where: { $0.state == .converting }) {
                    NotificationCenter.default.post(name: .upmarketConversionEnded, object: nil)
                }
            }
        }
    }

    private func reprocessItem(_ item: QueueItem, useAI: Bool) {
        Task.detached(priority: .userInitiated) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(item.url.pathExtension)
            try? FileManager.default.copyItem(at: item.url, to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            await ConversionService.shared.convert(fileURL: tempURL, useAI: useAI)
            while await ConversionService.shared.isConverting {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await MainActor.run {
                guard let idx = self.queue.firstIndex(where: { $0.id == item.id }) else { return }
                switch ConversionService.shared.result {
                case .success(let output):
                    self.queue[idx].state = .done(output.markdown, output.title)
                case .failure(let error):
                    self.queue[idx].state = .failed(error)
                case .none:
                    self.queue[idx].state = .failed("Conversion failed")
                }
                if !self.queue.contains(where: { $0.state == .converting }) {
                    NotificationCenter.default.post(name: .upmarketConversionEnded, object: nil)
                }
            }
        }
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
    let item: QueueItem
    let onRemove: () -> Void

    @State private var showActions = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 3) {
                ZStack(alignment: .bottomTrailing) {
                    fileIcon.frame(width: 36, height: 36)
                    stateIndicator
                }
                Text(item.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 56)
            }
            .padding(.vertical, 6)

            if showActions {
                hoverActions
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .contentShape(Rectangle())
        .onHover { showActions = $0 }
        .onTapGesture(count: 2) { handleDoubleClick() }
        .onTapGesture(count: 1) { handleSingleClick() }
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var fileIcon: some View {
        if FileManager.default.fileExists(atPath: item.url.path),
           let icon = NSWorkspace.shared.icon(forFile: item.url.path) as NSImage? {
            Image(nsImage: icon).resizable().interpolation(.high).antialiased(true)
        } else {
            Image(systemName: extensionIcon)
                .font(.system(size: 24))
                .foregroundStyle(.primary.opacity(0.6))
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch item.state {
        case .pending:
            EmptyView()
        case .converting:
            if #available(macOS 15.0, *) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Color.accentColor, in: Circle())
                    .symbolEffect(.rotate, isActive: true)
            } else {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
            }
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.green)
                .background(Color.black.opacity(0.4), in: Circle())
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.red)
                .background(Color.black.opacity(0.4), in: Circle())
        }
    }

    @ViewBuilder
    private var hoverActions: some View {
        HStack(spacing: 3) {
            if case .done(let markdown, _) = item.state {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 9))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Copy Markdown")
            }
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Remove")
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if case .done(let markdown, let title) = item.state {
            Button("Open in Markdown Editor") { openInDefaultApp(markdown, title: title) }
            Divider()
            Button("Copy Markdown") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            }
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Save As…") { saveMarkdown(markdown, title: title) }
            Divider()
            Menu("Reprocess") {
                Button("Fast (instant)") { reprocess(useAI: false) }
                Button("Upmarket AI (best)") { reprocess(useAI: true) }
            }
            Divider()
        }
        Button("Show Original in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
        Divider()
        Button("Remove from Shelf", role: .destructive) { onRemove() }
    }

    private func handleSingleClick() {
        if case .done(let markdown, _) = item.state {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)
        }
    }

    private func handleDoubleClick() {
        if case .done(let markdown, let title) = item.state {
            openInDefaultApp(markdown, title: title)
        }
    }

    private func openInDefaultApp(_ markdown: String, title: String) {
        Task { @MainActor in
            let savedURL = SavePreference.shared.save(markdown: markdown, title: title, sourceURL: item.url)
            if let url = savedURL { NSWorkspace.shared.open(url) }
        }
    }

    private func saveMarkdown(_ markdown: String, title: String) {
        Task {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = (title.isEmpty ? "converted" : title) + ".md"
            await MainActor.run {
                panel.orderFrontRegardless()
                if panel.runModal() == .OK, let url = panel.url {
                    try? markdown.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    private func reprocess(useAI: Bool) {
        NotificationCenter.default.post(
            name: .upmarketReprocessItem,
            object: ReprocessRequest(url: item.url, itemID: item.id, useAI: useAI, enhanced: useAI)
        )
    }

    private var extensionIcon: String {
        switch item.url.pathExtension.lowercased() {
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
}

struct ShelfActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(4)
            .background(Color.black.opacity(configuration.isPressed ? 0.85 : 0.65), in: Circle())
    }
}

// MARK: - Queue Item Model

struct QueueItem: Identifiable {
    let id = UUID()
    let url: URL
    var state: State = .pending

    var name: String { url.deletingPathExtension().lastPathComponent }
    var ext: String  { url.pathExtension.uppercased() }

    enum State: Equatable {
        case pending
        case converting
        case done(String, String)
        case failed(String)
    }
}
