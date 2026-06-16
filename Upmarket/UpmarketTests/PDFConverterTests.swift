import AppKit
import CoreText
import XCTest
@testable import Upmarket

final class PDFConverterTests: XCTestCase {
    func testPDFKitConversionStillHandlesSmallDigitalPDF() throws {
        let url = temporaryPDFURL()
        try writePDF(
            to: url,
            pages: [
                """
                Quarterly Report
                Revenue increased across the core product line as more customers converted documents locally.
                The operating summary contains enough digital text for the native extractor to treat this as a digital PDF.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFConverter.convert(url: url)

        XCTAssertEqual(result.pageCount, 1)
        XCTAssertTrue(result.markdown.contains("Quarterly Report"))
        XCTAssertFalse(result.isLikelyScanned)
    }

    func testPDFKitJoinsHyphenSpacingAndDetectsNumberedHeadings() throws {
        let url = temporaryPDFURL()
        try writePDF(
            to: url,
            pages: [
                """
                1 Executive Summary
                Previso is a full- time start- up pursuing a subscription- based model.
                2.1 Overview of the Market
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let md = try PDFConverter.convert(url: url).markdown

        // Hyphen-spacing artifacts collapsed.
        XCTAssertTrue(md.contains("full-time"))
        XCTAssertTrue(md.contains("start-up"))
        XCTAssertTrue(md.contains("subscription-based"))
        XCTAssertFalse(md.contains("full- time"))
        // Numbered headings promoted by depth.
        XCTAssertTrue(md.contains("## 1 Executive Summary"))
        XCTAssertTrue(md.contains("### 2.1 Overview of the Market"))
    }

    func testPDFKitConversionRejectsOverLimitPageCount() throws {
        let url = temporaryPDFURL()
        try writePDF(to: url, pages: ["Page One", "Page Two"])
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(
            try PDFConverter.convert(
                url: url,
                limits: PDFConverter.Limits(
                    maximumPages: 1,
                    maximumPageSidePoints: VisionProcessingLimits.maximumPDFPageSidePoints,
                    maximumPageAreaPoints: VisionProcessingLimits.maximumPDFPageAreaPoints
                )
            )
        ) { error in
            guard case VisionProcessingLimitError.tooManyPages(let pageCount) = error else {
                return XCTFail("Expected tooManyPages, got \(error)")
            }
            XCTAssertEqual(pageCount, 2)
        }
    }

    func testPDFKitConversionRejectsExtremePageGeometry() throws {
        let url = temporaryPDFURL()
        try writePDF(
            to: url,
            pages: ["Oversized page"],
            mediaBox: CGRect(x: 0, y: 0, width: 20_000, height: 20_000)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try PDFConverter.convert(url: url)) { error in
            guard case VisionProcessingLimitError.pageTooLarge = error else {
                return XCTFail("Expected pageTooLarge, got \(error)")
            }
        }
    }

    func testVisionProcessingLimitsRejectPDFKitPageAndGeometryLimits() {
        XCTAssertThrowsError(
            try VisionProcessingLimits.validatePDFKitPageCount(VisionProcessingLimits.maximumPDFKitPages + 1)
        )
        XCTAssertThrowsError(
            try VisionProcessingLimits.validatePDFPageBounds(
                CGRect(
                    x: 0,
                    y: 0,
                    width: VisionProcessingLimits.maximumPDFPageSidePoints + 1,
                    height: 500
                )
            )
        )
    }

    private func temporaryPDFURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("upmarket-pdfconverter-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
    }

    private func writePDF(
        to url: URL,
        pages: [String],
        mediaBox: CGRect = CGRect(x: 0, y: 0, width: 500, height: 320)
    ) throws {
        var pageBox = mediaBox
        guard let context = CGContext(url as CFURL, mediaBox: &pageBox, nil) else {
            throw NSError(domain: "PDFConverterTests", code: 1)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]

        for page in pages {
            context.beginPDFPage(nil)
            var y = Int(min(mediaBox.height - 70, 250))
            for line in page.components(separatedBy: .newlines)
                .map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
                context.textPosition = CGPoint(x: 40, y: y)
                let attributed = NSAttributedString(string: line, attributes: attributes)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
                y -= 28
            }
            context.endPDFPage()
        }
        context.closePDF()
    }
}
