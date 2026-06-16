import Foundation
import NaturalLanguage
import PDFKit

#if canImport(Vision)
import Vision
#endif

#if canImport(CoreML)
import CoreML
#endif

struct NativeDocumentClassifier {
    enum DocumentBucket: String, Equatable {
        case native = "native"
        case digitalComplex = "digital-complex"
        case scannedOrUnknown = "scanned-or-unknown"

        var diagnosticLabel: String { rawValue }
    }

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

    /// Engine for the complex/AI document path. Apple Vision is the Pure-Apple default —
    /// robust across scripts, handwriting, and the long tail, never catastrophic. Granite-
    /// Docling (native VLM via mlx-swift) is routed in only where it is measurably better:
    /// clean, typed, Latin / simplified-Chinese print documents. Validated on the
    /// OmniDocBench typed-document subset (Granite ≈ +5 pts there; ~0% on traditional
    /// Chinese / RTL / handwriting, where Vision wins).
    enum DocumentEngine: String, Equatable {
        case appleVision = "apple_vision"
        case graniteDoclingNative = "granite_docling_native"

        var diagnosticLabel: String { rawValue }
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
        let detectedLanguage: String?
        let languageConfidence: Double
        let detectedLanguages: [String]
        let hasMixedLanguages: Bool
        let sampledRotatedPages: Int
        let sampledLandscapePages: Int
        let sampledPagesRequiringRenderDownscale: Int
        let visionInspectedPages: Int
        let visionPagesWithText: Int
        let visionTextBoxCount: Int
        let visionEstimatedColumns: Int
        let visionDenseTextLayoutPages: Int
        let visionDocumentRectanglePages: Int
        let visionAverageDocumentSkewDegrees: Double

        init(
            pageCount: Int,
            sampledPages: Int,
            averageDigitalTextCharactersPerPage: Int,
            averageLinesPerSampledPage: Int,
            shortLineRatio: Double,
            numericLineRatio: Double,
            hasAxisLikeText: Bool,
            hasRTLText: Bool,
            hasTableLikeText: Bool,
            visionTextRecognitionAvailable: Bool,
            coreMLAvailable: Bool,
            visionObservedTextLines: Int,
            visionAverageConfidence: Float,
            detectedLanguage: String? = nil,
            languageConfidence: Double = 0,
            detectedLanguages: [String] = [],
            hasMixedLanguages: Bool = false,
            sampledRotatedPages: Int = 0,
            sampledLandscapePages: Int = 0,
            sampledPagesRequiringRenderDownscale: Int = 0,
            visionInspectedPages: Int = 0,
            visionPagesWithText: Int = -1,
            visionTextBoxCount: Int = 0,
            visionEstimatedColumns: Int = 1,
            visionDenseTextLayoutPages: Int = 0,
            visionDocumentRectanglePages: Int = 0,
            visionAverageDocumentSkewDegrees: Double = 0
        ) {
            self.pageCount = pageCount
            self.sampledPages = sampledPages
            self.averageDigitalTextCharactersPerPage = averageDigitalTextCharactersPerPage
            self.averageLinesPerSampledPage = averageLinesPerSampledPage
            self.shortLineRatio = shortLineRatio
            self.numericLineRatio = numericLineRatio
            self.hasAxisLikeText = hasAxisLikeText
            self.hasRTLText = hasRTLText
            self.hasTableLikeText = hasTableLikeText
            self.visionTextRecognitionAvailable = visionTextRecognitionAvailable
            self.coreMLAvailable = coreMLAvailable
            self.visionObservedTextLines = visionObservedTextLines
            self.visionAverageConfidence = visionAverageConfidence
            self.detectedLanguage = detectedLanguage
            self.languageConfidence = languageConfidence
            let languages = detectedLanguages.isEmpty ? detectedLanguage.map { [$0] } ?? [] : detectedLanguages
            self.detectedLanguages = languages
            self.hasMixedLanguages = hasMixedLanguages || Set(languages).count > 1
            self.sampledRotatedPages = sampledRotatedPages
            self.sampledLandscapePages = sampledLandscapePages
            self.sampledPagesRequiringRenderDownscale = sampledPagesRequiringRenderDownscale
            self.visionInspectedPages = visionInspectedPages
            self.visionPagesWithText = visionPagesWithText < 0 ? (visionObservedTextLines > 0 ? 1 : 0) : visionPagesWithText
            self.visionTextBoxCount = visionTextBoxCount
            self.visionEstimatedColumns = max(1, visionEstimatedColumns)
            self.visionDenseTextLayoutPages = visionDenseTextLayoutPages
            self.visionDocumentRectanglePages = visionDocumentRectanglePages
            self.visionAverageDocumentSkewDegrees = visionAverageDocumentSkewDegrees
        }

