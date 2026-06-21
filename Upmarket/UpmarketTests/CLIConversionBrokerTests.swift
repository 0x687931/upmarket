import XCTest
@testable import Upmarket

@MainActor
final class CLIConversionBrokerTests: XCTestCase {
    func testSuccessfulRequestWritesFormattedJSONWithoutFullSourcePath() async throws {
        let root = try makeRoot()
        let id = UUID().uuidString
        let directory = CLIHandoffPaths.handoffDirectory(id: id, root: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("plain input".utf8).write(to: directory.appendingPathComponent("input.txt"))
        try writeRequest(
            CLIConversionRequest(
                version: 1,
                inputFile: "input.txt",
                sourceDisplayName: "/Users/alice/Documents/private.txt",
                useAI: false,
                outputMode: OutputMode.json.rawValue
            ),
            to: directory
        )

        let broker = CLIConversionBroker(
            rootURL: root,
            authorize: { _, _ in },
            convert: { url, useAI, aiEngine in
                XCTAssertEqual(url.lastPathComponent, "input.txt")
                XCTAssertFalse(useAI)
                XCTAssertNil(aiEngine)
                return .success(ConversionOutput(
                    markdown: "# Converted",
                    pages: 1,
                    format: "TXT",
                    title: "Converted",
                    pipeline: .enhanced,
                    selectedPathway: .enhanced
                ))
            }
        )

        await broker.process(id: id)

        let response = try readResponse(from: directory)
        XCTAssertEqual(response.status, .success)
        XCTAssertNil(response.output)
        let outputFile = try XCTUnwrap(response.outputFile)
        XCTAssertEqual(outputFile, "output.json")
        let output = try String(contentsOf: directory.appendingPathComponent(outputFile), encoding: .utf8)
        XCTAssertTrue(output.contains(#""markdown""#))
        XCTAssertTrue(output.contains(#""source" : "private.txt""#))
        XCTAssertFalse(output.contains("/Users/alice"))
    }

    func testPurchaseRequiredWritesActionableStatusWithoutConverting() async throws {
        let root = try makeRoot()
        let id = UUID().uuidString
        let directory = try makeHandoff(root: root, id: id)

        let broker = CLIConversionBroker(
            rootURL: root,
            authorize: { _, _ in throw ProgrammaticConversionAuthorizationError.purchaseRequired },
            convert: { _, _, _ in
                XCTFail("Conversion should not run when authorization fails")
                return .failure("Should not run")
            }
        )

        await broker.process(id: id)

        let response = try readResponse(from: directory)
        XCTAssertEqual(response.status, .purchaseRequired)
        XCTAssertEqual(response.message, "Open Upmarket to unlock more conversions.")
        XCTAssertNil(response.output)
        XCTAssertNil(response.outputFile)
    }

    func testAIUnavailableWritesDedicatedStatusWithoutConsumingConversion() async throws {
        let root = try makeRoot()
        let id = UUID().uuidString
        let directory = try makeHandoff(root: root, id: id, useAI: true)

        let broker = CLIConversionBroker(
            rootURL: root,
            authorize: { useAI, _ in
                XCTAssertTrue(useAI)
                throw ProgrammaticConversionAuthorizationError.aiUnavailable
            },
            convert: { _, _, _ in
                XCTFail("Conversion should not run when AI is unavailable")
                return .failure("Should not run")
            }
        )

        await broker.process(id: id)

        let response = try readResponse(from: directory)
        XCTAssertEqual(response.status, .aiUnavailable)
        XCTAssertNil(response.output)
        XCTAssertNil(response.outputFile)
    }

    func testUnsafeManifestInputIsRejectedBeforeConversion() async throws {
        let root = try makeRoot()
        let id = UUID().uuidString
        let directory = CLIHandoffPaths.handoffDirectory(id: id, root: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeRequest(
            CLIConversionRequest(
                version: 1,
                inputFile: "../private.txt",
                sourceDisplayName: "private.txt",
                useAI: false,
                outputMode: OutputMode.markdown.rawValue
            ),
            to: directory
        )

        let broker = CLIConversionBroker(
            rootURL: root,
            authorize: { _, _ in XCTFail("Authorization should not run for invalid manifests") },
            convert: { _, _, _ in
                XCTFail("Conversion should not run for invalid manifests")
                return .failure("Should not run")
            }
        )

        await broker.process(id: id)

        let response = try readResponse(from: directory)
        XCTAssertEqual(response.status, .inputRejected)
        XCTAssertNil(response.output)
        XCTAssertNil(response.outputFile)
    }

    func testVersionTwoRequestForwardsExplicitAIEngine() async throws {
        let root = try makeRoot()
        let id = UUID().uuidString
        let directory = try makeHandoff(
            root: root,
            id: id,
            version: 2,
            useAI: true,
            aiEngine: .lfm2
        )

        let broker = CLIConversionBroker(
            rootURL: root,
            authorize: { useAI, aiEngine in
                XCTAssertTrue(useAI)
                XCTAssertEqual(aiEngine, .lfm2)
            },
            convert: { _, useAI, aiEngine in
                XCTAssertTrue(useAI)
                XCTAssertEqual(aiEngine, .lfm2)
                return .success(ConversionOutput(
                    markdown: "# LFM2",
                    pages: 1,
                    format: "PDF",
                    title: "LFM2",
                    pipeline: .ai,
                    selectedPathway: .ai
                ))
            }
        )

        await broker.process(id: id)

        let response = try readResponse(from: directory)
        XCTAssertEqual(response.status, .success)
    }

    func testExplicitAIEngineWithoutAIIsRejected() async throws {
        let root = try makeRoot()
        let id = UUID().uuidString
        let directory = try makeHandoff(
            root: root,
            id: id,
            version: 2,
            useAI: false,
            aiEngine: .granite
        )

        let broker = CLIConversionBroker(
            rootURL: root,
            authorize: { _, _ in XCTFail("Authorization should not run for invalid manifests") },
            convert: { _, _, _ in
                XCTFail("Conversion should not run for invalid manifests")
                return .failure("Should not run")
            }
        )

        await broker.process(id: id)

        let response = try readResponse(from: directory)
        XCTAssertEqual(response.status, .inputRejected)
    }

    private func makeHandoff(
        root: URL,
        id: String,
        version: Int = 1,
        useAI: Bool = false,
        aiEngine: AIEngine? = nil
    ) throws -> URL {
        let directory = CLIHandoffPaths.handoffDirectory(id: id, root: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("plain input".utf8).write(to: directory.appendingPathComponent("input.txt"))
        try writeRequest(
            CLIConversionRequest(
                version: version,
                inputFile: "input.txt",
                sourceDisplayName: "input.txt",
                useAI: useAI,
                aiEngine: aiEngine,
                outputMode: OutputMode.markdown.rawValue
            ),
            to: directory
        )
        return directory
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketCLIBrokerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func writeRequest(_ request: CLIConversionRequest, to directory: URL) throws {
        let encoder = JSONEncoder()
        try encoder.encode(request).write(to: directory.appendingPathComponent("request.json"))
    }

    private func readResponse(from directory: URL) throws -> CLIConversionResponse {
        try JSONDecoder().decode(
            CLIConversionResponse.self,
            from: Data(contentsOf: directory.appendingPathComponent("response.json"))
        )
    }
}
