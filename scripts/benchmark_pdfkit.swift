import Foundation
import PDFKit

struct Manifest: Decodable {
    struct Document: Decodable {
        let id: String
        let file: String
        let category: String
    }
    let documents: [Document]
}

struct Result: Encodable {
    let id: String
    let file: String
    let markdown: String
    let elapsed_seconds: Double
    let error: String?
}

func markdown(page: PDFPage, text: String) -> String {
    let rawLines = text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    let lines = repairSingleCharacterLabels(rawLines)

    if isLikelyFigureText(lines) {
        return """
        Extracted figure text:

        ```text
        \(lines.joined(separator: "\n"))
        ```
        """
    }

    var result: [String] = []
    for (lineIndex, line) in lines.enumerated() {
        let isLikelyHeading = line.count < 80
            && !line.hasSuffix(".")
            && !line.hasSuffix(",")
            && lineIndex < 3
            && line.rangeOfCharacter(from: .letters) != nil
        result.append(isLikelyHeading && lineIndex == 0 ? "## \(line)" : line)
    }
    return result.joined(separator: "\n")
}

func repairSingleCharacterLabels(_ lines: [String]) -> [String] {
    var result: [String] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        if index + 1 < lines.count,
           line.count == 1,
           lines[index + 1].count == 1,
           line.rangeOfCharacter(from: .letters) != nil,
           lines[index + 1].rangeOfCharacter(from: .letters) != nil {
            result.append(line + lines[index + 1])
            index += 2
            continue
        }
        result.append(line)
        index += 1
    }
    return result
}

func isLikelyFigureText(_ lines: [String]) -> Bool {
    guard !lines.isEmpty, lines.count <= 14 else { return false }
    let joined = lines.joined(separator: " ")
    let words = joined.split { $0.isWhitespace }
    guard words.count <= 24 else { return false }

    let numericLines = lines.filter { line in
        line.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil
    }.count
    let sentenceLines = lines.filter { $0.hasSuffix(".") || $0.hasSuffix(":") }.count
    let hasAxisLikeText = joined.contains("[") || joined.contains("]") || joined.contains("/") || joined.contains("MeV")

    return sentenceLines == 0 && (numericLines >= 3 || hasAxisLikeText)
}

func convert(path: String) throws -> (String, Int) {
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
        throw NSError(domain: "PDFKitBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open PDF"])
    }
    if document.isLocked {
        throw NSError(domain: "PDFKitBenchmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "password protected"])
    }
    var pages: [String] = []
    for pageIndex in 0..<document.pageCount {
        guard let page = document.page(at: pageIndex) else { continue }
        let text = page.string ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        pages.append(markdown(page: page, text: text))
    }
    return (pages.joined(separator: "\n\n---\n\n"), document.pageCount)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let corpus = root.appendingPathComponent("tests/corpus")
let manifestURL = corpus.appendingPathComponent("manifest.json")
let manifestData = try Data(contentsOf: manifestURL)
let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

for document in manifest.documents where document.category == "pdf" {
    var fileURL = corpus.appendingPathComponent(document.file)
    if !FileManager.default.fileExists(atPath: fileURL.path) {
        fileURL = corpus.appendingPathComponent("docling/docling").appendingPathComponent(document.file)
    }

    let start = Date()
    do {
        let (markdown, _) = try convert(path: fileURL.path)
        let result = Result(
            id: document.id,
            file: document.file,
            markdown: markdown,
            elapsed_seconds: Date().timeIntervalSince(start),
            error: nil
        )
        print(String(data: try encoder.encode(result), encoding: .utf8)!)
    } catch {
        let result = Result(
            id: document.id,
            file: document.file,
            markdown: "",
            elapsed_seconds: Date().timeIntervalSince(start),
            error: error.localizedDescription
        )
        print(String(data: try encoder.encode(result), encoding: .utf8)!)
    }
}
