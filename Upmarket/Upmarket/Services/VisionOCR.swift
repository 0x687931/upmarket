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
        let handwritingRatio: Double  // 0.0-1.0, portion of document with handwriting
        let containsSignificantHandwriting: Bool  // True if > 30% handwriting detected
    }

    struct PageResult {
        let pageIndex: Int
        let text: String
        let confidence: Float
        let observations: [VNRecognizedTextObservation]
        let handwritingConfidence: Float
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
        try VisionProcessingLimits.validatePageCount(pageCount)

        var pageTexts: [String] = []
        var confidenceSum: Float = 0
        var confidenceCount = 0
        var handwritingSum: Float = 0
        var handwritingCount = 0
        var languageSet = Set<String>()
        for i in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: i) else { continue }
            let pageResult = try await recognisePage(page: page, index: i)
            let text = pageResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                pageTexts.append(text)
            }
            if pageResult.confidence > 0 {
                confidenceSum += pageResult.confidence
                confidenceCount += 1
            }
            if pageResult.handwritingConfidence > 0 {
                handwritingSum += pageResult.handwritingConfidence
                handwritingCount += 1
            }
            languageSet.formUnion(extractLanguages(pageResult.observations))
        }

        let fullText = pageTexts.joined(separator: "\n\n---\n\n")
        let avgConfidence = confidenceCount == 0 ? 0 : confidenceSum / Float(confidenceCount)
        let handwritingRatio = handwritingCount == 0 ? 0.0 : Double(handwritingSum) / Double(handwritingCount)
        let containsSignificantHandwriting = handwritingRatio > 0.30

        return Result(
            text: fullText,
            pageCount: pageCount,
            averageConfidence: avgConfidence,
            isLikelyScanned: avgConfidence > 0.1,
            detectedLanguages: Array(languageSet).sorted(),
            handwritingRatio: handwritingRatio,
            containsSignificantHandwriting: containsSignificantHandwriting
        )
    }

    /// OCR a single image file (PNG, JPG, TIFF etc.)
    static func recognise(imageURL: URL) async throws -> Result {
        guard let ciImage = CIImage(contentsOf: imageURL) else {
            throw OCRError.cannotReadImage
        }
        try VisionProcessingLimits.validateImagePixels(
            width: Int(ciImage.extent.width),
            height: Int(ciImage.extent.height)
        )

        let pageResult = try await recogniseCIImage(ciImage, pageIndex: 0)
        let languages = extractLanguages(pageResult.observations)

        return Result(
            text: pageResult.text,
            pageCount: 1,
            averageConfidence: pageResult.confidence,
            isLikelyScanned: true,
            detectedLanguages: languages,
            handwritingRatio: Double(pageResult.handwritingConfidence),
            containsSignificantHandwriting: pageResult.handwritingConfidence > 0.30
        )
    }

    // MARK: - Private

    private static func recognisePage(page: PDFPage, index: Int) async throws -> PageResult {
        let bounds = page.bounds(for: .mediaBox)
        let size = try VisionProcessingLimits.renderSize(for: bounds, dpi: 150)

        let renderer = PDFPageRenderer(page: page, width: size.width, height: size.height)
        guard let cgImage = autoreleasepool(invoking: { renderer.render() }) else {
            return PageResult(pageIndex: index, text: "", confidence: 0, observations: [], handwritingConfidence: 0)
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
        let preparedImage = await preprocessedImageForOCR(cgImage) ?? cgImage
        return try await recognisePreparedCGImage(preparedImage, pageIndex: pageIndex)
    }

    static func preprocessedImageForOCR(_ cgImage: CGImage) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 1
            request.minimumConfidence = 0.60

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
                return
            }

            guard let rectangle = request.results?.first else {
                continuation.resume(returning: nil)
                return
            }
            let coverage = rectangleCoverage(rectangle)
            let skew = rectangleSkewDegrees(rectangle)
            guard coverage >= 0.35,
                  coverage < 0.96,
                  coverage < 0.90 || skew >= 2 else {
                continuation.resume(returning: nil)
                return
            }

            continuation.resume(returning: perspectiveCorrectedImage(from: cgImage, rectangle: rectangle))
        }
    }

    private static func recognisePreparedCGImage(_ cgImage: CGImage, pageIndex: Int) async throws -> PageResult {
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

                // Estimate handwriting confidence from text characteristics
                let handwritingConfidence = estimateHandwritingConfidence(observations: observations)

                continuation.resume(returning: PageResult(
                    pageIndex: pageIndex,
                    text: lines.joined(separator: "\n"),
                    confidence: avgConf,
                    observations: observations,
                    handwritingConfidence: handwritingConfidence
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

    /// Estimate handwriting confidence from text observations.
    /// Handwritten text typically has lower confidence and more variation in character spacing.
    private static func estimateHandwritingConfidence(observations: [VNRecognizedTextObservation]) -> Float {
        guard !observations.isEmpty else { return 0 }

        // Collect confidence scores
        let confidences = observations.compactMap { $0.topCandidates(1).first?.confidence }
        guard !confidences.isEmpty else { return 0 }

        // Handwriting typically has:
        // 1. Lower average confidence (< 0.70)
        // 2. High variance in confidence (inconsistent letter recognition)
        let avgConfidence = confidences.reduce(0, +) / Float(confidences.count)
        let variance = confidences.reduce(0) { sum, conf in
            sum + pow((conf - avgConfidence) * (conf - avgConfidence), 0.5)
        } / Float(confidences.count)

        // Handwriting score: penalize low confidence, reward high variance
        var handwritingScore: Float = 0

        if avgConfidence < 0.70 {
            handwritingScore += (0.70 - avgConfidence) * 0.5  // Penalty for low confidence
        }

        if variance > 0.15 {
            handwritingScore += min(variance, 0.5) * 0.5  // Reward for high variance
        }

        // Clamp to 0.0-1.0
        return min(max(handwritingScore, 0), 1.0)
    }

    private static func perspectiveCorrectedImage(from cgImage: CGImage, rectangle: VNRectangleObservation) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }

        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: imagePoint(rectangle.topLeft, extent: input.extent)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: imagePoint(rectangle.topRight, extent: input.extent)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: imagePoint(rectangle.bottomLeft, extent: input.extent)), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: imagePoint(rectangle.bottomRight, extent: input.extent)), forKey: "inputBottomRight")

        guard let output = filter.outputImage,
              output.extent.width > 1,
              output.extent.height > 1 else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    private static func imagePoint(_ point: CGPoint, extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + point.x * extent.width,
            y: extent.minY + point.y * extent.height
        )
    }

    private static func rectangleCoverage(_ rectangle: VNRectangleObservation) -> CGFloat {
        let points = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
        var area: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            area += points[index].x * next.y - next.x * points[index].y
        }
        return abs(area) / 2
    }

    private static func rectangleSkewDegrees(_ rectangle: VNRectangleObservation) -> Double {
        let radians = atan2(rectangle.topRight.y - rectangle.topLeft.y, rectangle.topRight.x - rectangle.topLeft.x)
        let degrees = abs(Double(radians * 180 / .pi))
        return min(degrees, abs(180 - degrees))
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
