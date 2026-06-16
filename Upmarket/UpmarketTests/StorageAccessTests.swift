import XCTest
import UniformTypeIdentifiers
@testable import Upmarket

final class StorageAccessTests: XCTestCase {
    func testLocalInputPassesReadableValidation() throws {
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try "hello".write(to: input, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: input) }

        XCTAssertNoThrow(try FileAccessService.shared.validateReadableInput(input))
    }

    func testMissingInputMapsToUnavailable() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        XCTAssertThrowsError(try FileAccessService.shared.validateReadableInput(missing)) { error in
            XCTAssertEqual(error as? FileAccessError, .unavailable)
            XCTAssertEqual(
                FileAccessService.userVisibleMessage(for: error),
                "This document is not available on this Mac. Download it and try again."
            )
        }
    }

    func testUnsupportedInputHasProductLevelError() throws {
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "hello".write(to: input, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: input) }

        XCTAssertThrowsError(try FileAccessService.shared.validateReadableInput(input)) { error in
            XCTAssertEqual(error as? FileAccessError, .unsupportedType)
            XCTAssertEqual(
                FileAccessService.userVisibleMessage(for: error),
                "Choose a supported document file to convert."
            )
            XCTAssertFalse(FileAccessService.userVisibleMessage(for: error).contains("Python"))
        }
    }

    func testTooLargeInputHasProductLevelError() throws {
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try "hello".write(to: input, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: input) }

        XCTAssertThrowsError(try FileAccessService.shared.validateReadableInput(input, maxBytes: 1)) { error in
            XCTAssertEqual(error as? FileAccessError, .tooLarge)
            XCTAssertEqual(
                FileAccessService.userVisibleMessage(for: error),
                "This document is too large to convert safely."
            )
        }
    }

    func testSupportedInputPolicyIncludesReleaseCriticalFormats() {
        // All served by native engines (EPUB via ZipReader + HTML). ZIP/WEBVTT were
        // Python-only and were dropped when the Python runtime was removed.
        let expectedExtensions = ["pdf", "txt", "docx", "pptx", "xlsx", "html", "epub", "csv", "png", "mp3", "wav"]
        for fileExtension in expectedExtensions {
            let url = URL(fileURLWithPath: "/tmp/input.\(fileExtension)")
            XCTAssertTrue(SupportedInputPolicy.supports(url), "Expected \(fileExtension) to be accepted")
        }
    }

    func testSupportedInputPolicyDoesNotFallBackToGenericData() {
        XCTAssertFalse(SupportedInputPolicy.typeIdentifiers.contains(UTType.data.identifier))
        XCTAssertFalse(SupportedInputPolicy.supports(URL(fileURLWithPath: "/tmp/input")))
        XCTAssertFalse(SupportedInputPolicy.supports(URL(fileURLWithPath: "/tmp/input.unsupported-upmarket")))
    }

    func testQuickActionSupportedInputAdapterMatchesAppPolicy() throws {
        // The Quick Action must derive accepted inputs from the single source of truth
        // (ToolFormatCapabilityMatrix) rather than a hand-maintained list that can drift.
        let quickActionSource = try String(contentsOf: quickActionSourceURL(), encoding: .utf8)
        XCTAssertTrue(
            quickActionSource.contains("ToolFormatCapabilityMatrix.accepts("),
            "Quick Action must gate inputs through ToolFormatCapabilityMatrix, the input-policy source of truth"
        )
        XCTAssertFalse(quickActionSource.contains("?? .data"))
    }

    func testAppIntentSupportedTypeAdapterMatchesAppPolicy() throws {
        // The App Intent enforces the input policy at perform time via validateReadableInput,
        // which routes through SupportedInputPolicy.supports — the single source of truth.
        // This guards against an Intent that converts without first applying the input policy.
        // (The deployment target is macOS 26.0, so IntentFile.supportedContentTypes is also
        // available should we ever want to declare types up front as well.)
        let intentsSource = try String(contentsOf: intentsSourceURL(), encoding: .utf8)
        XCTAssertTrue(
            intentsSource.contains("validateReadableInput"),
            "App Intent must enforce the input policy at perform time via validateReadableInput"
        )
    }

    func testStorageKindClassifiesAppleCloudAndProviderPaths() {
        XCTAssertEqual(
            FileAccessService.storageKind(for: URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/report.pdf")),
            .iCloudDrive
        )
        XCTAssertEqual(
            FileAccessService.storageKind(for: URL(fileURLWithPath: "/Users/me/Library/CloudStorage/Dropbox/report.pdf")),
            .fileProvider
        )
        XCTAssertEqual(
            FileAccessService.storageKind(for: URL(fileURLWithPath: "/Volumes/USB/report.pdf")),
            .externalVolume
        )
        XCTAssertEqual(
            FileAccessService.storageKind(for: URL(fileURLWithPath: "/Users/me/Documents/report.pdf")),
            .local
        )
    }

    func testUnavailableInputMapsToProductLevelConversionError() throws {
        let workspace = try AppWorkspace.create(prefix: "storage-test")
        defer { AppWorkspace.remove(workspace) }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        XCTAssertThrowsError(try AppWorkspace.copy(missing, into: workspace)) { error in
            XCTAssertEqual(error as? ConversionError, .sourceUnavailable)
            XCTAssertFalse(error.localizedDescription.contains("Python"))
        }
    }

    private func quickActionSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UpmarketQuickAction/ActionViewController.swift")
    }

    private func intentsSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Upmarket/Intents/UpmarketIntents.swift")
    }
}
