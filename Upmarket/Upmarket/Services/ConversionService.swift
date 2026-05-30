import Foundation
import Combine
import PythonKit

final class ConversionService: ObservableObject {

    static let shared = ConversionService()

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var isConverting = false {
        willSet { objectWillChange.send() }
    }

    private(set) var result: ConversionResult?  {
        willSet { objectWillChange.send() }
    }

    private init() {}

    func reset() {
        result = nil
    }

    func convert(fileURL: URL) {
        guard !isConverting else { return }
        isConverting = true
        result = nil

        // Copy to temp dir so the sandboxed Python process can read it
        let tempURL: URL
        do {
            tempURL = try copyToTemp(fileURL: fileURL)
        } catch {
            result = .failure("Could not access file: \(error.localizedDescription)")
            isConverting = false
            return
        }

        Task.detached(priority: .userInitiated) {
            let output = await self.runConversion(fileURL: tempURL, originalURL: fileURL)
            try? FileManager.default.removeItem(at: tempURL)
            await MainActor.run {
                self.result = output
                self.isConverting = false
            }
        }
    }

    // MARK: - Private

    private func copyToTemp(fileURL: URL) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileURL.pathExtension)
        try FileManager.default.copyItem(at: fileURL, to: tmp)
        return tmp
    }

    private func runConversion(fileURL: URL, originalURL: URL) async -> ConversionResult {
        let converter = Python.import("docling_bridge.converter")
        let pyResult  = converter.convert(fileURL.path)

        let success = Bool(pyResult["success"]) ?? false

        if success {
            let markdown = String(pyResult["markdown"]) ?? ""
            let meta     = pyResult["metadata"]
            let pages    = Int(meta["pages"]) ?? 0
            let format   = String(meta["format"]) ?? ""
            let title    = String(meta["title"]) ?? originalURL.deletingPathExtension().lastPathComponent
            return .success(ConversionOutput(markdown: markdown, pages: pages, format: format, title: title))
        } else {
            let error = String(pyResult["error"]) ?? "Unknown error"
            return .failure(error)
        }
    }
}

// MARK: - Models

enum ConversionResult {
    case success(ConversionOutput)
    case failure(String)
}

struct ConversionOutput {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
}
