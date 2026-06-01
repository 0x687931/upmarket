import Foundation
import PDFKit

#if canImport(Vision)
import Vision
#endif

#if canImport(CoreML)
import CoreML
#endif

struct NativeDocumentClassifier {
    enum RecommendedPathway: String, Equatable {
        case pdfKit = "pdfkit"
        case visionOCR = "vision_ocr"
        case enhanced = "enhanced"

        var diagnosticLabel: String {
            switch self {
            case .pdfKit: return "basic"
            case .visionOCR: return "image-text"
            case .enhanced: return "advanced"
            }
        }
    }

    struct Capabilities: Equatable {
        let visionTextRecognitionAvailable: Bool
        let coreMLAvailable: Bool

        nonisolated static var current: Capabilities {
            Capabilities(
                visionTextRecognitionAvailable: Self.detectVisionTextRecognition(),
                coreMLAvailable: Self.detectCoreML()
            )
        }

        nonisolated static let unavailable = Capabilities(
            visionTextRecognitionAvailable: false,
            coreMLAvailable: false
        )

        nonisolated private static func detectVisionTextRecognition() -> Bool {
            #if canImport(Vision)
            if #available(macOS 10.15, *) { return true }
            return false
            #else
            return false
            #endif
        }

        nonisolated private static func detectCoreML() -> Bool {
            #if canImport(CoreML)
            if #available(macOS 10.13, *) { return true }
            return false
            #else
            return false
            #endif
        }
    }

    struct Evidence: Equatable {
        let pageCount: Int
        let sampledPages: Int
        let averageDigitalTextCharactersPerPage: Int
        let averageLinesPerSampledPage: Int
        let shortLineRatio: Double
        let numericLineRatio: Double
        let hasAxisLikeText: Bool
        let hasRTLText: Bool
        let hasTableLikeText: Bool
        let visionTextRecognitionAvailable: Bool
        let coreMLAvailable: Bool
        let visionObservedTextLines: Int
        let visionAverageConfidence: Float

        var isLikelyScanned: Bool {
            averageDigitalTextCharactersPerPage < 80
                && visionTextRecognitionAvailable
                && visionObservedTextLines > 8
                && visionAverageConfidence > 0.35
        }

        var isLikelyFigureText: Bool {
            sampledPages > 0
                && averageLinesPerSampledPage <= 14
                && (numericLineRatio >= 0.35 || hasAxisLikeText)
        }

        var isLikelyComplexLayout: Bool {
            hasTableLikeText
                || hasRTLText
                || (averageLinesPerSampledPage > 45 && shortLineRatio > 0.45)
        }
    }

    struct Classification: Equatable {
        let recommendedPathway: RecommendedPathway
        let confidence: Double
        let evidence: Evidence
        let reasons: [String]

        var shouldUseNativeFirst: Bool {
            recommendedPathway == .pdfKit || recommendedPathway == .visionOCR
        }
    }

    enum ClassificationError: LocalizedError {
        case cannotOpenPDF
        case passwordRequired

        var errorDescription: String? {
            switch self {
            case .cannotOpenPDF:
                return "Upmarket couldn't open this PDF."
            case .passwordRequired:
                return "This PDF is password-protected."
            }
        }
    }

    static func classify(
        pdfURL: URL,
        password: String? = nil,
        capabilities: Capabilities = .current,
        maximumSampledPages: Int = 3
    ) async throws -> Classification {
        guard let document = PDFDocument(url: pdfURL) else {
            throw ClassificationError.cannotOpenPDF
        }
        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else {
                throw ClassificationError.passwordRequired
            }
        }

        let pageIndexes = sampledPageIndexes(pageCount: document.pageCount, maximum: maximumSampledPages)
        let samples = pageIndexes.compactMap { index -> PageSample? in
            guard let page = document.page(at: index) else { return nil }
            return PageSample(index: index, text: page.string ?? "", page: page)
        }

