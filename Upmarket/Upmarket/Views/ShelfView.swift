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

    // Persisted width — user can resize
    @AppStorage("upmarket.shelfWidth") private var shelfWidth: Double = 480

    private let shelfHeight: CGFloat = 68
    private let minWidth: CGFloat = 200
    private let maxWidth: CGFloat = 900

    var body: some View {
        ZStack(alignment: .topLeading) {
            shelfBackground

            HStack(spacing: 0) {
                addButton
                divider

                if isCollapsed {
                    collapsedLabel
                } else if queue.isEmpty {
                    emptyDropZone
                } else {
                    itemsArea
                }

                divider
                rightButtons
                resizeHandle
            }
        }
        // Close button — top-left, appears on hover like macOS traffic lights
        closeButton

        .frame(width: CGFloat(shelfWidth), height: shelfHeight)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .overlay(dropHighlight)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        // Handle files from Quick Action extension and Services menu
        .onReceive(NotificationCenter.default.publisher(for: .upmarketConvertFile)) { note in
            if let url = note.object as? URL { addToQueue(url) }
        }
        // Handle reprocess requests from context menu
        .onReceive(NotificationCenter.default.publisher(for: .upmarketReprocessItem)) { note in
            guard let req = note.object as? ReprocessRequest else { return }
            if let idx = queue.firstIndex(where: { $0.id == req.itemID }) {
                queue[idx].state = .converting
                reprocessItem(queue[idx], useAI: req.useAI)
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
            }
        }
    }

    private var closeButton: some View {
        Button {
            ShelfWindowController.shared.hide()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .systemRed))
                    .frame(width: 12, height: 12)
                Image(systemName: "xmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 5)
        .padding(.leading, 7)
        .help("Hide shelf  (show again from menu bar)")
    }

    // MARK: - Background — true liquid glass via NSVisualEffectView

    private var shelfBackground: some View {
        LiquidGlassBackground(cornerRadius: 12)
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 36)
    }

    // MARK: - Add Button (+)

    private var addButton: some View {
        Button {
            openFilePicker()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 40, height: shelfHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add files to convert  (+)")
    }

    // MARK: - Empty drop zone

    private var emptyDropZone: some View {
        HStack(spacing: 8) {
            if #available(macOS 14.0, *) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace.offUp))
            } else {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary.opacity(0.5))
            }
            Text(isTargeted ? "Release to convert" : "Drop documents here")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.5))
                .animation(.easeInOut(duration: 0.12), value: isTargeted)
        }
        .frame(maxWidth: .infinity)
    }

    private var collapsedLabel: some View {
        Text("Upmarket")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary.opacity(0.5))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Items area

    private var itemsArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(queue) { item in
                    ShelfItemView(item: item) {
                        withAnimation(.spring(duration: 0.25)) {
                            queue.removeAll { $0.id == item.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Right buttons

    private var rightButtons: some View {
        HStack(spacing: 2) {
            // Clear all (only when items present)
            if !queue.isEmpty && !isCollapsed {
                Button {
                    withAnimation(.spring(duration: 0.3)) { queue.removeAll() }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.6))
                        .frame(width: 28, height: shelfHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear all")
            }

            // Collapse / expand toggle — actually resizes the window
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    isCollapsed.toggle()
                    let newWidth: Double = isCollapsed ? 60 : shelfWidth
                    ShelfWindowController.shared.resizeToContent(width: CGFloat(newWidth))
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 30, height: shelfHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand shelf" : "Collapse shelf")
        }
    }

    // MARK: - Resize handle (right edge drag)

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6, height: shelfHeight)
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let newWidth = shelfWidth + value.translation.width
                        shelfWidth = max(Double(minWidth), min(Double(maxWidth), newWidth))
                        ShelfWindowController.shared.resizeToContent(width: CGFloat(shelfWidth))
                    }
            )
            .help("Drag to resize")
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { showPaywall = true; return false }
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
        // Open without activating the app — prevents Dock bounce
        panel.orderFrontRegardless()
        if panel.runModal() == .OK {
            panel.urls.forEach { addToQueue($0) }
        }
    }

    private func addToQueue(_ url: URL) {
        guard !queue.contains(where: { $0.url == url }) else { return }
        let item = QueueItem(url: url)
        store.consumeConversion()
        withAnimation(.spring(duration: 0.3)) {
            queue.insert(item, at: 0)
        }
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
            }
        }
    }
}

