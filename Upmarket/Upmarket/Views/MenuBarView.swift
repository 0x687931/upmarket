import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {

    @EnvironmentObject private var conversion: ConversionService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            dropTarget
            if let result = conversion.result {
                Divider()
                resultRow(result)
            }
            Divider()
            footer
        }
        .frame(width: 300)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("#")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
            Text("Upmarket")
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            if !store.hasBasicOrAbove {
                Text(store.freeDocsRemaining > 0
                     ? "\(store.freeDocsRemaining) free"
                     : store.packCredits > 0 ? "\(store.packCredits) left" : "Locked")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(store.freeDocsRemaining == 0 && store.packCredits == 0 ? .red : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Drop Target

    private var dropTarget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [5, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

            VStack(spacing: 6) {
                if conversion.isConverting || conversion.isAnalysing {
                    ProgressView()
                        .controlSize(.small)
                    Text(conversion.isAnalysing ? "Analysing…" : "Converting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                        .animation(.easeInOut(duration: 0.15), value: isTargeted)
                    Text(isTargeted ? "Release to convert" : "Drop a document")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isTargeted ? Color.accentColor : .primary)
                }
            }
            .padding(.vertical, 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard store.canConvert,
                  modelManager.allRequiredDownloaded,
                  let provider = providers.first else { return false }

            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    store.consumeConversion()
                    conversion.convert(fileURL: url, useAI: store.hasProOrAbove)
                }
            }
            return true
        }
    }

    // MARK: - Result Row

    private func resultRow(_ result: ConversionResult) -> some View {
        Group {
            switch result {
            case .success(let output):
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(output.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text("\(output.pages) pages · \(output.format)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output.markdown, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            case .failure:
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("Conversion failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { conversion.reset() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open Upmarket") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
