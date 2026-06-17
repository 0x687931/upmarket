import Darwin
import Foundation
import PDFKit

// upmarket-cli — standalone document → Markdown converter. Runs the same Apple-native
// engines as the app in-process (PDFKit / Vision via the shared VisionDocumentExtractor,
// routing via the shared ContentClassifier — the exact same router the app uses). All
// routing/validation logic is shared via Upmarket/Shared/. PDF, images, and plain text run
// in-process; AI/Granite, Office, EPUB, and HTML are handed to the app over the handoff.

private let maxInputBytes: Int64 = 500 * 1024 * 1024

private enum ExitCode: Int32 {
    case success = 0
    case usage = 1
    case inputRejected = 2
    case purchaseRequired = 3
    case aiUnavailable = 4
    case conversionFailed = 5
    case outputWriteFailed = 6

    /// Failures that mean "this engine couldn't run" rather than "this input is bad" —
    /// safe to retry with basic conversion. Input errors (password, unsupported) are not.
    var allowsBasicFallback: Bool { self == .aiUnavailable || self == .conversionFailed }
}

/// What the user asked for. `auto` lets the Apple classifier pick.
private enum Engine {
    case auto       // --auto (default): classify the document, pick the best route
    case native     // --basic / --native: in-process Apple (PDFKit / Vision)
    case complex    // --pro   / --complex: native complex-PDF path (Vision quality selection)
    case ai         // --max   / --ai:     native AI path (Vision; Granite runs in the app)
}

/// The concrete engine actually executed for a document.
private enum Pathway: String {
    case pdfkit = "native-pdfkit"
    case vision = "native-vision"
    case text   = "native-text"
}

private enum OutputFormat: String {
    case markdown, frontmatter, json
    var fileExtension: String { self == .json ? "json" : "md" }
}

private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "webp", "bmp", "heic", "heif"]

private struct Options {
    let inputURLs: [URL]
    let outputURL: URL?
    let engine: Engine
    let outputFormat: OutputFormat
    let force: Bool
    let debug: Bool
}

private struct ConvertedDocument {
    var markdown: String
    let pages: Int
    let format: String
    let title: String
    var pipeline: String
    var tables: [TableRepair.StructuredTable] = []
}

@main
private enum UpmarketCLI {
    static func main() async {
        do {
            let options = try parse(arguments: Array(CommandLine.arguments.dropFirst()))
            try await run(options)
            exit(ExitCode.success.rawValue)
        } catch let error as CommandError {
            if !error.message.isEmpty { fputs("\(error.message)\n", stderr) }
            exit(error.exitCode.rawValue)
        } catch {
            fputs("Upmarket could not complete this conversion: \(error.localizedDescription)\n", stderr)
            exit(ExitCode.conversionFailed.rawValue)
        }
    }

    // MARK: - Argument parsing

    private static func parse(arguments: [String]) throws -> Options {
        guard !arguments.isEmpty else { printUsage(); throw CommandError(.usage, "") }
        if isHelp(arguments) { printUsage(); throw CommandError(.success, "") }

        var remaining = arguments
        if remaining.first == "convert" { remaining.removeFirst() }

        var inputs: [String] = []
        var output: String?
        var engine: Engine = .auto
        var force = false
        var debug = false
        var format: OutputFormat = .markdown

        var index = 0
        while index < remaining.count {
            let argument = remaining[index]
            switch argument {
            case "-h", "--help": printUsage(); throw CommandError(.success, "")
            case "--auto":                       engine = .auto;    index += 1
            case "--basic", "--native":          engine = .native;  index += 1
            case "--pro", "--complex":           engine = .complex; index += 1
            case "--max", "--ai":                engine = .ai;      index += 1
            case "--debug", "-v", "--verbose":   debug = true;      index += 1
            case "--force":                      force = true;      index += 1
            case "-o", "--output":
                guard index + 1 < remaining.count else { throw CommandError(.usage, "Missing output file.") }
                output = remaining[index + 1]; index += 2
            case "--format":
                guard index + 1 < remaining.count, let parsed = OutputFormat(rawValue: remaining[index + 1]) else {
                    throw CommandError(.usage, "Output format must be markdown, frontmatter, or json.")
                }
                format = parsed; index += 2
            default:
                guard !argument.hasPrefix("-") else { throw CommandError(.usage, "Unknown option: \(argument)") }
                inputs.append(argument); index += 1
            }
        }

        guard !inputs.isEmpty else { printUsage(); throw CommandError(.usage, "At least one input file is required.") }
        if output != nil && inputs.count > 1 { throw CommandError(.usage, "--output can only be used with a single input file.") }

        return Options(
            inputURLs: inputs.map { URL(fileURLWithPath: $0).standardizedFileURL },
            outputURL: output.map { URL(fileURLWithPath: $0).standardizedFileURL },
            engine: engine,
            outputFormat: format,
            force: force,
            debug: debug
        )
    }

