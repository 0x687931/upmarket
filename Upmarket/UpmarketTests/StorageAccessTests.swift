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
        let quickActionSource = try String(contentsOf: quickActionSourceURL(), encoding: .utf8)
        let expectedExtensions = ["pdf", "html", "txt", "png", "jpg", "jpeg", "gif", "tiff", "docx", "pptx", "xlsx", "epub", "csv", "json", "xml", "zip", "mp3", "m4a", "wav", "aiff", "opus"]

        for fileExtension in expectedExtensions {
            XCTAssertTrue(quickActionSource.contains("\"\(fileExtension)\""), "Quick Action policy is missing \(fileExtension)")
            XCTAssertTrue(SupportedInputPolicy.supports(URL(fileURLWithPath: "/tmp/input.\(fileExtension)")), "App policy is missing \(fileExtension)")
        }
        XCTAssertFalse(quickActionSource.contains("?? .data"))
    }

    func testAppIntentSupportedTypeAdapterMatchesAppPolicy() throws {
        let intentsSource = try String(contentsOf: intentsSourceURL(), encoding: .utf8)

        for identifier in SupportedInputPolicy.typeIdentifiers {
            XCTAssertTrue(intentsSource.contains("\"\(identifier)\""), "App Intent policy is missing \(identifier)")
        }
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
