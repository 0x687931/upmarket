import XCTest
@testable import Upmarket

final class ModelManagerTests: XCTestCase {

    func testCheckFailureIsVisibleInstallFailure() async throws {
        let manager = ModelManager(
            checkModelsHandler: {
                throw NSError(domain: "test", code: 1)
            }
        )

        manager.checkModels()

        try await waitUntil {
            if case .failed = manager.installState { return true }
            return false
        }

        XCTAssertEqual(manager.models, [])
        XCTAssertEqual(manager.checkError, "Upmarket couldn't check local model files. Try again from Settings.")
    }

    func testEmptyModelCheckIsReadyFastPathNotFailure() async throws {
        let manager = ModelManager(
            checkModelsHandler: { [] }
        )

        manager.checkModels()

        try await waitUntil {
            if case .ready = manager.installState { return true }
            return false
        }

        XCTAssertEqual(manager.models, [])
        XCTAssertNil(manager.checkError)
    }

    func testGateBlocksAIDownloadWithoutMaxTier() {
        let assets: Set<ModelAsset> = []

        let gateNoTier = AppTierGate(tier: .basic, downloadedAssets: assets,
                                      deviceSupportsRuntime: true, aiFeatureEnabled: true, aiFeatureUnavailableReason: nil)
        XCTAssertNotNil(gateNoTier.downloadUnavailableReason(for: .upmarketAI))

        let gateFeatureOff = AppTierGate(tier: .max, downloadedAssets: assets,
                                          deviceSupportsRuntime: true, aiFeatureEnabled: false,
                                          aiFeatureUnavailableReason: "Upmarket AI is not yet available for Test")
        XCTAssertEqual(
            gateFeatureOff.downloadUnavailableReason(for: .upmarketAI),
            "Upmarket AI is not yet available for Test"
        )

        let gateNoDevice = AppTierGate(tier: .max, downloadedAssets: assets,
                                        deviceSupportsRuntime: false, aiFeatureEnabled: true, aiFeatureUnavailableReason: nil)
        XCTAssertNotNil(gateNoDevice.downloadUnavailableReason(for: .upmarketAI))
    }

    func testGateBlocksAIUseWhenModelNotDownloaded() {
        let gate = AppTierGate(tier: .max, downloadedAssets: [],
                                deviceSupportsRuntime: true, aiFeatureEnabled: true, aiFeatureUnavailableReason: nil)
        XCTAssertNotNil(gate.unavailableReason(for: .ai))
    }

    func testGateAfterCheckingAllowsAIWhenModelDownloaded() async {
        let manager = ModelManager(
            checkModelsHandler: {
                return [
                    Self.runtimeModel(isDownloaded: true),
                    Self.maxModel(isDownloaded: true)
                ]
            }
        )

        let gate = await manager.gateAfterChecking(tier: .max)
        XCTAssertNil(gate.unavailableReason(for: .ai))
        XCTAssertTrue(manager.downloadedAssets.contains(.pythonRuntime))
        XCTAssertTrue(manager.downloadedAssets.contains(.upmarketAI))
        XCTAssertTrue(manager.hasCheckedModels)
    }

    func testDownloadProgressUpdatesBeforeCompletion() async throws {
        let manager = ModelManager(
            models: [
                Self.runtimeModel(isDownloaded: true),
                Self.maxModel(isDownloaded: false)
            ],
            downloadModelHandler: { _, progressFile in
                writeProgress(percent: 25, message: "Downloading", to: progressFile)
                try? await Task.sleep(nanoseconds: 700_000_000)
                appendProgress(percent: 80, message: "Validating", to: progressFile)
                try? await Task.sleep(nanoseconds: 700_000_000)
                return ModelDownloadResult(success: true, error: nil)
            }
        )

        let gate = AppTierGate(tier: .max, downloadedAssets: [.pythonRuntime], deviceSupportsRuntime: true, aiFeatureEnabled: true, aiFeatureUnavailableReason: nil)
        manager.downloadAssets(for: .ai, gate: gate)

        try await waitUntil(timeout: 8) {
            manager.isDownloading && manager.downloadProgress >= 25
        }
        XCTAssertGreaterThanOrEqual(manager.downloadProgress, 25)
        XCTAssertEqual(manager.downloadingModelKey, "upmarket_ai")

        try await waitUntil(timeout: 8) {
            !manager.isDownloading
        }
        XCTAssertEqual(manager.downloadProgress, 100)
        XCTAssertNil(manager.downloadError)
        XCTAssertNil(manager.downloadingModelKey)
    }

