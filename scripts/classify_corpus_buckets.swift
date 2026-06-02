#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

struct CorpusManifest: Decodable {
    let documents: [CorpusDocument]
}

struct CorpusDocument: Decodable {
    let id: String
    let file: String
    let category: String
    let format: String
}

struct ClassificationReport: Encodable {
    let version: Int
    let manifest: String
    let generatedAt: String
    let classifier: String
    let summary: Summary
    let documents: [DocumentResult]
}

struct Summary: Encodable {
    let total: Int
    let buckets: [String: Int]
    let recommendations: [String: Int]
    let errors: Int
}

struct DocumentResult: Encodable {
    let id: String
    let file: String
    let category: String
    let format: String
    let bucket: String
    let recommendation: String
    let confidence: Double
    let reasons: [String]
    let evidence: Evidence?
    let error: String?
}

struct Evidence: Encodable {
    let pageCount: Int?
    let sampledPages: Int?
    let averageDigitalTextCharactersPerPage: Int
    let averageLinesPerSampledPage: Int
    let shortLineRatio: Double
    let numericLineRatio: Double
    let hasAxisLikeText: Bool
    let hasRTLText: Bool
    let hasTableLikeText: Bool
    let visionObservedTextLines: Int
    let visionAverageConfidence: Float
}

enum Bucket: String {
    case native
    case digitalComplex = "digital-complex"
    case scannedOrUnknown = "scanned-or-unknown"
    case blocked
}

enum Recommendation: String {
    case native
    case enhanced
    case imageText = "image-text"
    case blocked
}

struct Classification {
    let bucket: Bucket
    let recommendation: Recommendation
    let confidence: Double
    let reasons: [String]
    let evidence: Evidence?
}

let arguments = Array(CommandLine.arguments.dropFirst())
let manifestPath = value(after: "--manifest", in: arguments) ?? "tests/corpus/manifest.json"
let outputPath = value(after: "--output", in: arguments) ?? "reports/corpus-bucket-classification.json"
let manifestURL = URL(fileURLWithPath: manifestPath)
let corpusRoot = manifestURL.deletingLastPathComponent()
let manifest = try JSONDecoder().decode(CorpusManifest.self, from: Data(contentsOf: manifestURL))

var results: [DocumentResult] = []
for document in manifest.documents {
    let fileURL = resolve(document.file, corpusRoot: corpusRoot)
    do {
        let classification = try classify(document: document, fileURL: fileURL)
        results.append(DocumentResult(
            id: document.id,
            file: document.file,
            category: document.category,
            format: document.format,
            bucket: classification.bucket.rawValue,
            recommendation: classification.recommendation.rawValue,
            confidence: classification.confidence,
            reasons: classification.reasons,
            evidence: classification.evidence,
            error: nil
        ))
    } catch {
        results.append(DocumentResult(
            id: document.id,
            file: document.file,
            category: document.category,
            format: document.format,
            bucket: Bucket.blocked.rawValue,
            recommendation: Recommendation.blocked.rawValue,
            confidence: 0,
            reasons: [],
            evidence: nil,
            error: String(describing: error)
        ))
    }
}

