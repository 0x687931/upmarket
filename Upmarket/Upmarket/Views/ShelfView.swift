import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// The conversion queue shelf.
/// Sits to the left of the Dock, flush with the bottom of the screen.
/// Matches Dockside's visual style: dark translucent strip, file icons with labels,
/// action buttons at each end, expands on hover.
struct ShelfView: View {

    @EnvironmentObject private var conversion: ConversionService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false
    @State private var queue: [QueueItem] = []
    @State private var showPaywall = false
    @State private var isExpanded = false

    // Matches Dockside: shelf height tracks content
    private let itemSize: CGFloat = 52
    private let padding: CGFloat = 8

    var body: some View {
        ZStack {
            // Background — dark translucent material matching Dockside
            shelfBackground

            HStack(spacing: 0) {
                // Left button — add file (Dockside's + button)
                leftButton

                Divider()
                    .frame(height: 32)
                    .opacity(0.3)

                // File items area
                if queue.isEmpty {
                    emptyDropZone
                } else {
                    itemsArea
                }

                Divider()
                    .frame(height: 32)
                    .opacity(0.3)

                // Right buttons — expand and refresh (Dockside's > and ↺)
                rightButtons
            }
            .padding(.horizontal, padding)
        }
        .frame(height: 68)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        // Highlight on drag target
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        )
    }

    // MARK: - Background

    private var shelfBackground: some View {
        // Matches Dockside's dark translucent style
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Left Button (+)

    private var leftButton: some View {
        Button {
            openFilePicker()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, height: 68)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add file to convert")
    }

    // MARK: - Empty Drop Zone

    private var emptyDropZone: some View {
        HStack(spacing: 10) {
            if #available(macOS 14.0, *) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace.offUp))
            } else {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(isTargeted ? "Release to convert" : "Drop documents here")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Items Area

    private var itemsArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(queue) { item in
                    ShelfItemView(item: item) {
                        withAnimation(.spring(duration: 0.25)) {
                            queue.removeAll { $0.id == item.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Right Buttons

    private var rightButtons: some View {
        HStack(spacing: 0) {
            // Expand button (Dockside's >)
            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 68)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Expand shelf")

            // Refresh / clear button (Dockside's ↺)
            if !queue.isEmpty {
                Button {
                    withAnimation { queue.removeAll() }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 68)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear all")
            }
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { showPaywall = true; return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { addToQueue(url) }
            }
        }
        return true
    }

    private func openFilePicker() {
        guard store.canConvert else { showPaywall = true; return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
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
            // temporaryDirectory doesn't throw — no try? needed
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(item.url.pathExtension)
            try? FileManager.default.copyItem(at: item.url, to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            // convert() and isConverting are MainActor-isolated — use await
            await ConversionService.shared.convert(fileURL: tempURL)

            // Poll for completion on MainActor
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

// MARK: - Shelf Item View

struct ShelfItemView: View {
    let item: QueueItem
    let onRemove: () -> Void

    @State private var showActions = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 3) {
                // File icon — matches Dockside's icon display
                ZStack(alignment: .bottomTrailing) {
                    fileIcon
                        .frame(width: 36, height: 36)

                    // State indicator
                    stateIndicator
                }

                // Filename label — matches Dockside's label style
                Text(item.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 52)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)

            // Hover action buttons — appears on hover like Dockside
            if showActions {
                hoverActions
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: 60)
        .contentShape(Rectangle())
        .onHover { showActions = $0 }
    }

    @ViewBuilder
    private var fileIcon: some View {
        if let icon = NSWorkspace.shared.icon(forFile: item.url.path) as NSImage? {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
        } else {
            Image(systemName: extensionIcon)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.7))
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
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Color.accentColor, in: Circle())
                    .symbolEffect(.rotate, isActive: true)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
        case .done:
            if #available(macOS 14.0, *) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                    .background(Color.black, in: Circle())
                    .symbolEffect(.bounce, value: true)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                    .background(Color.black, in: Circle())
            }
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .background(Color.black, in: Circle())
        }
    }

    @ViewBuilder
    private var hoverActions: some View {
        HStack(spacing: 4) {
            // Copy Markdown (only when done)
            if case .done(let markdown, _) = item.state {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                }
                .buttonStyle(ShelfActionButtonStyle())
                .help("Copy Markdown")
            }

            // Remove
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(ShelfActionButtonStyle())
            .help("Remove")
        }
        .padding(.bottom, 2)
    }

    private var extensionIcon: String {
        switch item.url.pathExtension.lowercased() {
        case "pdf":                   return "doc.richtext"
        case "docx", "doc":           return "doc.text"
        case "pptx", "ppt":           return "rectangle.on.rectangle"
        case "xlsx", "xls":           return "tablecells"
        case "html", "htm":           return "globe"
        case "mp3", "m4a", "wav":     return "waveform"
        case "png", "jpg", "jpeg":    return "photo"
        default:                      return "doc"
        }
    }
}

struct ShelfActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(4)
            .background(
                Color.black.opacity(configuration.isPressed ? 0.8 : 0.6),
                in: Circle()
            )
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