    func testDownloadFailureSetsVisibleErrorAndClearsActiveModel() async throws {
        let manager = ModelManager(
            models: [Self.proModel(isDownloaded: false)],
            downloadModelHandler: { _, _ in
                ModelDownloadResult(success: false, error: "Connection failed")
            }
        )

        let gate = AppTierGate(tier: .pro, downloadedAssets: [], deviceSupportsRuntime: true, aiFeatureEnabled: true, aiFeatureUnavailableReason: nil)
        manager.downloadAsset(.layout, gate: gate)

        try await waitUntil(timeout: 5) {
            !manager.isDownloading && manager.downloadError != nil
        }

        XCTAssertEqual(manager.downloadError, "Connection failed")
        XCTAssertNil(manager.downloadingModelKey)
    }

    func testMaxModelKeepsConfiguredStorageDirectory() {
        let model = Self.maxModel(isDownloaded: true, storageDirectory: "ibm-granite--granite-docling-258M-mlx")
        let manager = ModelManager(models: [model])

        XCTAssertTrue(manager.downloadedAssets.contains(.upmarketAI))
        XCTAssertEqual(manager.models[0].storageDirectory, "ibm-granite--granite-docling-258M-mlx")
    }

    func testStorageCountsOnlyDownloadedRecognizedModelDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("upmarket-model-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writeBytes(11, to: root.appendingPathComponent("layout/model.bin"))
        try writeBytes(17, to: root.appendingPathComponent("ibm-granite--granite-docling-258M-mlx/model.bin"))
        try writeBytes(23, to: root.appendingPathComponent("stale-cache/model.bin"))

        let manager = ModelManager(
            models: [
                Self.proModel(isDownloaded: true),
                Self.maxModel(isDownloaded: false, storageDirectory: "ibm-granite--granite-docling-258M-mlx")
            ],
            modelsDirectoryURL: root
        )

        XCTAssertEqual(manager.downloadedModelCount, 1)
        XCTAssertEqual(manager.downloadedModelEstimatedSizeMB, 20)
        XCTAssertEqual(manager.totalStorageUsed, 11)
    }

    func testDeleteModelKeepsRowAvailableForRedownload() {
        let manager = ModelManager(
            models: [Self.maxModel(isDownloaded: true)],
            checkModelsHandler: {
                [Self.maxModel(isDownloaded: false)]
            }
        )

        manager.deleteModel(key: "upmarket_ai")

        XCTAssertEqual(manager.models.count, 1)
        XCTAssertEqual(manager.models[0].key, "upmarket_ai")
        XCTAssertFalse(manager.models[0].isDownloaded)
        XCTAssertEqual(manager.models[0].error, "not downloaded")
    }

    func testCheckErrorClearsOnSuccessfulRetry() async throws {
        var callCount = 0
        let manager = ModelManager(
            checkModelsHandler: {
                callCount += 1
                if callCount == 1 { throw NSError(domain: "test", code: 1) }
                return [Self.maxModel(isDownloaded: true)]
            }
        )

        manager.checkModels()
        try await waitUntil {
            if case .failed = manager.installState { return true }
            return false
        }
        XCTAssertNotNil(manager.checkError)

        manager.checkModels()
        try await waitUntil {
            if case .ready = manager.installState { return true }
            return false
        }
        XCTAssertNil(manager.checkError)
        XCTAssertEqual(manager.models.count, 1)
    }

    func testOfflineModeHandlerCalledAfterSuccessfulDownload() async throws {
        let offlineCalled = OfflineModeCallCounter()
        let manager = ModelManager(
            models: [Self.maxModel(isDownloaded: false)],
            checkModelsHandler: {
                [Self.maxModel(isDownloaded: true)]
            },
            downloadModelHandler: { _, _ in
                ModelDownloadResult(success: true, error: nil)
            },
            offlineModeHandler: {
                await offlineCalled.increment()
            }
        )

        let gate = AppTierGate(tier: .max, downloadedAssets: [.pythonRuntime], deviceSupportsRuntime: true, aiFeatureEnabled: true, aiFeatureUnavailableReason: nil)
        manager.downloadAssets(for: .ai, gate: gate)

        try await waitUntil(timeout: 5) {
            !manager.isDownloading
        }

        let count = await offlineCalled.count
        XCTAssertEqual(count, 1)
        XCTAssertNil(manager.downloadError)
    }

