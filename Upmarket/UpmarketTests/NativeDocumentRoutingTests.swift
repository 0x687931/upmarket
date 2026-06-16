import XCTest
@testable import Upmarket

/// The classify-then-route rules: Apple Vision is the default; Granite-Docling (native) is
/// routed in ONLY for clean, typed, Latin/simplified-Chinese print documents. Validated
/// failure modes (traditional Chinese, RTL, dense multi-column, low-confidence/handwriting)
/// must fall through to Vision.
final class NativeDocumentRoutingTests: XCTestCase {

    /// A clean, typed, high-confidence English document; override one field per test.
    private func evidence(
        lang: String? = "en",
        langs: [String] = [],
        rtl: Bool = false,
        confidence: Float = 0.9,
        columns: Int = 1,
        visionAvailable: Bool = true
    ) -> NativeDocumentClassifier.Evidence {
        NativeDocumentClassifier.Evidence(
            pageCount: 1, sampledPages: 1, averageDigitalTextCharactersPerPage: 2000,
            averageLinesPerSampledPage: 30, shortLineRatio: 0.2, numericLineRatio: 0.1,
            hasAxisLikeText: false, hasRTLText: rtl, hasTableLikeText: false,
            visionTextRecognitionAvailable: visionAvailable, coreMLAvailable: true,
            visionObservedTextLines: 30, visionAverageConfidence: confidence,
            detectedLanguage: lang, detectedLanguages: langs,
            visionEstimatedColumns: columns)
    }

    private func engine(_ e: NativeDocumentClassifier.Evidence) -> NativeDocumentClassifier.DocumentEngine {
        NativeDocumentClassifier.Classification(
            recommendedPathway: .enhanced, confidence: 1, evidence: e, reasons: []
        ).recommendedEngine
    }

    func testCleanTypedRoutesToGranite() {
        XCTAssertEqual(engine(evidence(lang: "en")), .graniteDoclingNative)
        XCTAssertEqual(engine(evidence(lang: "zh-Hans")), .graniteDoclingNative)   // simplified Chinese
        XCTAssertEqual(engine(evidence(lang: "fr")), .graniteDoclingNative)
    }

    func testFailureModesRouteToVision() {
        XCTAssertEqual(engine(evidence(lang: "zh-Hant")), .appleVision)            // traditional Chinese
        XCTAssertEqual(engine(evidence(lang: "ja")), .appleVision)                 // unvalidated CJK
        XCTAssertEqual(engine(evidence(lang: "en", rtl: true)), .appleVision)      // RTL
        XCTAssertEqual(engine(evidence(langs: ["en", "ja"])), .appleVision)        // mixed languages
        XCTAssertEqual(engine(evidence(lang: "en", columns: 3)), .appleVision)     // newspaper / dense
        XCTAssertEqual(engine(evidence(lang: "en", confidence: 0.4)), .appleVision) // handwriting/degraded proxy
        XCTAssertEqual(engine(evidence(lang: nil)), .appleVision)                  // unknown script
        XCTAssertEqual(engine(evidence(lang: "en", visionAvailable: false)), .appleVision)
    }
}
