import AppKit
import CoreText
import PDFKit
import XCTest
@testable import Upmarket

final class DocumentChunkerTests: XCTestCase {
    func testChunkingUnlocksPasswordProtectedPDFs() throws {
        let plainURL = temporaryPDFURL(suffix: "plain")
        let encryptedURL = temporaryPDFURL(suffix: "encrypted")
        try writePDF(
            to: plainURL,
            pages: [
                "Chunk one",
                "Chunk two"
            ]
        )
        defer {
            try? FileManager.default.removeItem(at: plainURL)
            try? FileManager.default.removeItem(at: encryptedURL)
        }

        guard let document = PDFDocument(url: plainURL) else {
            return XCTFail("Could not reopen generated PDF")
        }
        let options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: "secret",
            .userPasswordOption: "secret"
        ]
        XCTAssertTrue(document.write(to: encryptedURL, withOptions: options))

        XCTAssertThrowsError(
            try DocumentChunker.chunk(pdfURL: encryptedURL, maxPages: 1)
        ) { error in
            guard case DocumentChunker.ChunkingError.passwordRequired = error else {
                return XCTFail("Expected passwordRequired, got \(error)")
            }
        }

        let chunks = try DocumentChunker.chunk(pdfURL: encryptedURL, password: "secret", maxPages: 1)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].pageCount, 1)
        XCTAssertEqual(chunks[1].pageCount, 1)
    }

    private func temporaryPDFURL(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("upmarket-documentchunker-\(suffix)-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
    }

    private func writePDF(
        to url: URL,
        pages: [String],
        mediaBox: CGRect = CGRect(x: 0, y: 0, width: 500, height: 320)
    ) throws {
        var pageBox = mediaBox
        guard let context = CGContext(url as CFURL, mediaBox: &pageBox, nil) else {
            throw NSError(domain: "DocumentChunkerTests", code: 1)
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