        var isLikelyScanned: Bool {
            averageDigitalTextCharactersPerPage < 80
                && visionTextRecognitionAvailable
                && visionPagesWithText > 0
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
                || hasVisionMultiColumnLayout
                || hasVisionDenseTextLayout
                || (averageLinesPerSampledPage > 45 && shortLineRatio > 0.45)
        }

        var hasVisionMultiColumnLayout: Bool {
            visionEstimatedColumns > 1
        }

        var hasVisionDenseTextLayout: Bool {
            visionDenseTextLayoutPages > 0
        }

        var hasCameraCapturedPage: Bool {
            visionDocumentRectanglePages > 0 || visionAverageDocumentSkewDegrees >= 2
        }

        var needsImageNormalization: Bool {
            sampledRotatedPages > 0
                || sampledPagesRequiringRenderDownscale > 0
                || hasCameraCapturedPage
        }

        var preprocessingHints: [String] {
            var hints: [String] = []
            if sampledPagesRequiringRenderDownscale > 0 { hints.append("bounded image render") }
            if sampledRotatedPages > 0 { hints.append("normalize page rotation") }
            if hasCameraCapturedPage { hints.append("crop or deskew document image") }
            if hasVisionMultiColumnLayout { hints.append("preserve multi-column layout") }
            if hasVisionDenseTextLayout { hints.append("inspect dense text layout") }
            if hasMixedLanguages { hints.append("preserve mixed-language text") }
            return hints
        }

        /// Scripts where Granite-Docling is validated/expected strong: Latin scripts and
        /// simplified Chinese. Traditional Chinese (`zh-Hant`), RTL, and other CJK go to
        /// Apple Vision. `detectedLanguage` is an NLLanguage raw value (e.g. "en",
        /// "zh-Hans", "zh-Hant").
        var isGraniteFriendlyScript: Bool {
            guard let lang = detectedLanguage?.lowercased() else { return false }
            if lang.hasPrefix("zh-hant") { return false }                 // traditional Chinese -> Vision
            if lang.hasPrefix("zh-hans") || lang == "zh" { return true }  // simplified Chinese (validated)
            // Latin-script languages (validated: en; others assumed Granite-friendly, expand as validated).
            let latin: Set<String> = ["en", "fr", "de", "es", "it", "pt", "nl", "sv", "da", "nb",
                                      "fi", "pl", "cs", "tr", "vi", "id", "ms", "ro", "hu", "hr", "ca"]
            return latin.contains { lang == $0 || lang.hasPrefix($0 + "-") }
        }

        /// Route to Granite-Docling (native) instead of Apple Vision. Granite wins on clean,
        /// typed, Latin/simplified-Chinese print; it fails on traditional Chinese, RTL, dense
        /// multi-column (newspapers), and low-confidence (handwriting/degraded) inputs — all of
        /// which fall through to Vision, the robust default.
        /// ponytail: handwriting is proxied by low Vision confidence at classify time — there is
        /// no dedicated pre-conversion handwriting signal yet; tighten when one lands.
        var isGraniteDoclingEligible: Bool {
            visionTextRecognitionAvailable
                && visionAverageConfidence >= 0.6        // degraded / handwriting proxy
                && !hasRTLText
                && !hasMixedLanguages
                && visionEstimatedColumns < 3            // newspapers / dense multi-column -> Vision
                && isGraniteFriendlyScript
        }
    }

    struct Classification: Equatable {
        let recommendedPathway: RecommendedPathway
        let confidence: Double
        let evidence: Evidence
        let reasons: [String]

        var bucket: DocumentBucket {
            switch recommendedPathway {
            case .pdfKit:
                return .native
            case .enhanced:
                return .digitalComplex
            case .visionOCR:
                return .scannedOrUnknown
            }
        }

        var shouldUseNativeFirst: Bool {
            recommendedPathway == .pdfKit || recommendedPathway == .visionOCR
        }

        /// Engine for the complex document path: Apple Vision by default; Granite-Docling
        /// (native) only when the classifier signals a clean typed Latin/simplified-Chinese
        /// document. Consumed by ConversionRunner once the native Granite engine is wired.
        var recommendedEngine: DocumentEngine {
            evidence.isGraniteDoclingEligible ? .graniteDoclingNative : .appleVision
        }

