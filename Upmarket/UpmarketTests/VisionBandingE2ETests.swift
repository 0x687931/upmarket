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
    /// With the banding fallback wired in, extract() must now recover it.
    func testBandingRecoversTallTableEndToEnd() async throws {
        try XCTSkipUnless(VisionDocumentExtractor.isAvailable, "needs macOS 26 Vision")
        let url = fixture("000006.jpg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "corpus fixture absent")

        let result = try await VisionDocumentExtractor.extract(imageURL: url)
        XCTAssertGreaterThanOrEqual(result.tablesFound, 1, "banding should recover the missed tall table")
        let rows = result.structuredTables.first?.rows.count ?? 0
        XCTAssertGreaterThanOrEqual(rows, 10, "recovered table should have many rows; got \(rows)")
        XCTAssertTrue(result.markdown.contains("|"), "markdown should contain a table")
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
