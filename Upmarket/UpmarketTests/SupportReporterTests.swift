import XCTest
@testable import Upmarket

final class SupportReporterTests: XCTestCase {
    func testReportPreviewCanOmitDiagnostics() {
        let preview = SupportReporter.makePreview(
            category: .crash,
            summary: "App quit while converting.",
            includeDiagnostics: false,
            snapshot: sampleSnapshot,
            logExport: "secret log"
        )

        XCTAssertTrue(preview.body.contains("Diagnostics: omitted by user"))
        XCTAssertFalse(preview.body.contains("App Version:"))
        XCTAssertFalse(preview.body.contains("secret log"))
    }

    func testReportPreviewIncludesRedactedDiagnostics() {
        let preview = SupportReporter.makePreview(
            category: .conversionFailure,
            summary: "Failed with /Users/alex/Documents/private.pdf using Python docling",
            includeDiagnostics: true,
            snapshot: sampleSnapshot,
            logExport: "2026-06-01 [pythonBridge] Docling failed at /Users/alex/Documents/private.pdf"
        )

        XCTAssertTrue(preview.body.contains("Category: Conversion failure"))
        XCTAssertTrue(preview.body.contains("Correlation ID: job-123"))
        XCTAssertTrue(preview.body.contains("Last Stage: Processing document"))
        XCTAssertTrue(preview.body.contains("Last Error: runtime.bridge"))
        XCTAssertTrue(preview.body.contains("[redacted path]"))
        XCTAssertFalse(preview.body.contains("/Users/alex/Documents/private.pdf"))
        XCTAssertFalse(preview.body.contains("private.pdf"))
        XCTAssertFalse(preview.body.contains("Python"))
        XCTAssertFalse(preview.body.contains("pythonBridge"))
        XCTAssertFalse(preview.body.localizedCaseInsensitiveContains("docling"))
    }

    func testMailURLTargetsSupportAddress() throws {
        let preview = SupportReportPreview(subject: "Upmarket Crash", body: "Body")
        let url = try XCTUnwrap(SupportReporter.mailURL(for: preview))

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.contains("support@upmarket.app"))
        XCTAssertTrue(url.absoluteString.contains("subject=Upmarket%20Crash"))
    }

    @MainActor
    func testFailedQueueJobProvidesSupportSnapshotContext() async throws {
        let queue = ConversionQueue { _, progress in
            progress?(.python)
            return .failure(ConversionError.pythonRuntime("runtime failed").errorDescription ?? "Conversion failed.")
        }
        let id = queue.add(URL(fileURLWithPath: "/tmp/source.pdf"))

        try await waitUntil {
            queue.job(id: id)?.stage == .failed
        }

        let snapshot = queue.diagnosticSnapshotForLastFailedJob()
        XCTAssertEqual(snapshot.correlationID, id.uuidString)
        XCTAssertEqual(snapshot.lastConversionStage, "Processing document")
        XCTAssertEqual(snapshot.lastErrorCode, "runtime.bridge")
    }

    private var sampleSnapshot: DiagnosticSnapshot {
        DiagnosticSnapshot(
            appVersion: "1.0",
            buildNumber: "42",
            macOSVersion: "macOS 15.5",
            hardwareModel: "Mac15,6",
            localeIdentifier: "en_US",
            correlationID: "job-123",
            lastConversionStage: "python",
            lastErrorCode: "runtime.bridge",
            plistStatus: "ok",
            entitlementStatus: "sandboxed",
            modelManifestStatus: "manifest-present"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}
