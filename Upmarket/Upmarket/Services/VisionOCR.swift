import Foundation
import Vision
import PDFKit
import CoreImage
import NaturalLanguage

/// On-device OCR for scanned PDFs and images using Apple's Vision framework.
/// Zero download, no network, accelerated on Apple Silicon Neural Engine.
/// Replaces the Python OCR path for scanned documents.
struct VisionOCR {

    // MARK: - Output

    struct Result {
        let text: String
        let pageCount: Int
        let averageConfidence: Float
        let isLikelyScanned: Bool
        let detectedLanguages: [String]
    }

    struct PageResult {
        let pageIndex: Int
        let text: String
        let confidence: Float
        let observations: [VNRecognizedTextObservation]
    }

    // MARK: - Public API

    /// OCR a scanned PDF — renders each page to image then runs Vision.
    static func recognise(pdfURL: URL, password: String? = nil) async throws -> Result {
        guard let document = PDFDocument(url: pdfURL) else {
            throw OCRError.cannotOpenPDF
        }

        if document.isLocked {
            guard let pwd = password, document.unlock(withPassword: pwd) else {
                throw OCRError.passwordRequired
            }
        }

        let pageCount = document.pageCount
        var pageResults: [PageResult] = []

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let pageResult = try await recognisePage(page: page, index: i)
            pageResults.append(pageResult)
        }

        let fullText = pageResults
            .sorted { $0.pageIndex < $1.pageIndex }
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n---\n\n")

        let avgConfidence = pageResults.isEmpty ? 0 :
            pageResults.map(\.confidence).reduce(0, +) / Float(pageResults.count)

        let languages = Array(Set(pageResults.flatMap { extractLanguages($0.observations) }))

        return Result(
            text: fullText,
            pageCount: pageCount,
            averageConfidence: avgConfidence,
            isLikelyScanned: avgConfidence > 0.1,
            detectedLanguages: languages
        )
    }

    /// OCR a single image file (PNG, JPG, TIFF etc.)
    static func recognise(imageURL: URL) async throws -> Result {
        guard let ciImage = CIImage(contentsOf: imageURL) else {
            throw OCRError.cannotReadImage
        }

        let pageResult = try await recogniseCIImage(ciImage, pageIndex: 0)
        let languages = extractLanguages(pageResult.observations)

        return Result(
            text: pageResult.text,
            pageCount: 1,
            averageConfidence: pageResult.confidence,
            isLikelyScanned: true,
            detectedLanguages: languages
        )
    }

    // MARK: - Private

    private static func recognisePage(page: PDFPage, index: Int) async throws -> PageResult {
        // Render page to image at 150 DPI — good balance of quality vs speed
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 150.0 / 72.0   // PDF points are 72 DPI
        let width  = Int(bounds.width  * scale)
        let height = Int(bounds.height * scale)

        let renderer = PDFPageRenderer(page: page, width: width, height: height)
        guard let cgImage = renderer.render() else {
            return PageResult(pageIndex: index, text: "", confidence: 0, observations: [])
        }

        return try await recogniseCGImage(cgImage, pageIndex: index)
    }

    private static func recogniseCIImage(_ ciImage: CIImage, pageIndex: Int) async throws -> PageResult {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw OCRError.renderFailed
        }
        return try await recogniseCGImage(cgImage, pageIndex: pageIndex)
    }

    private static func recogniseCGImage(_ cgImage: CGImage, pageIndex: Int) async throws -> PageResult {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { obs -> String? in
                    guard let candidate = obs.topCandidates(1).first,
                          candidate.confidence > 0.3 else { return nil }
                    return candidate.string
                }

                let avgConf = observations.isEmpty ? 0 :
                    observations.compactMap { $0.topCandidates(1).first?.confidence }
                    .reduce(0, +) / Float(observations.count)

                continuation.resume(returning: PageResult(
                    pageIndex: pageIndex,
                    text: lines.joined(separator: "\n"),
                    confidence: avgConf,
                    observations: observations
                ))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Let Vision auto-detect language — supports 26+ languages
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func extractLanguages(_ observations: [VNRecognizedTextObservation]) -> [String] {
        // Vision doesn't expose per-observation language yet,
        // use NLLanguageRecognizer on the aggregated text
        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        guard !text.isEmpty else { return ["en"] }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 3)
            .filter { $0.value > 0.1 }
            .map { $0.key.rawValue }
    }

    // MARK: - Errors

    enum OCRError: LocalizedError {
        case cannotOpenPDF
        case passwordRequired
        case cannotReadImage
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .cannotOpenPDF:    return "Upmarket couldn't open this PDF."
            case .passwordRequired: return "This PDF is password-protected."
            case .cannotReadImage:  return "Upmarket couldn't read this image."
            case .renderFailed:     return "Upmarket couldn't process this page."
            }
        }
    }
}

// MARK: - PDF Page Renderer

/// Renders a PDFPage to a CGImage at a specified pixel size.
private struct PDFPageRenderer {
    let page: PDFPage
    let width: Int
    let height: Int

    func render() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // White background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale to fit
        let bounds = page.bounds(for: .mediaBox)
        let scaleX = CGFloat(width)  / bounds.width
        let scaleY = CGFloat(height) / bounds.height
        context.scaleBy(x: scaleX, y: scaleY)

        // Render PDF page into context
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        page.draw(with: .mediaBox, to: context)
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }
}
