import XCTest
@testable import Upmarket

/// End-to-end verification of the tall-table banding fallback through the REAL extract() path
/// (extractImageStructured -> processImage -> gate -> extractTablesByBanding), using FinTabNet
/// table images the spike measured. Skips cleanly when the corpus or macOS 26 Vision is absent.
final class VisionBandingE2ETests: XCTestCase {

    private func fixture(_ name: String) -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }  // .../UpmarketTests -> .../Upmarket -> repo
        return root.appendingPathComponent("tests/corpus/tables/fintabnet/\(name)")
    }

    /// 000006.jpg is a 30-row financial table that direct Vision MISSES (returns no table).
    /// The banding fallback was meant to recover it — but on the IDL whole-page corpus its
    /// stitch mis-groups cells and drops prose, so the call site is disabled
    /// (VisionDocumentExtractor.tableBandingEnabled = false) pending a stitch-quality fix. This
    /// test is skipped until then; the banding functions and their stitch unit tests remain.
    func testBandingRecoversTallTableEndToEnd() async throws {
        throw XCTSkip("banding call site disabled (tableBandingEnabled=false) pending stitch-quality fix")
    }

    /// Control: a small table Vision detects on the first pass still works (no regression,
    /// and the banding gate did not need to fire).
    func testDirectDetectionStillWorks() async throws {
        try XCTSkipUnless(VisionDocumentExtractor.isAvailable, "needs macOS 26 Vision")
        let url = fixture("000000.jpg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "corpus fixture absent")

        let result = try await VisionDocumentExtractor.extract(imageURL: url)
        XCTAssertGreaterThanOrEqual(result.tablesFound, 1)
    }
}