    func testOfflineModeHandlerNotCalledAfterFailedDownload() async throws {
        let offlineCalled = OfflineModeCallCounter()
        let manager = ModelManager(
            models: [Self.maxModel(isDownloaded: false)],
            downloadModelHandler: { _, _ in
                ModelDownloadResult(success: false, error: "Network error")
            },
            offlineModeHandler: {
                await offlineCalled.increment()
            }
        )

        let gate = AppTierGate(tier: .max, downloadedAssets: [], deviceSupportsRuntime: true, aiFeatureEnabled: true, aiFeatureUnavailableReason: nil)
        manager.downloadAssets(for: .ai, gate: gate)

        try await waitUntil(timeout: 5) {
            !manager.isDownloading && manager.downloadError != nil
        }

        let count = await offlineCalled.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(manager.downloadError, "Network error")
    }

    func testIndividualDownloadUsesSelectedOptionalModelKey() async throws {
        let recorder = DownloadKeyRecorder()
        let manager = ModelManager(
            models: [Self.proModel(isDownloaded: false)],
            checkModelsHandler: {
                [Self.proModel(isDownloaded: true)]
            },
            downloadModelHandler: { key, _ in
                await recorder.record(key)
                return ModelDownloadResult(success: true, error: nil)
            }
        )

        let gate = AppTierGate(tier: .pro, downloadedAssets: [], deviceSupportsRuntime: true, aiFeatureEnabled: true, aiFeatureUnavailableReason: nil)
        manager.downloadAsset(.layout, gate: gate)

        try await waitUntil(timeout: 5) {
            !manager.isDownloading
        }

        let keys = await recorder.keys
        XCTAssertEqual(keys, ["layout"])
        XCTAssertNil(manager.downloadError)
        XCTAssertEqual(manager.models, [Self.proModel(isDownloaded: true)])
    }

    private func writeBytes(_ count: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0, count: count).write(to: url)
    }

    private static func maxModel(isDownloaded: Bool, storageDirectory: String? = nil) -> ModelStatus {
        ModelStatus(
            key: "upmarket_ai",
            name: "Upmarket AI",
            description: "Advanced local conversion",
            isDownloaded: isDownloaded,
            sizeMB: 600,
            isRequired: false,
            tier: "max",
            storageDirectory: storageDirectory
        )
    }

    private static func runtimeModel(isDownloaded: Bool) -> ModelStatus {
        ModelStatus(
            key: "python_runtime_pro",
            name: "Upmarket Runtime",
            description: "Required for Enhanced and AI conversion",
            isDownloaded: isDownloaded,
            sizeMB: 367,
            isRequired: false,
            tier: "pro",
            error: isDownloaded ? nil : "not downloaded",
            storageDirectory: "python_runtime_pro"
        )
    }

    private static func proModel(isDownloaded: Bool) -> ModelStatus {
        ModelStatus(
            key: "layout",
            name: "Upmarket Enhanced",
            description: "Better results for complex PDFs",
            isDownloaded: isDownloaded,
            sizeMB: 20,
            isRequired: false,
            tier: "pro",
            error: isDownloaded ? nil : "not downloaded"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await MainActor.run(body: condition) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor OfflineModeCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor DownloadKeyRecorder {
    private var recordedKeys: [String] = []

    var keys: [String] {
        recordedKeys
    }

    func record(_ key: String) {
        recordedKeys.append(key)
    }
}

private func writeProgress(percent: Double, message: String, to path: String) {
    let line = #"{"percent":\#(percent),"message":"\#(message)"}"# + "\n"
    try? line.write(toFile: path, atomically: true, encoding: .utf8)
}

private func appendProgress(percent: Double, message: String, to path: String) {
    guard let data = (#"{"percent":\#(percent),"message":"\#(message)"}"# + "\n").data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: path),
       let handle = FileHandle(forWritingAtPath: path) {
        defer { try? handle.close() }
        try? handle.seekToEnd()
        handle.write(data)
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
