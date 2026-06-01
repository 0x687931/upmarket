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
            summary: "Failed with /Users/alex/Documents/private.pdf",
            includeDiagnostics: true,
            snapshot: sampleSnapshot,
            logExport: "2026-06-01 [conversion] failed"
        )

        XCTAssertTrue(preview.body.contains("Category: Conversion failure"))
        XCTAssertTrue(preview.body.contains("Correlation ID: job-123"))
        XCTAssertTrue(preview.body.contains("/Users/[redacted]/Documents/private.pdf"))
        XCTAssertFalse(preview.body.contains("/Users/alex/Documents/private.pdf"))
    }

    func testMailURLTargetsSupportAddress() throws {
        let preview = SupportReportPreview(subject: "Upmarket Crash", body: "Body")
        let url = try XCTUnwrap(SupportReporter.mailURL(for: preview))

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.contains("support@upmarket.app"))
        XCTAssertTrue(url.absoluteString.contains("subject=Upmarket%20Crash"))
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
            lastErrorCode: "pythonRuntime",
            plistStatus: "ok",
            entitlementStatus: "sandboxed",
            modelManifestStatus: "manifest-present"
        )
    }
}