let summary = Summary(
    total: results.count,
    buckets: count(results.map(\.bucket)),
    recommendations: count(results.map(\.recommendation)),
    errors: results.filter { $0.error != nil }.count
)
let report = ClassificationReport(
    version: 1,
    manifest: manifestPath,
    generatedAt: ISO8601DateFormatter().string(from: Date()),
    classifier: "Apple native preflight: PDFKit + Vision; ImageIO/AVFoundation/Speech category routing for non-PDFs",
    summary: summary,
    documents: results
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try encoder.encode(report).write(to: outputURL)

print("classified \(summary.total) documents")
print("buckets: \(summary.buckets)")
print("recommendations: \(summary.recommendations)")
print("errors: \(summary.errors)")
print("wrote \(outputPath)")

func classify(document: CorpusDocument, fileURL: URL) throws -> Classification {
    let ext = fileURL.pathExtension.lowercased()
    switch ext {
    case "pdf":
        return try classifyPDF(fileURL)
    case "png", "jpg", "jpeg", "tif", "tiff", "webp", "bmp", "gif":
        return classifyImage(fileURL)
    case "mp3", "m4a", "wav", "aiff", "opus", "flac", "aac", "mp4", "mov", "avi":
        return Classification(
            bucket: .native,
            recommendation: .native,
            confidence: 0.72,
            reasons: ["native media metadata/transcription route"],
            evidence: nil
        )
    case "csv", "json", "xml", "html", "htm", "epub", "docx", "doc", "pptx", "ppt", "xlsx", "xls", "asciidoc", "md", "vtt":
        return Classification(
            bucket: .digitalComplex,
            recommendation: .enhanced,
            confidence: 0.66,
            reasons: ["structured digital document"],
            evidence: nil
        )
    default:
        return Classification(
            bucket: .scannedOrUnknown,
            recommendation: .imageText,
            confidence: 0.40,
            reasons: ["unknown format"],
            evidence: nil
        )
    }
}

func classifyPDF(_ fileURL: URL) throws -> Classification {
    guard let document = PDFDocument(url: fileURL) else {
        throw NSError(domain: "CorpusClassifier", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open PDF"])
    }
    if document.isLocked {
        throw NSError(domain: "CorpusClassifier", code: 2, userInfo: [NSLocalizedDescriptionKey: "password required"])
    }

    let indexes = sampledPageIndexes(pageCount: document.pageCount, maximum: 3)
    let samples: [(text: String, page: PDFPage)] = indexes.compactMap { index in
        guard let page = document.page(at: index) else { return nil }
        return (page.string ?? "", page)
    }
    let vision = inspectPDFPagesWithVision(samples.map(\.page))
    let evidence = makeEvidence(
        pageCount: document.pageCount,
        sampledPages: samples.count,
        sampledTexts: samples.map(\.text),
        vision: vision
    )
    return recommend(from: evidence)
}

func classifyImage(_ fileURL: URL) -> Classification {
    let vision = inspectImageWithVision(fileURL)
    let evidence = Evidence(
        pageCount: nil,
        sampledPages: nil,
        averageDigitalTextCharactersPerPage: 0,
        averageLinesPerSampledPage: vision.lines,
        shortLineRatio: 0,
        numericLineRatio: 0,
        hasAxisLikeText: false,
        hasRTLText: false,
        hasTableLikeText: false,
        visionObservedTextLines: vision.lines,
        visionAverageConfidence: vision.confidence
    )
    return Classification(
        bucket: .scannedOrUnknown,
        recommendation: .imageText,
        confidence: vision.lines > 3 && vision.confidence > 0.25 ? 0.82 : 0.58,
        reasons: vision.lines > 3 && vision.confidence > 0.25
            ? ["image text detected"]
            : ["image-only or unknown document"],
        evidence: evidence
    )
}

func recommend(from evidence: Evidence) -> Classification {
    if evidence.averageDigitalTextCharactersPerPage < 80,
       evidence.visionObservedTextLines > 8,
       evidence.visionAverageConfidence > 0.35 {
        return Classification(
            bucket: .scannedOrUnknown,
            recommendation: .imageText,
            confidence: 0.86,
            reasons: ["low native text", "image text detected"],
            evidence: evidence
        )
    }

    if evidence.averageDigitalTextCharactersPerPage < 80,
       evidence.visionObservedTextLines == 0 {
        return Classification(
            bucket: .scannedOrUnknown,
            recommendation: .imageText,
            confidence: 0.58,
            reasons: ["low native text", "unknown page content"],
            evidence: evidence
        )
    }

    var reasons: [String] = []
    if evidence.hasTableLikeText { reasons.append("table-like text") }
    if evidence.hasRTLText { reasons.append("right-to-left text") }
    if evidence.averageLinesPerSampledPage > 45 && evidence.shortLineRatio > 0.45 {
        reasons.append("dense multi-column layout")
    }
    if !reasons.isEmpty {
        return Classification(
            bucket: .digitalComplex,
            recommendation: .enhanced,
            confidence: 0.78,
            reasons: reasons,
            evidence: evidence
        )
    }

    return Classification(
        bucket: .native,
        recommendation: .native,
        confidence: 0.70,
        reasons: ["digital text"],
        evidence: evidence
    )
}

func makeEvidence(
    pageCount: Int,
    sampledPages: Int,
    sampledTexts: [String],
    vision: (lines: Int, confidence: Float)
) -> Evidence {
    let lines = sampledTexts.flatMap {
        $0.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    let sampledPageCount = max(sampledPages, 1)
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
        sampledPages: sampledPages,
        averageDigitalTextCharactersPerPage: totalCharacters / sampledPageCount,
        averageLinesPerSampledPage: lines.count / sampledPageCount,
        shortLineRatio: ratio(shortLines, lines.count),
        numericLineRatio: ratio(numericLines, lines.count),
        hasAxisLikeText: joined.range(of: #"\b(x|y|axis|legend|figure|chart)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
        hasRTLText: joined.range(of: #"\p{Arabic}|\p{Hebrew}"#, options: .regularExpression) != nil,
        hasTableLikeText: tableLikeLines >= max(2, sampledPageCount),
        visionObservedTextLines: vision.lines,
        visionAverageConfidence: vision.confidence
    )
}

func inspectPDFPagesWithVision(_ pages: [PDFPage]) -> (lines: Int, confidence: Float) {
    var allConfidences: [Float] = []
    var lineCount = 0
    for page in pages {
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: NSSize(width: bounds.width, height: bounds.height), for: .mediaBox)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        let result = inspectCGImageWithVision(cgImage)
        lineCount += result.lines
        allConfidences.append(contentsOf: result.confidences)
    }
    return (lineCount, average(allConfidences))
}

func inspectImageWithVision(_ fileURL: URL) -> (lines: Int, confidence: Float) {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return (0, 0)
    }
    let result = inspectCGImageWithVision(cgImage)
    return (result.lines, average(result.confidences))
}

func inspectCGImageWithVision(_ cgImage: CGImage) -> (lines: Int, confidences: [Float]) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return (0, [])
    }
    let observations = request.results ?? []
    let confidences = observations.compactMap { $0.topCandidates(1).first?.confidence }
    return (observations.count, confidences)
}

func sampledPageIndexes(pageCount: Int, maximum: Int) -> [Int] {
    guard pageCount > 0, maximum > 0 else { return [] }
    let candidates = [0, pageCount / 2, pageCount - 1]
    var seen: Set<Int> = []
    return candidates.filter { seen.insert($0).inserted }.prefix(maximum).map { $0 }
}

func resolve(_ path: String, corpusRoot: URL) -> URL {
    let direct = corpusRoot.appendingPathComponent(path)
    if FileManager.default.fileExists(atPath: direct.path) { return direct }
    return corpusRoot.appendingPathComponent("docling/docling").appendingPathComponent(path)
}

func ratio(_ numerator: Int, _ denominator: Int) -> Double {
    guard denominator > 0 else { return 0 }
    return Double(numerator) / Double(denominator)
}

func average(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Float(values.count)
}

func count(_ values: [String]) -> [String: Int] {
    values.reduce(into: [:]) { result, value in
        result[value, default: 0] += 1
    }
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag),
          arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}