    private static func isHelp(_ a: [String]) -> Bool {
        a == ["--help"] || a == ["-h"] || a == ["convert", "--help"] || a == ["convert", "-h"]
    }

    // MARK: - Conversion driver

    private static func run(_ options: Options) async throws {
        try requireProEntitlement(for: options.engine)
        for inputURL in options.inputURLs {
            let outURL = outputURL(for: inputURL, explicit: options.outputURL, format: options.outputFormat)
            try validateInput(inputURL)
            try validateOutputDestination(outURL, force: options.force)

            switch try await route(for: inputURL, engine: options.engine, debug: options.debug) {
            case .broker(let useAI):
                // AI/Granite, Office, EPUB, HTML — handed to the app, which owns those engines.
                let text = try await brokerToApp(
                    inputURL: inputURL, useAI: useAI,
                    outputMode: options.outputFormat.rawValue, debug: options.debug)
                try write(text, to: outURL, force: options.force)

            case .inProcess(let pathway):
                debugLog("file=\(inputURL.lastPathComponent) engine=\(pathway.rawValue)", options.debug)
                let start = Date()
                var document = try await execute(pathway: pathway, inputURL: inputURL, debug: options.debug)
                document = validateAndRepair(document, debug: options.debug)
                debugLog("pages=\(document.pages) pipeline=\(document.pipeline) elapsed=\(String(format: "%.2fs", Date().timeIntervalSince(start)))", options.debug)
                let rendered = render(document, sourceName: inputURL.lastPathComponent, mode: options.outputFormat)
                try write(rendered, to: outURL, force: options.force)
            }
        }
    }

    /// The CLI is a Pro/Max feature. Enforced via the tier snapshot the app writes
    /// (StoreManager); the unsandboxed CLI can't read StoreKit itself.
    private static func requireProEntitlement(for engine: Engine) throws {
        guard let snap = TierSnapshot.read(), snap.purchased, snap.tier >= TierSnapshot.proTier else {
            throw CommandError(.purchaseRequired,
                "The Upmarket command-line tool requires Upmarket Pro. Open Upmarket to upgrade.")
        }
        if engine == .ai, snap.tier < TierSnapshot.maxTier {
            throw CommandError(.aiUnavailable,
                "Upmarket AI requires Upmarket Max. Open Upmarket to upgrade.")
        }
    }

    /// Where a document runs: in-process (the CLI's Apple engines) or brokered to the app.
    private enum Route {
        case inProcess(Pathway)
        case broker(useAI: Bool)
    }

    /// The single routing decision, shared with the app via ContentClassifier. `--auto`/`--pro`
    /// let the classifier choose; `--max/--ai` forces AI; `--basic` forces the in-process path.
    /// PDF/image/text run in-process; AI/Office/EPUB/HTML are handed to the app.
    private static func route(for inputURL: URL, engine: Engine, debug: Bool) async throws -> Route {
        if engine == .ai { return .broker(useAI: true) }

        let ext = inputURL.pathExtension.lowercased()
        func nativeRoute() -> Route {
            if ext == "pdf" { return .inProcess(.pdfkit) }   // execute() falls back to Vision if no text
            if imageExtensions.contains(ext) { return .inProcess(.vision) }
            if ext == "txt" || ext == "md" || ext == "csv" { return .inProcess(.text) }
            return .broker(useAI: false)                     // Office/EPUB/HTML/etc. → app
        }

        // --basic/--native forces the in-process Apple path; everything else routes by content.
        if engine == .native { return nativeRoute() }

        guard let classification = await ContentClassifier.classify(fileURL: inputURL) else {
            debugLog("auto: classification unavailable → format default", debug)
            return nativeRoute()
        }
        debugLog("auto: classifier=\(classification.recommendedPathway.rawValue) kind=\(classification.kind.diagnosticLabel)", debug)
        switch classification.recommendedPathway {
        case .pdfKit:                                       return .inProcess(.pdfkit)
        case .visionOCR, .enhanced:                         return .inProcess(.vision)
        case .nativeText:                                   return .inProcess(.text)
        case .ai:                                           return .broker(useAI: true)
        case .nativeOffice, .nativeHTML, .nativeEPUB, .speech, .metadata:
                                                            return .broker(useAI: false)
        }
    }