        var complexityAdvice: ComplexityAdvice {
            switch bucket {
            case .native:
                return ComplexityAdvice(
                    recommendation: .basic,
                    score: Int(confidence * 100),
                    reasons: reasons,
                    detectedLanguage: evidence.detectedLanguage
                )
            case .digitalComplex:
                return ComplexityAdvice(
                    recommendation: .aiRecommended,
                    score: Int(confidence * 100),
                    reasons: reasons,
                    detectedLanguage: evidence.detectedLanguage
                )
            case .scannedOrUnknown:
                return ComplexityAdvice(
                    recommendation: .aiRequired,
                    score: Int(confidence * 100),
                    reasons: reasons,
                    detectedLanguage: evidence.detectedLanguage
                )
            }
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

        let cheapInspection = inspectWithPDFKit(document: document, maximumSampledPages: maximumSampledPages)
        let vision = await inspectWithVision(samples: cheapInspection.samples, capabilities: capabilities)
        let evidence = makeEvidence(
            pageCount: cheapInspection.pageCount,
            samples: cheapInspection.samples,
            capabilities: capabilities,
            vision: vision
        )
        return recommend(from: evidence)
    }

    static func recommend(from evidence: Evidence) -> Classification {
        if evidence.isLikelyScanned {
            var reasons = ["low native text", "image text detected"]
            if evidence.needsImageNormalization {
                reasons.append("image normalization available")
            }
            return Classification(
                recommendedPathway: .visionOCR,
                confidence: 0.86,
                evidence: evidence,
                reasons: reasons
            )
        }

        if evidence.isLikelyComplexLayout {
            var reasons: [String] = []
            if evidence.hasTableLikeText { reasons.append("table-like text") }
            if evidence.hasRTLText { reasons.append("right-to-left text") }
            if evidence.hasVisionMultiColumnLayout { reasons.append("multi-column layout") }
            if evidence.hasVisionDenseTextLayout { reasons.append("dense text layout") }
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

    private struct CheapInspection {
        let pageCount: Int
        let samples: [PageSample]
    }

    private struct PagePreflight {
        let textCharacters: Int
        let lineCount: Int
        let detectedLanguage: String?
        let languageConfidence: Double
        let hasRTLText: Bool
        let isRotated: Bool
        let isLandscape: Bool
        let requiresRenderDownscale: Bool
    }

    private struct VisionInspection {
        let inspectedPages: Int
        let pagesWithText: Int
        let observedTextLines: Int
        let averageConfidence: Float
        let textBoxCount: Int
        let estimatedColumns: Int
        let denseTextLayoutPages: Int
        let documentRectanglePages: Int
        let averageDocumentSkewDegrees: Double

        static let unavailable = VisionInspection(
            inspectedPages: 0,
            pagesWithText: 0,
            observedTextLines: 0,
            averageConfidence: 0,
            textBoxCount: 0,
            estimatedColumns: 1,
            denseTextLayoutPages: 0,
            documentRectanglePages: 0,
            averageDocumentSkewDegrees: 0
        )

        init(results: [VisionPageInspection]) {
            guard !results.isEmpty else {
                self = .unavailable
                return
            }

            inspectedPages = results.count
            pagesWithText = results.filter { $0.observedTextLines > 0 }.count
            observedTextLines = results.reduce(0) { $0 + $1.observedTextLines }
            textBoxCount = results.reduce(0) { $0 + $1.textBoxCount }
            estimatedColumns = max(1, results.map(\.estimatedColumns).max() ?? 1)
            denseTextLayoutPages = results.filter(\.hasDenseTextLayout).count
            documentRectanglePages = results.filter(\.hasDocumentRectangle).count

            let confidences = results.filter { $0.averageConfidence > 0 }.map(\.averageConfidence)
            averageConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)

            let skew = results.compactMap(\.documentSkewDegrees)
            averageDocumentSkewDegrees = skew.isEmpty ? 0 : skew.reduce(0, +) / Double(skew.count)
        }

        private init(
            inspectedPages: Int,
            pagesWithText: Int,
            observedTextLines: Int,
            averageConfidence: Float,
            textBoxCount: Int,
            estimatedColumns: Int,
            denseTextLayoutPages: Int,
            documentRectanglePages: Int,
            averageDocumentSkewDegrees: Double
        ) {
            self.inspectedPages = inspectedPages
            self.pagesWithText = pagesWithText
            self.observedTextLines = observedTextLines
            self.averageConfidence = averageConfidence
            self.textBoxCount = textBoxCount
            self.estimatedColumns = estimatedColumns
            self.denseTextLayoutPages = denseTextLayoutPages
            self.documentRectanglePages = documentRectanglePages
            self.averageDocumentSkewDegrees = averageDocumentSkewDegrees
        }
    }

    private struct VisionPageInspection {
        let observedTextLines: Int
        let averageConfidence: Float
        let textBoxCount: Int
        let estimatedColumns: Int
        let hasDenseTextLayout: Bool
        let hasDocumentRectangle: Bool
        let documentSkewDegrees: Double?

        static let unavailable = VisionPageInspection(
            observedTextLines: 0,
            averageConfidence: 0,
            textBoxCount: 0,
            estimatedColumns: 1,
            hasDenseTextLayout: false,
            hasDocumentRectangle: false,
            documentSkewDegrees: nil
        )
    }

    private static func sampledPageIndexes(pageCount: Int, maximum: Int) -> [Int] {
        guard pageCount > 0, maximum > 0 else { return [] }
        let candidates = [0, pageCount / 2, pageCount - 1]
        return Array(NSOrderedSet(array: candidates).compactMap { $0 as? Int }.prefix(maximum))
    }

    private static func inspectWithPDFKit(document: PDFDocument, maximumSampledPages: Int) -> CheapInspection {
        let pageIndexes = sampledPageIndexes(pageCount: document.pageCount, maximum: maximumSampledPages)
        let samples = pageIndexes.compactMap { index -> PageSample? in
            guard let page = document.page(at: index) else { return nil }
            return PageSample(index: index, text: page.string ?? "", page: page)
        }
        return CheapInspection(pageCount: document.pageCount, samples: samples)
    }

    private static func makeEvidence(
        pageCount: Int,
        samples: [PageSample],
        capabilities: Capabilities,
        vision: VisionInspection
    ) -> Evidence {
        let pagePreflights = samples.map { preflight(page: $0) }
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
        let languageHypotheses = detectLanguageHypotheses(in: joined, maximum: 3)
        let language = languageHypotheses.first
        let pageLanguages = pagePreflights.compactMap(\.detectedLanguage)
        let detectedLanguages = uniqueLanguageCodes(pageLanguages + languageHypotheses.map { $0.code })
        let hasMixedLanguages = Set(pageLanguages).count > 1
            || languageHypotheses.dropFirst().contains { $0.confidence >= 0.15 }

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
            visionAverageConfidence: vision.averageConfidence,
            detectedLanguage: language?.code,
            languageConfidence: language?.confidence ?? 0,
            detectedLanguages: detectedLanguages,
            hasMixedLanguages: hasMixedLanguages,
            sampledRotatedPages: pagePreflights.filter(\.isRotated).count,
            sampledLandscapePages: pagePreflights.filter(\.isLandscape).count,
            sampledPagesRequiringRenderDownscale: pagePreflights.filter(\.requiresRenderDownscale).count,
            visionInspectedPages: vision.inspectedPages,
            visionPagesWithText: vision.pagesWithText,
            visionTextBoxCount: vision.textBoxCount,
            visionEstimatedColumns: vision.estimatedColumns,
            visionDenseTextLayoutPages: vision.denseTextLayoutPages,
            visionDocumentRectanglePages: vision.documentRectanglePages,
            visionAverageDocumentSkewDegrees: vision.averageDocumentSkewDegrees
        )
    }

