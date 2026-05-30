//
//  ContentView.swift
//  Upmarket
//
//  Created by Andrew McArdle on 30/5/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @EnvironmentObject private var conversion: ConversionService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager
    @State private var isTargeted = false
    @State private var showPaywall = false
    @State private var showModelDownload = false

    var body: some View {
        VStack(spacing: 0) {
            trialBanner
            if conversion.isConverting {
                convertingView
            } else if let result = conversion.result {
                resultView(result)
            } else {
                dropZone
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        .sheet(isPresented: $showModelDownload) {
            ModelDownloadView()
                .environmentObject(modelManager)
                .environmentObject(store)
        }
        .onAppear {
            modelManager.checkModels()
            if !modelManager.allRequiredDownloaded {
                showModelDownload = true
            }
        }
        .onChange(of: modelManager.allRequiredDownloaded) { _, ready in
            if ready { showModelDownload = false }
        }
    }

    // MARK: - Trial Banner

    @ViewBuilder
    private var trialBanner: some View {
        switch store.entitlement {
        case .trial(let days):
            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text(days == 1 ? "1 day left in your free trial" : "\(days) days left in your free trial")
                    .fontWeight(.medium)
                Spacer()
                Button("Upgrade") { showPaywall = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .font(.subheadline)
        case .none:
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text("Your free trial has expired")
                    .fontWeight(.medium)
                Spacer()
                Button("Unlock Upmarket") { showPaywall = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .font(.subheadline)
        default:
            EmptyView()
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 56))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text("Drop a document here")
                .font(.title2)
                .fontWeight(.medium)

            Text("PDF, Word, PowerPoint, Excel, HTML")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Choose File…") { openFilePicker() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3) as Color,
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding(24)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .padding(24)
    }

    // MARK: - Converting

    private var convertingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Converting…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result

    private func resultView(_ result: ConversionResult) -> some View {
        switch result {
        case .success(let output):
            return AnyView(
                VStack(spacing: 0) {
                    toolbar(output)
                    Divider()
                    ScrollView {
                        Text(output.markdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            )
        case .failure(let error):
            return AnyView(
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                    Text("Conversion failed")
                        .font(.title3).fontWeight(.medium)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Try Another File") { conversion.reset() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            )
        }
    }

    private func toolbar(_ output: ConversionOutput) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(output.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(output.format) · \(output.pages) page\(output.pages == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output.markdown, forType: .string)
            }
            .buttonStyle(.bordered)

            Button("Save…") { saveMarkdown(output) }
                .buttonStyle(.borderedProminent)

            Button("Convert Another") { conversion.reset() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func openFilePicker() {
        guard store.hasBasicOrAbove else { showPaywall = true; return }
        guard modelManager.allRequiredDownloaded else { showModelDownload = true; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .html, .png, .jpeg,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            conversion.convert(fileURL: url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.hasBasicOrAbove else { showPaywall = true; return false }
        guard modelManager.allRequiredDownloaded else { showModelDownload = true; return false }
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { conversion.convert(fileURL: url) }
        }
        return true
    }

    private func saveMarkdown(_ output: ConversionOutput) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = output.title + ".md"
        if panel.runModal() == .OK, let url = panel.url {
            try? output.markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ConversionService.shared)
}
