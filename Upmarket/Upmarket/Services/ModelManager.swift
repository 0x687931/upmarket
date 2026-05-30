import Foundation
import Combine
import PythonKit

struct ModelStatus {
    let key: String
    let name: String
    let description: String
    let isDownloaded: Bool
    let sizeMB: Int
    let isRequired: Bool
    let tier: String
}

final class ModelManager: ObservableObject {

    static let shared = ModelManager()

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var models: [ModelStatus] = [] {
        willSet { objectWillChange.send() }
    }

    private(set) var isDownloading = false {
        willSet { objectWillChange.send() }
    }

    private(set) var downloadProgress: Double = 0 {
        willSet { objectWillChange.send() }
    }

    private(set) var downloadMessage = "" {
        willSet { objectWillChange.send() }
    }

    private(set) var downloadError: String? {
        willSet { objectWillChange.send() }
    }

    private init() {}

    // Fast path (PyMuPDF4LLM) always works — no download required
    var allRequiredDownloaded: Bool { true }

    var enhancedDownloaded: Bool {
        models.first { $0.tier == "enhanced" }?.isDownloaded ?? false
    }

    var requiredSizeMB: Int {
        models.filter(\.isRequired).reduce(0) { $0 + $1.sizeMB }
    }

    var proSizeMB: Int {
        models.filter { $0.tier == "pro" }.reduce(0) { $0 + $1.sizeMB }
    }

    // MARK: - Public

    func checkModels() {
        let manager = Python.import("upmarket_models.model_manager")
        let pyStatus = manager.check_models()

        var result: [ModelStatus] = []
        for item in pyStatus.items() {
            guard let key = String(item[0]) else { continue }
            let info = item[1]
            result.append(ModelStatus(
                key: key,
                name: String(info["name"]) ?? key,
                description: String(info["description"]) ?? "",
                isDownloaded: Bool(info["downloaded"]) ?? false,
                sizeMB: Int(info["size_mb"]) ?? 0,
                isRequired: Bool(info["required"]) ?? false,
                tier: String(info["tier"]) ?? "basic"
            ))
        }

        DispatchQueue.main.async {
            self.models = result.sorted { $0.isRequired && !$1.isRequired }
        }
    }

    func downloadRequiredModels() {
        downloadModels(keys: models.filter(\.isRequired).map(\.key))
    }

    func downloadProModels() {
        downloadModels(keys: models.filter { $0.tier == "pro" && !$0.isDownloaded }.map(\.key))
    }

    // MARK: - Private

    private func downloadModels(keys: [String]) {
        guard !isDownloading else { return }
        isDownloading = true
        downloadError = nil
        downloadProgress = 0

        Task.detached(priority: .userInitiated) {
            for key in keys {
                await self.downloadSingleModel(key: key)
                if await self.downloadError != nil { break }
            }

            let manager = Python.import("upmarket_models.model_manager")
            manager.set_offline_mode()

            await MainActor.run {
                self.isDownloading = false
                self.checkModels()
            }
        }
    }

    private func downloadSingleModel(key: String) async {
        let progressFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("upmarket_\(key)_progress.jsonl")
            .path

        // Clear any existing progress file
        try? FileManager.default.removeItem(atPath: progressFile)

        let manager = Python.import("upmarket_models.model_manager")

        // Start download in a separate task so we can poll progress
        let downloadTask = Task.detached {
            manager.download_model(key, progressFile)
        }

        // Poll progress file every 500ms
        while !downloadTask.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)

            if let lines = try? String(contentsOfFile: progressFile, encoding: .utf8) {
                let lastLine = lines.split(separator: "\n").last.map(String.init)
                if let line = lastLine,
                   let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let percent = json["percent"] as? Double ?? 0
                    let message = json["message"] as? String ?? ""
                    await MainActor.run {
                        self.downloadProgress = percent
                        self.downloadMessage = message
                    }
                }
            }

            // Check if download completed
            let result = await downloadTask.value
            if let result = result as? PythonObject {
                let success = Bool(result["success"]) ?? false
                if !success {
                    let error = String(result["error"]) ?? "Download failed"
                    await MainActor.run { self.downloadError = error }
                }
                break
            }
        }

        try? FileManager.default.removeItem(atPath: progressFile)
    }
}