// MARK: - Resize cursor helper

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
                    fileIcon
                        .frame(width: 36, height: 36)
                    stateIndicator
                }

                Text(item.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 52)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)

            if showActions {
                hoverActions
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: 60)
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
            Image(nsImage: icon)
                .resizable().interpolation(.high).antialiased(true)
        } else {
            Image(systemName: extensionIcon)
                .font(.system(size: 26))
                .foregroundStyle(.primary.opacity(0.7))
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
                .font(.system(size: 11))
                .foregroundStyle(.green)
                .background(Color.black.opacity(0.5), in: Circle())
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .background(Color.black.opacity(0.5), in: Circle())
        }
    }

    @ViewBuilder
    private var hoverActions: some View {
        HStack(spacing: 3) {
            if case .done(let markdown, let title) = item.state {
                // Copy Markdown
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 9))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Copy Markdown")

                // Save as .md file
                Button {
                    saveMarkdown(markdown, title: title)
                } label: {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 9))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Save as .md")
            }

            // Remove
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Remove")
        }
        .padding(.bottom, 2)
    }

    // MARK: - Right-click context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        // Open actions
        if case .done(let markdown, let title) = item.state {
            Button("Open in Markdown Editor") {
                openInDefaultApp(markdown, title: title)
            }
            Divider()

            // Copy options
            Button("Copy Markdown") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            }
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }

            Divider()

            // Save
            Button("Save As…") {
                saveMarkdown(markdown, title: title)
            }

            Divider()

            // Reprocess
            Menu("Reprocess") {
                Button("Fast (instant)") {
                    reprocess(useAI: false, enhanced: false)
                }
                Button("Enhanced (better quality)") {
                    reprocess(useAI: false, enhanced: true)
                }
                Button("Upmarket AI (best)") {
                    reprocess(useAI: true, enhanced: true)
                }
            }

            Divider()
        } else if item.state == .pending || item.state == .converting {
            // Can still copy path while converting
            Button("Copy Source Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
        }

        // Show source in Finder
        Button("Show Original in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }

        Divider()

        // Remove
        Button("Remove from Shelf", role: .destructive) {
            onRemove()
        }
    }

    // MARK: - Reprocess

    private func reprocess(useAI: Bool, enhanced: Bool) {
        // Notify ShelfView to re-convert this item with different settings
        NotificationCenter.default.post(
            name: .upmarketReprocessItem,
            object: ReprocessRequest(url: item.url, itemID: item.id, useAI: useAI, enhanced: enhanced)
        )
    }

    // MARK: - Tap handlers

    private func handleSingleClick() {
        // Single click on done item — copy to clipboard
        if case .done(let markdown, _) = item.state {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)
            // Brief visual feedback could go here
        }
    }

    private func handleDoubleClick() {
        // Double click — open in default Markdown app or save + open
        if case .done(let markdown, let title) = item.state {
            openInDefaultApp(markdown, title: title)
        }
    }

    private func openInDefaultApp(_ markdown: String, title: String) {
        // Use SavePreference — respects user's chosen save location
        Task {
            let savedURL = await SavePreference.shared.save(
                markdown: markdown,
                title: title,
                sourceURL: item.url
            )
            if let url = savedURL {
                await MainActor.run {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func saveMarkdown(_ markdown: String, title: String) {
        // Explicit save — always show panel regardless of preference
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

    private var extensionIcon: String {
        switch item.url.pathExtension.lowercased() {
        case "pdf":               return "doc.richtext"
        case "docx", "doc":       return "doc.text"
        case "pptx", "ppt":       return "rectangle.on.rectangle"
        case "xlsx", "xls":       return "tablecells"
        case "html", "htm":       return "globe"
        case "mp3", "m4a", "wav": return "waveform"
        case "png", "jpg", "jpeg":return "photo"
        default:                  return "doc"
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
        case done(String, String)   // markdown, title
        case failed(String)
    }
}
