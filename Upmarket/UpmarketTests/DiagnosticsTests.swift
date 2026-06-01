import XCTest
@testable import Upmarket

final class DiagnosticsTests: XCTestCase {
    func testDiagnosticSnapshotIsJSONAndDoesNotIncludeSourcePath() throws {
        let snapshot = DiagnosticSnapshot(
            appVersion: "1.0",
            buildNumber: "42",
            macOSVersion: "macOS",
            hardwareModel: "Mac",
            localeIdentifier: "en_US",
            correlationID: UUID().uuidString,
            lastConversionStage: ConversionStage.failed.rawValue,
            lastErrorCode: "pythonRuntime",
            plistStatus: "ok",
            entitlementStatus: "sandboxed",
            modelManifestStatus: "not-installed"
        )

        let data = try Diagnostics.makeRedactedBundle(snapshot: snapshot)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("correlationID"))
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("secret.pdf"))
    }

    func testPathRedactionKeepsOnlyLastComponent() {
        XCTAssertEqual(Diagnostics.redactPath("/Users/alice/Documents/secret.pdf"), "secret.pdf")
    }

    func testWorkspaceCleanupRemovesDirectory() throws {
        let workspace = try AppWorkspace.create(prefix: "diagnostics-test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))

        AppWorkspace.remove(workspace)

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.path))
    }

    func testOversizedInputIsRejectedBeforeCopy() throws {
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: input) }
        let handle = try FileHandle(forWritingTo: input)
        try handle.truncate(atOffset: UInt64(AppWorkspace.maxInputBytes + 1))
        try handle.close()

        let workspace = try AppWorkspace.create(prefix: "diagnostics-test")
        defer { AppWorkspace.remove(workspace) }

        XCTAssertThrowsError(try AppWorkspace.copy(input, into: workspace)) { error in
            XCTAssertEqual(error as? ConversionError, .fileTooLarge)
        }
    }
}
