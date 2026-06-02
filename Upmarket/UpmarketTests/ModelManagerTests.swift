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
        XCTAssertTrue(manager.allRequiredDownloaded)
    }

    func testProDownloadRequiresProductAndFeatureGate() {
        let manager = ModelManager(models: [
            Self.proModel(isDownloaded: false)
        ])

        XCTAssertEqual(
            manager.proDownloadUnavailableReason(hasPro: false, featureEnabled: true, deviceSupportsAI: true),
            "Upmarket AI requires a Pro license."
        )
        XCTAssertEqual(
            manager.proDownloadUnavailableReason(
                hasPro: true,
                featureEnabled: false,
                featureReason: "Upmarket AI is not yet available for Test",
                deviceSupportsAI: true
            ),
            "Upmarket AI is not yet available for Test"
        )
        XCTAssertEqual(
            manager.proDownloadUnavailableReason(
                hasPro: true,
                featureEnabled: true,
                deviceSupportsAI: false,
                deviceReason: "Unsupported Mac"
            ),
            "Unsupported Mac"
        )
        XCTAssertEqual(
            manager.aiUseUnavailableReason(hasPro: true, featureEnabled: true, deviceSupportsAI: true),
            "Download Upmarket AI before using it for conversion."
        )
    }

    func testAIUseChecksModelsBeforeTreatingEmptyListAsUnavailable() async {
        let manager = ModelManager(
            checkModelsHandler: {
                return [Self.proModel(isDownloaded: true)]
            }
        )

        let reason = await manager.aiUseUnavailableReasonAfterChecking(
            hasPro: true,
            featureEnabled: true,
            deviceSupportsAI: true
        )

        XCTAssertNil(reason)
        XCTAssertTrue(manager.proDownloaded)
        XCTAssertTrue(manager.hasCheckedModels)
    }

    func testDownloadProgressUpdatesBeforeCompletion() async throws {
        let manager = ModelManager(
            models: [Self.proModel(isDownloaded: false)],
            downloadModelHandler: { _, progressFile in
                writeProgress(percent: 25, message: "Downloading", to: progressFile)
                try? await Task.sleep(nanoseconds: 700_000_000)
                appendProgress(percent: 80, message: "Validating", to: progressFile)
                try? await Task.sleep(nanoseconds: 700_000_000)
                return ModelDownloadResult(success: true, error: nil)
            }
        )

        manager.downloadProModels(
            hasPro: true
        )

        try await waitUntil(timeout: 8) {
            manager.isDownloading && manager.downloadProgress >= 25
        }
        XCTAssertGreaterThanOrEqual(manager.downloadProgress, 25)

        try await waitUntil(timeout: 8) {
            !manager.isDownloading
        }
        XCTAssertEqual(manager.downloadProgress, 100)
        XCTAssertNil(manager.downloadError)
    }

    func testProModelKeepsConfiguredStorageDirectory() {
        let model = Self.proModel(isDownloaded: true, storageDirectory: "ibm-granite--granite-docling-258M-mlx")
        let manager = ModelManager(models: [model])

        XCTAssertTrue(manager.proDownloaded)
        XCTAssertEqual(manager.models[0].storageDirectory, "ibm-granite--granite-docling-258M-mlx")
    }

    private static func proModel(isDownloaded: Bool, storageDirectory: String? = nil) -> ModelStatus {
        ModelStatus(
            key: "upmarket_ai",
            name: "Upmarket AI",
            description: "Advanced local conversion",
            isDownloaded: isDownloaded,
            sizeMB: 631,
            isRequired: false,
            tier: "pro",
            storageDirectory: storageDirectory
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