    private static func preflight(page sample: PageSample) -> PagePreflight {
        let trimmedText = sample.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmedText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let language = detectLanguage(in: trimmedText)
        let bounds = sample.page.bounds(for: .mediaBox)
        let rotation = normalizedRotation(sample.page.rotation)

        return PagePreflight(
            textCharacters: trimmedText.count,
            lineCount: lines.count,
            detectedLanguage: language.code,
            languageConfidence: language.confidence,
            hasRTLText: containsRTLScript(trimmedText),
            isRotated: rotation != 0,
            isLandscape: bounds.width > bounds.height,
            requiresRenderDownscale: requiresRenderDownscale(bounds: bounds, dpi: 150)
        )
    }

    private static func uniqueLanguageCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for code in codes where seen.insert(code).inserted {
            result.append(code)
        }
        return result
    }

    private static func normalizedRotation(_ rotation: Int) -> Int {
        let normalized = rotation % 360
        return normalized >= 0 ? normalized : normalized + 360
    }

    private static func requiresRenderDownscale(bounds: CGRect, dpi: CGFloat) -> Bool {
        guard bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0 else { return false }

        let scale = dpi / 72.0
        let width = max(Int(bounds.width * scale), 1)
        let height = max(Int(bounds.height * scale), 1)
        let pixels = Double(width) * Double(height)
        return max(width, height) > VisionProcessingLimits.maximumRenderedSide
            || pixels > Double(VisionProcessingLimits.maximumRenderedPixels)
    }

