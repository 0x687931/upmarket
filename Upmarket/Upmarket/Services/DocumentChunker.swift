import Foundation
import PDFKit

/// Splits large PDF documents into Vision-safe chunks.
/// Vision's RecognizeDocumentsRequest has a page limit (~20-30 pages).
/// For larger PDFs, chunk them for processing or fall back to Docling.
struct DocumentChunker {

    enum ChunkingError: LocalizedError {
        case cannotOpenPDF
        case emptyPDF
        case invalidPageRange
        case passwordRequired

        var errorDescription: String? {
            switch self {
            case .cannotOpenPDF:
                return "Could not open PDF document."
            case .emptyPDF:
                return "PDF has no pages."
            case .invalidPageRange:
                return "Invalid page range for chunking."
            case .passwordRequired:
                return "This PDF is password-protected."
            }
        }
    }

    /// Represents a chunk of a PDF document
    struct Chunk {
        /// Index of first page in original PDF (0-based)
        let startPageIndex: Int
        /// Index of last page in original PDF (inclusive, 0-based)
        let endPageIndex: Int
        /// Pages in this chunk
        let pages: [PDFPage]
        /// True if this is the final chunk
        let isLast: Bool

        var pageCount: Int { pages.count }
        var pageRange: String { "\(startPageIndex + 1)-\(endPageIndex + 1)" }
    }

    /// Maximum pages per chunk (Vision's limit is ~20-30; use conservative default)
    static let defaultChunkSize = 20

    /// Check if PDF needs chunking for Vision processing
    /// Returns true if page count exceeds the vision-safe limit
    static func needsChunking(_ pdfURL: URL, maxPages: Int = defaultChunkSize) -> Bool {
        guard let document = PDFDocument(url: pdfURL) else { return false }
        return document.pageCount > maxPages
    }

    /// Check if document page count exceeds vision-safe limit
    static func needsChunking(pageCount: Int, maxPages: Int = defaultChunkSize) -> Bool {
        pageCount > maxPages
    }

    /// Chunk a PDF into vision-safe pieces
    ///
    /// - Parameters:
    ///   - pdfURL: URL to the PDF document
    ///   - maxPages: Maximum pages per chunk (default: 20, safe for Vision API)
    ///
    /// - Returns: Array of chunks; if PDF is smaller than maxPages, returns single chunk
    /// - Throws: ChunkingError if PDF cannot be opened or is empty
    static func chunk(
        pdfURL: URL,
        password: String? = nil,
        maxPages: Int = defaultChunkSize
    ) throws -> [Chunk] {
        guard let document = PDFDocument(url: pdfURL) else {
            throw ChunkingError.cannotOpenPDF
        }

        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else {
                throw ChunkingError.passwordRequired
            }
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw ChunkingError.emptyPDF }

        // If small enough, return as single chunk
        if pageCount <= maxPages {
            let pages = (0..<pageCount).compactMap { document.page(at: $0) }
            return [Chunk(startPageIndex: 0, endPageIndex: pageCount - 1, pages: pages, isLast: true)]
        }

        // Split into chunks
        var chunks: [Chunk] = []
        var startIndex = 0

        while startIndex < pageCount {
            let endIndex = min(startIndex + maxPages - 1, pageCount - 1)
            let chunkSize = endIndex - startIndex + 1

            let pages = (startIndex...endIndex).compactMap { document.page(at: $0) }
            guard pages.count == chunkSize else {
                throw ChunkingError.invalidPageRange
            }

            let isLast = endIndex == pageCount - 1
            chunks.append(
                Chunk(
                    startPageIndex: startIndex,
                    endPageIndex: endIndex,
                    pages: pages,
                    isLast: isLast
                )
            )

            startIndex = endIndex + 1
        }

        return chunks
    }

    /// Extract metadata about chunking
    struct ChunkingMetadata {
        /// Total pages in original document
        let totalPages: Int
        /// Number of chunks
        let chunkCount: Int
        /// Pages per chunk
        let chunkSize: Int
        /// True if chunking was applied (totalPages > chunkSize)
        let wasChunked: Bool

        init(totalPages: Int, chunkCount: Int, chunkSize: Int = defaultChunkSize) {
            self.totalPages = totalPages
            self.chunkCount = chunkCount
            self.chunkSize = chunkSize
            self.wasChunked = chunkCount > 1
        }
    }

    /// Get metadata about chunking for a given page count
    static func analyzeChunking(pageCount: Int, chunkSize: Int = defaultChunkSize) -> ChunkingMetadata {
        let chunkCount = (pageCount + chunkSize - 1) / chunkSize
        return ChunkingMetadata(totalPages: pageCount, chunkCount: chunkCount, chunkSize: chunkSize)
    }
}