    /// Hands a conversion to the running app over the shared handoff: write request.json + the
    /// input into CLIHandoffs/<id>/, open upmarket://convert?cli=<id>, poll for response.json.
    private static func brokerToApp(inputURL: URL, useAI: Bool, outputMode: String, debug: Bool) async throws -> String {
        let fm = FileManager.default
        guard let root = CLIHandoffPaths.rootURL(fileManager: fm) else {
            throw CommandError(.conversionFailed, "Open the Upmarket app to convert this document.")
        }
        let id = UUID().uuidString
        let finalDir = CLIHandoffPaths.handoffDirectory(id: id, root: root)
        // Stage the request beside its destination, then atomic-move it in, so the app's handoff
        // watcher only ever sees a complete <uuid>/ (request.json + input) — no partial-read race.
        let stagingDir = finalDir.deletingLastPathComponent().appendingPathComponent("\(id).staging", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: finalDir); try? fm.removeItem(at: stagingDir) }

        let inputName = "input." + (inputURL.pathExtension.isEmpty ? "dat" : inputURL.pathExtension.lowercased())
        try fm.copyItem(at: inputURL, to: stagingDir.appendingPathComponent(inputName))
        let request = CLIConversionRequest(
            version: 1, inputFile: inputName, sourceDisplayName: inputURL.lastPathComponent,
            useAI: useAI, outputMode: outputMode)
        try JSONEncoder().encode(request).write(to: stagingDir.appendingPathComponent("request.json"), options: .atomic)
        try fm.moveItem(at: stagingDir, to: finalDir)

        debugLog("brokering to app: id=\(id) useAI=\(useAI)", debug)
        launchAppIfNeeded()   // any running instance's watcher services the request

        let responseURL = finalDir.appendingPathComponent("response.json")
        let deadline = Date().addingTimeInterval(600)   // VLM over many pages is slow
        while !fm.fileExists(atPath: responseURL.path) {
            if Date() > deadline {
                throw CommandError(.conversionFailed, "Timed out waiting for the Upmarket app. Make sure Upmarket is installed.")
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        let response = try JSONDecoder().decode(CLIConversionResponse.self, from: Data(contentsOf: responseURL))
        switch response.status {
        case .success:
            guard let outputFile = response.outputFile else {
                throw CommandError(.conversionFailed, "Upmarket returned no output.")
            }
            return try String(contentsOf: finalDir.appendingPathComponent(outputFile), encoding: .utf8)
        case .purchaseRequired:
            throw CommandError(.purchaseRequired, response.message ?? "Open Upmarket to unlock more conversions.")
        case .aiUnavailable:
            throw CommandError(.aiUnavailable, response.message ?? "Upmarket AI is not available for this conversion.")
        case .inputRejected:
            throw CommandError(.inputRejected, response.message ?? "Upmarket couldn't read this document.")
        case .conversionFailed:
            throw CommandError(.conversionFailed, response.message ?? "Upmarket couldn't convert this document.")
        }
    }

    /// Launch Upmarket in the background by bundle id (no-op if already running) so its handoff
    /// watcher can service the request. No URL scheme → no LaunchServices routing fragility.
    private static func launchAppIfNeeded() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-b", "com.upmarket.app"]
        try? process.run()
        process.waitUntilExit()
    }

    private static func execute(pathway: Pathway, inputURL: URL, debug: Bool) async throws -> ConvertedDocument {
        switch pathway {
        case .pdfkit:
            if let native = nativePDFKit(inputURL) { return native }
            debugLog("PDFKit found no extractable text → Vision OCR", debug)
            return try await nativeVisionPDF(inputURL)
        case .vision:
            return inputURL.pathExtension.lowercased() == "pdf"
                ? try await nativeVisionPDF(inputURL)
                : try await nativeVisionImage(inputURL)
        case .text:
            return try nativeText(inputURL)
        }
    }