        let vision = await inspectWithVision(samples: samples, capabilities: capabilities)
        let evidence = makeEvidence(
            pageCount: document.pageCount,
            samples: samples,
            capabilities: capabilities,
            vision: vision
        )
        return recommend(from: evidence)
    }

    static func recommend(from evidence: Evidence) -> Classification {
        if evidence.isLikelyScanned {
            return Classification(
                recommendedPathway: .visionOCR,
                confidence: 0.86,
                evidence: evidence,
                reasons: ["low native text", "image text detected"]
            )
        }

        if evidence.isLikelyComplexLayout {
            var reasons: [String] = []
            if evidence.hasTableLikeText { reasons.append("table-like text") }
            if evidence.hasRTLText { reasons.append("right-to-left text") }
            if evidence.averageLinesPerSampledPage > 45 && evidence.shortLineRatio > 0.45 {
                reasons.append("dense multi-column layout")
            }
            return Classification(
                recommendedPathway: .enhanced,
                confidence: 0.78,
                evidence: evidence,
                reasons: reasons
            )
        }

        if evidence.isLikelyFigureText {
            return Classification(
                recommendedPathway: .pdfKit,
                confidence: 0.74,
                evidence: evidence,
                reasons: ["short figure text"]
            )
        }

        return Classification(
            recommendedPathway: .pdfKit,
            confidence: 0.70,
            evidence: evidence,
            reasons: ["digital text"]
        )
    }

    private struct PageSample {
        let index: Int
        let text: String
        let page: PDFPage
    }

    private struct VisionInspection {
        let observedTextLines: Int
        let averageConfidence: Float

        static let unavailable = VisionInspection(observedTextLines: 0, averageConfidence: 0)
    }

    private static func sampledPageIndexes(pageCount: Int, maximum: Int) -> [Int] {
        guard pageCount > 0, maximum > 0 else { return [] }
        let candidates = [0, pageCount / 2, pageCount - 1]
        return Array(NSOrderedSet(array: candidates).compactMap { $0 as? Int }.prefix(maximum))
    }

    private static func makeEvidence(
        pageCount: Int,
        samples: [PageSample],
        capabilities: Capabilities,
        vision: VisionInspection
    ) -> Evidence {
        let sampledTexts = samples.map(\.text)
        let lines = sampledTexts.flatMap {
            $0.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let sampledPageCount = max(samples.count, 1)
        let totalCharacters = sampledTexts.reduce(0) { $0 + $1.trimmingCharacters(in: .whitespacesAndNewlines).count }
        let shortLines = lines.filter { $0.count <= 32 }.count
        let numericLines = lines.filter {
            $0.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil
        }.count
        let tableLikeLines = lines.filter {
            $0.contains("|")
                || $0.contains("\t")
                || $0.range(of: #"\S\s{2,}\S\s{2,}\S"#, options: .regularExpression) != nil
        }.count
        let joined = lines.joined(separator: " ")

        return Evidence(
            pageCount: pageCount,
            sampledPages: samples.count,
            averageDigitalTextCharactersPerPage: totalCharacters / sampledPageCount,
            averageLinesPerSampledPage: lines.count / sampledPageCount,
            shortLineRatio: lines.isEmpty ? 0 : Double(shortLines) / Double(lines.count),
            numericLineRatio: lines.isEmpty ? 0 : Double(numericLines) / Double(lines.count),
            hasAxisLikeText: joined.contains("[") || joined.contains("]") || joined.contains("/") || joined.contains("MeV"),
            hasRTLText: containsRTLScript(joined),
            hasTableLikeText: tableLikeLines >= 2,
            visionTextRecognitionAvailable: capabilities.visionTextRecognitionAvailable,
            coreMLAvailable: capabilities.coreMLAvailable,
            visionObservedTextLines: vision.observedTextLines,
            visionAverageConfidence: vision.averageConfidence
        )
    }

    private static func inspectWithVision(samples: [PageSample], capabilities: Capabilities) async -> VisionInspection {
        guard capabilities.visionTextRecognitionAvailable, let first = samples.first else {
            return .unavailable
        }

        #if canImport(Vision)
        guard let image = render(page: first.page) else { return .unavailable }
        return await recogniseText(in: image)
        #else
        return .unavailable
        #endif
    }

    private static func containsRTLScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x0590...0x05FF).contains(scalar.value)
                || (0x0600...0x06FF).contains(scalar.value)
                || (0x0750...0x077F).contains(scalar.value)
                || (0x08A0...0x08FF).contains(scalar.value)
        }
    }

    #if canImport(Vision)
    private static func recogniseText(in image: CGImage) async -> VisionInspection {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let confidences = observations.compactMap { $0.topCandidates(1).first?.confidence }
                let average = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)
                continuation.resume(returning: VisionInspection(
                    observedTextLines: observations.count,
                    averageConfidence: average
                ))
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                continuation.resume(returning: .unavailable)
            }
        }
    }
    #endif

    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 96.0 / 72.0
        let width = max(Int(bounds.width * scale), 1)
        let height = max(Int(bounds.height * scale), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        page.draw(with: .mediaBox, to: context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