    private static func detectLanguage(in text: String) -> (code: String?, confidence: Double) {
        guard let best = detectLanguageHypotheses(in: text, maximum: 1).first,
              best.confidence >= 0.20 else {
            return (nil, 0)
        }
        return (best.code, best.confidence)
    }

    private static func detectLanguageHypotheses(in text: String, maximum: Int) -> [(code: String, confidence: Double)] {
        let sample = String(text.prefix(4_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 20 else {
            return []
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.languageHypotheses(withMaximum: maximum)
            .map { (code: $0.key.rawValue, confidence: Double($0.value)) }
            .filter { $0.confidence >= 0.15 }
            .sorted { $0.confidence > $1.confidence }
    }

    private static func inspectWithVision(samples: [PageSample], capabilities: Capabilities) async -> VisionInspection {
        guard capabilities.visionTextRecognitionAvailable, !samples.isEmpty else {
            return .unavailable
        }

        #if canImport(Vision)
        var results: [VisionPageInspection] = []
        for sample in samples {
            if Task.isCancelled { break }
            guard let image = autoreleasepool(invoking: { render(page: sample.page) }) else { continue }
            results.append(await inspectTextAndLayout(in: image))
        }
        return VisionInspection(results: results)
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
    private static func inspectTextAndLayout(in image: CGImage) async -> VisionPageInspection {
        await withCheckedContinuation { continuation in
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .fast
            textRequest.usesLanguageCorrection = false
            if #available(macOS 13, *) {
                textRequest.automaticallyDetectsLanguage = true
            }

            let rectangleRequest = VNDetectRectanglesRequest()
            rectangleRequest.maximumObservations = 1
            rectangleRequest.minimumConfidence = 0.55

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([textRequest, rectangleRequest])
            } catch {
                continuation.resume(returning: VisionPageInspection.unavailable)
                return
            }

            let observations = textRequest.results ?? []
            let confidentObservations = observations.filter { observation in
                guard let candidate = observation.topCandidates(1).first else { return false }
                return candidate.confidence > 0.30
            }
            let confidences = observations.compactMap { $0.topCandidates(1).first?.confidence }
            let average = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)
            let boxes = confidentObservations.map(\.boundingBox)
            let rectangles = (rectangleRequest.results ?? []).filter { rectangleCoverage($0) >= 0.35 && rectangleCoverage($0) < 0.98 }
            let skew = rectangles.first.map { rectangleSkewDegrees($0) }

            continuation.resume(returning: VisionPageInspection(
                observedTextLines: confidentObservations.count,
                averageConfidence: average,
                textBoxCount: boxes.count,
                estimatedColumns: estimatedColumnCount(from: boxes),
                hasDenseTextLayout: hasDenseTextLayout(boxes: boxes),
                hasDocumentRectangle: !rectangles.isEmpty,
                documentSkewDegrees: skew
            ))
        }
    }

    private static func estimatedColumnCount(from boxes: [CGRect]) -> Int {
        guard boxes.count >= 10 else { return 1 }
        let centers = boxes
            .filter { $0.width > 0.03 && $0.height > 0.005 }
            .map(\.midX)
        let left = centers.filter { $0 < 0.45 }.count
        let right = centers.filter { $0 > 0.55 }.count
        return left >= 4 && right >= 4 ? 2 : 1
    }

    private static func hasDenseTextLayout(boxes: [CGRect]) -> Bool {
        guard boxes.count >= 25 else { return false }
        let averageHeight = boxes.reduce(0) { $0 + $1.height } / CGFloat(boxes.count)
        return boxes.count >= 45 || averageHeight < 0.018
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
    #endif

    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard let size = try? VisionProcessingLimits.renderSize(for: bounds, dpi: 96) else { return nil }
        let width = size.width
        let height = size.height
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
