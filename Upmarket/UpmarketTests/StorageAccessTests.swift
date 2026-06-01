import XCTest
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
}