    // MARK: - Native engines (in-process)

    /// Digital-PDF text via the shared `PDFConverter` (same engine as the app, incl. hyphen
    /// cleanup + heading detection). Returns nil for locked or text-less (scanned) PDFs so the
    /// caller can fall back to Vision OCR.
    private static func nativePDFKit(_ inputURL: URL) -> ConvertedDocument? {
        guard let result = try? PDFConverter.convert(url: inputURL),
              !result.isLikelyScanned,
              !result.markdown.isEmpty else { return nil }
        return ConvertedDocument(markdown: result.markdown, pages: result.pageCount, format: "PDF",
                                 title: inputURL.deletingPathExtension().lastPathComponent, pipeline: Pathway.pdfkit.rawValue)
    }

    private static func nativeVisionPDF(_ inputURL: URL) async throws -> ConvertedDocument {
        let result = try await VisionDocumentExtractor.extract(pdfURL: inputURL)
        return ConvertedDocument(markdown: result.markdown, pages: result.pageCount, format: "PDF",
                                 title: inputURL.deletingPathExtension().lastPathComponent,
                                 pipeline: Pathway.vision.rawValue, tables: result.structuredTables)
    }

    private static func nativeVisionImage(_ inputURL: URL) async throws -> ConvertedDocument {
        let result = try await VisionDocumentExtractor.extract(imageURL: inputURL)
        return ConvertedDocument(markdown: result.markdown, pages: result.pageCount,
                                 format: inputURL.pathExtension.uppercased(),
                                 title: inputURL.deletingPathExtension().lastPathComponent,
                                 pipeline: Pathway.vision.rawValue, tables: result.structuredTables)
    }

    private static func nativeText(_ inputURL: URL) throws -> ConvertedDocument {
        let contents = try String(contentsOf: inputURL, encoding: .utf8)
        return ConvertedDocument(markdown: contents, pages: 1, format: inputURL.pathExtension.uppercased(),
                                 title: inputURL.deletingPathExtension().lastPathComponent, pipeline: Pathway.text.rawValue)
    }

    // MARK: - Shared validation / repair

    /// Repairs missing tables when structured table data is available (Vision), and emits
    /// quality metrics under --debug — using the same validators the app runs.
    private static func validateAndRepair(_ document: ConvertedDocument, debug: Bool) -> ConvertedDocument {
        var result = document
        if !document.tables.isEmpty {
            let report = DocumentStructureValidator.validateAndRepair(
                originalMarkdown: document.markdown,
                convertedMarkdown: document.markdown,
                originalTables: document.tables
            )
            if let repaired = report.reformattedMarkdown {
                result.markdown = repaired
                debugLog("structure repair applied (\(report.issues.count) issue(s))", debug)
            }
        }
        if debug {
            let validation = ConversionValidator.validate(
                originalMarkdown: result.markdown,
                convertedMarkdown: result.markdown,
                tablesDetected: result.tables.count,
                listsDetected: 0,
                pagesProcessed: result.pages
            )
            debugLog("validation: words=\(validation.metrics.outputWordCount) chars=\(validation.metrics.outputCharCount) tables=\(validation.metrics.tablesDetected)", debug)
            validation.warnings.forEach { debugLog("warning: \($0)", debug) }
        }
        return result
    }

    // MARK: - Input / output

    private static func outputURL(for inputURL: URL, explicit: URL?, format: OutputFormat) -> URL {
        explicit ?? inputURL.deletingPathExtension().appendingPathExtension(format.fileExtension)
    }

    private static func validateInput(_ url: URL) throws {
        guard ToolFormatCapabilityMatrix.accepts(url) else {
            throw CommandError(.inputRejected, "Unsupported input format: .\(url.pathExtension)")
        }
        guard (try? url.checkResourceIsReachable()) == true else {
            throw CommandError(.inputRejected, "Input file does not exist or cannot be reached.")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CommandError(.inputRejected, "Input must be a regular file.") }
        guard values.isReadable != false else { throw CommandError(.inputRejected, "Input file is not readable.") }
        guard let fileSize = values.fileSize, Int64(fileSize) <= maxInputBytes else {
            throw CommandError(.inputRejected, "Input file is too large. Maximum size is 500 MB.")
        }
    }

