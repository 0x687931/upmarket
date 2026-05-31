import SwiftUI
import UniformTypeIdentifiers

/// The Dock-adjacent shelf. Inspired by Dockside's positioning and polish,
/// but purpose-built for document conversion: drop files, see queue, copy results.
struct ShelfView: View {

    @EnvironmentObject private var conversion: ConversionService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false
    @State private var queue: [QueueItem] = []
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 280)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("#")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
            Text("Upmarket")
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            if !store.hasBasicOrAbove {
                creditsLabel
            }
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "Upmarket" || $0.isMainWindow })?
                    .makeKeyAndOrderFront(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open main window")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var creditsLabel: some View {
        let count = store.freeDocsRemaining > 0 ? store.freeDocsRemaining : store.packCredits
        let label = store.freeDocsRemaining > 0 ? "\(count) free" : (store.packCredits > 0 ? "\(count) left" : "Expired")
        let isExpired = !store.canConvert

        return Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(isExpired ? .red : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if queue.isEmpty {
            emptyState
        } else {
            queueList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(isTargeted ? 0.18 : 0.08))
                    .frame(width: 64, height: 64)
                    .animation(.easeInOut(duration: 0.2), value: isTargeted)

                // Magic Replace: swaps between outlined and filled with a morph animation
                if #available(macOS 14.0, *) {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.symbolEffect(.replace.offUp))
                        .symbolEffect(.bounce, value: isTargeted)
                } else {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                        .animation(.easeInOut(duration: 0.15), value: isTargeted)
                }
            }
            VStack(spacing: 3) {
                Text(isTargeted ? "Release to convert" : "Drop documents here")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .animation(.easeInOut(duration: 0.15), value: isTargeted)
                Text("PDF · DOCX · PPTX · HTML · Audio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 280)
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(queue) { item in
                    QueueItemRow(item: item) {
                        queue.removeAll { $0.id == item.id }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: 360)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if !queue.isEmpty {
                Button("Clear All") {
                    withAnimation { queue.removeAll() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                let pending = queue.filter { $0.state == .pending }.count
                if pending > 0 {
                    Button("Convert All") {
                        convertAll()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            } else {
                Button("Open Main Window") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Preferences") {
                    NotificationCenter.default.post(name: .showPreferences, object: nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canConvert else { showPaywall = true; return false }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    self.addToQueue(url)
                }
            }
        }
        return true
    }

    private func addToQueue(_ url: URL) {
        let item = QueueItem(url: url)
        withAnimation(.spring(duration: 0.3)) {
            queue.insert(item, at: 0)
        }
        // Auto-convert immediately
        convertItem(item)
    }

    private func convertAll() {
        for item in queue where item.state == .pending {
            convertItem(item)
        }
    }

    private func convertItem(_ item: QueueItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[idx].state = .converting

        store.consumeConversion()

        Task.detached(priority: .userInitiated) {
            let tempURL = try? FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(item.url.pathExtension)
            if let temp = tempURL {
                try? FileManager.default.copyItem(at: item.url, to: temp)
            }

            let sourceURL = tempURL ?? item.url
            let result = await withCheckedContinuation { cont in
                ConversionService.shared.convert(fileURL: sourceURL)
                // Poll for result
                Task {
                    while ConversionService.shared.isConverting { try? await Task.sleep(nanoseconds: 200_000_000) }
                    cont.resume(returning: ConversionService.shared.result)
                }
            }

            await MainActor.run {
                if let idx = self.queue.firstIndex(where: { $0.id == item.id }) {
                    switch result {
                    case .success(let output):
                        self.queue[idx].state = .done(output.markdown, output.title)
                    case .failure(let err):
                        self.queue[idx].state = .failed(err)
                    case .none:
                        self.queue[idx].state = .failed("Conversion failed")
                    }
                }
                if let temp = tempURL { try? FileManager.default.removeItem(at: temp) }
            }
        }
    }
}

// MARK: - Queue Item Model

struct QueueItem: Identifiable {
    let id = UUID()
    let url: URL
    var state: State = .pending

    var name: String { url.deletingPathExtension().lastPathComponent }
    var ext: String { url.pathExtension.uppercased() }

    enum State: Equatable {
        case pending
        case converting
        case done(String, String)   // markdown, title
        case failed(String)
    }
}

// MARK: - Queue Item Row

struct QueueItemRow: View {
    let item: QueueItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // File type badge
            Text(item.ext)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 3))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                stateLabel
            }

            Spacer()
            actionButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch item.state {
        case .pending:
            Text("Waiting…")
                .font(.caption2).foregroundStyle(.secondary)
        case .converting:
            HStack(spacing: 4) {
                if #available(macOS 15.0, *) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.rotate, isActive: true)
                } else if #available(macOS 14.0, *) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.pulse, isActive: true)
                } else {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                }
                Text("Converting").font(.caption2).foregroundStyle(.secondary)
            }
        case .done(_, _):
            HStack(spacing: 4) {
                if #available(macOS 14.0, *) {
                    Image(symbol: UpmarketSymbols.done)
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: item.state == .done("", ""))
                } else {
                    Image(symbol: UpmarketSymbols.done)
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }
                Text("Ready").font(.caption2).foregroundStyle(.green)
            }
        case .failed(let err):
            Text(err).font(.caption2).foregroundStyle(.red).lineLimit(1)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.state {
        case .done(let markdown, _):
            HStack(spacing: 4) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Image(symbol: UpmarketSymbols.copy).font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Copy Markdown")

                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        default:
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var badgeColor: Color {
        switch item.ext {
        case "PDF": return .red.opacity(0.8)
        case "DOCX", "DOC": return .blue.opacity(0.8)
        case "PPTX", "PPT": return .orange.opacity(0.8)
        case "XLSX", "XLS": return .green.opacity(0.8)
        case "HTML", "HTM": return .purple.opacity(0.8)
        case "MP3", "M4A", "WAV", "FLAC": return .pink.opacity(0.8)
        default: return Color.accentColor.opacity(0.8)
        }
    }
}

extension Notification.Name {
    static let showPreferences = Notification.Name("upmarket.showPreferences")
}
