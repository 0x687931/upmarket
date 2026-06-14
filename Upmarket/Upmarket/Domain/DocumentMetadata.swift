import Foundation

/// Metadata extracted during document processing.
struct DocumentMetadata: Codable, Equatable, Sendable {
    /// Apple's semantic document type (form, receipt, invoice, document, etc.)
    /// Only available when using Vision's RecognizeDocumentsRequest (macOS 26+)
    let elementType: String?

    /// Detected language code (e.g., "en", "fr")
    let language: String?

    /// Method used for extraction: "pdfkit", "vision", "vision-ocr", "docling"
    let extractionMethod: String

    /// Confidence in the extraction (0.0 to 1.0)
    let extractionConfidence: Double

    /// True if document contains significant handwritten content
    let containsHandwriting: Bool

    /// Estimated ratio of handwritten vs. printed text (0.0 to 1.0)
    let handwritingRatio: Double

    init(
        elementType: String? = nil,
        language: String? = nil,
        extractionMethod: String = "unknown",
        extractionConfidence: Double = 0.8,
        containsHandwriting: Bool = false,
        handwritingRatio: Double = 0.0
    ) {
        self.elementType = elementType
        self.language = language
        self.extractionMethod = extractionMethod
        self.extractionConfidence = extractionConfidence
        self.containsHandwriting = containsHandwriting
        self.handwritingRatio = handwritingRatio
    }

    /// Default metadata for documents without special processing
    static let `default` = DocumentMetadata()

    /// Metadata for PDFKit extraction
    static func pdfkit(language: String? = nil) -> DocumentMetadata {
        DocumentMetadata(
            language: language,
            extractionMethod: "pdfkit",
            extractionConfidence: 0.95
        )
    }

    /// Metadata for Vision OCR extraction
    static func visionOCR(
        language: String? = nil,
        handwriting: Bool = false,
        handwritingRatio: Double = 0.0
    ) -> DocumentMetadata {
        DocumentMetadata(
            language: language,
            extractionMethod: "vision-ocr",
            extractionConfidence: 0.75,
            containsHandwriting: handwriting,
            handwritingRatio: handwritingRatio
        )
    }

    /// Metadata for Vision Document Extractor (macOS 26+)
    static func visionDocuments(
        elementType: String? = nil,
        language: String? = nil
    ) -> DocumentMetadata {
        DocumentMetadata(
            elementType: elementType,
            language: language,
            extractionMethod: "vision",
            extractionConfidence: 0.85
        )
    }

    /// Metadata for the in-process native HTML converter
    static func nativeHTML(language: String? = nil) -> DocumentMetadata {
        DocumentMetadata(
            language: language,
            extractionMethod: "native-html",
            extractionConfidence: 0.9
        )
    }

    /// Metadata for Docling extraction
    static func docling(language: String? = nil) -> DocumentMetadata {
        DocumentMetadata(
            language: language,
            extractionMethod: "docling",
            extractionConfidence: 0.88
        )
    }
}