    private static func validateOutputDestination(_ url: URL, force: Bool) throws {
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CommandError(.outputWriteFailed, "Output directory does not exist.")
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw CommandError(.outputWriteFailed, "Output directory is not writable.")
        }
        if FileManager.default.fileExists(atPath: url.path), !force {
            throw CommandError(.outputWriteFailed, "Output file already exists. Pass --force to replace it.")
        }
    }

    // MARK: - Output formatting

    private static func render(_ document: ConvertedDocument, sourceName: String, mode: OutputFormat) -> String {
        switch mode {
        case .markdown:    return document.markdown
        case .frontmatter: return frontmatter(for: document, sourceName: sourceName) + "\n" + document.markdown
        case .json:        return json(for: document, sourceName: sourceName)
        }
    }

    private static func frontmatter(for document: ConvertedDocument, sourceName: String) -> String {
        [
            "---",
            "title: \(yamlString(document.title))",
            "source: \(yamlString(sourceName))",
            "converted: \(yamlString(ISO8601DateFormatter().string(from: Date())))",
            "format: \(yamlString(document.format))",
            "pipeline: \(yamlString(document.pipeline))",
            "pages: \(document.pages)",
            "word_count: \(wordCount(document.markdown))",
            "---", ""
        ].joined(separator: "\n")
    }

    private static func json(for document: ConvertedDocument, sourceName: String) -> String {
        struct Payload: Encodable { let title: String; let markdown: String; let metadata: Metadata }
        struct Metadata: Encodable {
            let source: String; let converted: String; let format: String
            let pipeline: String; let pages: Int; let word_count: Int
        }
        let payload = Payload(
            title: document.title, markdown: document.markdown,
            metadata: Metadata(source: sourceName, converted: ISO8601DateFormatter().string(from: Date()),
                               format: document.format, pipeline: document.pipeline, pages: document.pages,
                               word_count: wordCount(document.markdown))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            return #"{"title":"","markdown":"","metadata":{}}"#
        }
        return text
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.filter { token in token.contains { $0.isLetter || $0.isNumber } }.count
    }

    private static func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static func write(_ output: String, to url: URL, force: Bool) throws {
        try validateOutputDestination(url, force: force)
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try Data(output.utf8).write(to: temporaryURL, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                guard force else { throw CommandError(.outputWriteFailed, "Output file already exists. Pass --force to replace it.") }
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch let error as CommandError {
            try? FileManager.default.removeItem(at: temporaryURL); throw error
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw CommandError(.outputWriteFailed, "Could not write output file.")
        }
    }

    private static func debugLog(_ message: String, _ enabled: Bool) {
        guard enabled else { return }
        fputs("[upmarket] \(message)\n", stderr)
    }

    /// Always-visible note to stderr (e.g. a tier fallback). Keeps stdout/output clean.
    private static func notice(_ message: String) {
        fputs("upmarket: \(message)\n", stderr)
    }

    private static func printUsage() {
        print("""
        Usage:
          upmarket-cli <input...> [routing] [--format markdown|frontmatter|json] [--force] [--debug]
          upmarket-cli -h | --help

        Routing (choose at most one; default --auto):
          --auto                  Let Upmarket inspect the document and pick the best route.
          --basic, --native       In-process Apple conversion (PDFKit for text, Vision OCR for scans).
          --pro, --complex        Enhanced conversion (layout + table extraction).
          --max, --ai             AI conversion for scanned/complex documents.

        If a requested Enhanced/AI runtime isn't installed, Upmarket falls back to basic
        conversion (with a note) rather than failing — open the app to enable those tiers.

        Options:
          -o, --output <path>     Write output to this file (single input only).
          --format <format>       Output format: markdown, frontmatter, or json.
          --force                 Replace an existing output file.
          --debug, -v             Print routing, timing, and validation details to stderr.
          -h, --help              Show this help text.

        Examples:
          upmarket-cli report.pdf                 # writes report.md beside it
          upmarket-cli *.pdf --pro
          upmarket-cli scan.pdf --auto --debug
          upmarket-cli notes.txt --format json
        """)
    }
}

private struct CommandError: Error {
    let exitCode: ExitCode
    let message: String
    init(_ exitCode: ExitCode, _ message: String) { self.exitCode = exitCode; self.message = message }
}
