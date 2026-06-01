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
    @State private var isExpanded = false

    // Hover states per button
    @State private var hoverClose  = false
    @State private var hoverAdd    = false
    @State private var hoverToggle = false
    @State private var hoverDrop   = false

    // Closed state: two-column panel
    // Left col: 3 buttons stacked [X][+][>]  |  Right col: [↓] drop arrow
    private let colWidth:     CGFloat = 48   // wider columns for proper padding
    private let closedHeight: CGFloat = 108  // 3 × 36pt buttons — room to breathe
    private let itemWidth:    CGFloat = 64
    private let itemSpacing:  CGFloat = 8
    private let maxVisible:   Int     = 5

    private var buttonHeight: CGFloat { closedHeight / 3 }  // 36pt each

    private var isAnyConverting: Bool {
        queue.contains { $0.state == .converting }
    }

    // Width: closed = stripWidth, open = strip + items
    private var closedWidth: CGFloat { colWidth * 2 + 1 }  // two cols + divider

    private var totalWidth: CGFloat {
        guard isExpanded else { return closedWidth }
        let count = min(queue.count, maxVisible)
        let content: CGFloat = count > 0
            ? CGFloat(count) * (itemWidth + itemSpacing) + itemSpacing
            : 200
        let overflow: CGFloat = queue.count > maxVisible ? itemWidth + itemSpacing : 0
        return closedWidth + 8 + content + overflow
    }

    var body: some View {
        HStack(spacing: 0) {
            // Closed state: [X][+][>] | [↓]
            closedPanel

            // Expanded content slides out to the right
            if isExpanded {
                expandedContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: totalWidth, height: closedHeight)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: isExpanded)
        .animation(.spring(duration: 0.25), value: queue.count)
        .background(LiquidGlassBackground(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(isTargeted ? 0.8 : 0), lineWidth: 2)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        )
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

    // MARK: - Closed panel: [X][+][>] | [↓]

    private var closedPanel: some View {
        HStack(spacing: 0) {
            // Left column: 3 stacked buttons
            VStack(spacing: 0) {
                controlButton(symbol: "xmark",  hoverColor: .red,                          isHovered: hoverClose,  help: "Hide shelf") { ShelfWindowController.shared.hide() }
                    .onHover { hoverClose = $0 }
                controlButton(symbol: "plus",   hoverColor: .green,                        isHovered: hoverAdd,    help: "Add files")  { openFilePicker() }
                    .onHover { hoverAdd = $0 }
                controlButton(symbol: isExpanded ? "arrow.left" : "arrow.right",
                              hoverColor: Color(nsColor: .systemBlue),                     isHovered: hoverToggle, help: isExpanded ? "Collapse" : "Expand") {
                    withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isExpanded.toggle() }
                }
                .onHover { hoverToggle = $0 }
            }
            .frame(width: colWidth, height: closedHeight)

            // Thin divider between columns
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: closedHeight * 0.6)

            // Right column: drop arrow centred
            dropArrowButton
                .onHover { hoverDrop = $0 }
                .frame(width: colWidth, height: closedHeight)
        }
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
                // Circle grows to fill available space minus 10pt padding each side
                Circle()
                    .fill(hoverColor.opacity(isHovered ? 0.18 : 0))
                    .frame(width: buttonHeight - 10, height: buttonHeight - 10)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? hoverColor : .primary.opacity(0.45))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: colWidth, height: buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var dropArrowButton: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(isTargeted || hoverDrop ? 0.18 : 0))
                .frame(width: buttonHeight - 10, height: buttonHeight - 10)
            if #available(macOS 14.0, *) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isTargeted || hoverDrop ? Color.accentColor : .primary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace.offUp))
            } else {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isTargeted || hoverDrop ? Color.accentColor : .primary.opacity(0.4))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isTargeted)
        .animation(.easeInOut(duration: 0.12), value: hoverDrop)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 10)

            if queue.isEmpty && isAnyConverting {
                conversionView
            } else if queue.isEmpty {
                emptyView
            } else {
                itemsView
            }
        }
    }

    private var emptyView: some View {
        HStack(spacing: 12) {
            if #available(macOS 14.0, *) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.25))
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .animation(.easeInOut(duration: 0.12), value: isTargeted)
            } else {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(isTargeted ? Color.accentColor : .primary.opacity(0.25))
            }
            Text(isTargeted ? "Release to convert" : "Drop documents here")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.35))
        }
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
                ForEach(queue.prefix(maxVisible)) { item in
                    ShelfItemView(item: item) {
                        withAnimation(.spring(duration: 0.25)) {
                            queue.removeAll { $0.id == item.id }
                        }
                    }
                    .frame(width: itemWidth)
                }
                if queue.count > maxVisible {
                    overflowBadge
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var overflowBadge: some View {
        let extra = queue.count - maxVisible
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
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { self.addToQueue(url) }
            }
        }
        return true
    }

    // MARK: - Queue management

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
                if self.store.shouldShowTrialPaywallAfterConversion() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        NotificationCenter.default.post(name: .showPaywall, object: nil)
                    }
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
                case .success(let output): self.queue[idx].state = .done(output.markdown, output.title)
                case .failure(let error):  self.queue[idx].state = .failed(error)
                case .none:                self.queue[idx].state = .failed("Conversion failed")
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

    @ViewBuilder private var fileIcon: some View {
        if FileManager.default.fileExists(atPath: item.url.path),
           let icon = NSWorkspace.shared.icon(forFile: item.url.path) as NSImage? {
            Image(nsImage: icon).resizable().interpolation(.high).antialiased(true)
        } else {
            Image(systemName: extensionIcon)
                .font(.system(size: 24)).foregroundStyle(.primary.opacity(0.6))
        }
    }

    @ViewBuilder private var stateIndicator: some View {
        switch item.state {
        case .pending: EmptyView()
        case .converting:
            if #available(macOS 15.0, *) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(2).background(Color.accentColor, in: Circle())
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

    @ViewBuilder private var hoverActions: some View {
        HStack(spacing: 3) {
            if case .done(let markdown, _) = item.state {
                Button {
                    FileAccessService.shared.copyMarkdown(markdown)
                } label: { Image(systemName: "doc.on.doc").font(.system(size: 9)) }
                .buttonStyle(ShelfActionButtonStyle()).help("Copy Markdown")
            }
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(ShelfActionButtonStyle()).help("Remove")
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder private var contextMenuItems: some View {
        if case .done(let markdown, let title) = item.state {
            Button("Open in Markdown Editor") { openInDefaultApp(markdown, title: title) }
            Divider()
            Button("Copy Markdown") {
                FileAccessService.shared.copyMarkdown(markdown)
            }
            Button("Copy File Path") {
                FileAccessService.shared.copyFilePath(item.url)
            }
            Divider()
            Button("Save As…") { saveMarkdown(markdown, title: title) }
            Divider()
            Menu("Reprocess") {
                Button("Fast (instant)")       { reprocess(useAI: false) }
                Button("Upmarket AI (best)")   { reprocess(useAI: true)  }
            }
            Divider()
        }
        Button("Show Original in Finder") {
            FileAccessService.shared.revealInFinder(item.url)
        }
        Divider()
        Button("Remove from Shelf", role: .destructive) { onRemove() }
    }

    private func handleSingleClick() {
        if case .done(let markdown, _) = item.state {
            FileAccessService.shared.copyMarkdown(markdown)
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
