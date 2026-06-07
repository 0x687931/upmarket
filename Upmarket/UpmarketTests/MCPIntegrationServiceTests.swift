import XCTest
@testable import Upmarket

@MainActor
final class MCPIntegrationServiceTests: XCTestCase {
    func testMissingStateDefaultsToDisabled() throws {
        let root = try makeRoot()
        let service = makeService(root: root)

        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.status, .disabled)
    }

    func testInvalidStateDefaultsToDisabled() throws {
        let root = try makeRoot()
        let stateDirectory = root.appendingPathComponent("MCP", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try Data("{invalid".utf8).write(to: stateDirectory.appendingPathComponent("advertisement.json"))

        let service = makeService(root: root)

        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.status, .disabled)
    }

    func testEnabledStatePersistsAndBuildsSnippet() throws {
        let root = try makeRoot()
        let bundle = try makeBundleWithMCPTool()
        let service = makeService(root: root, bundleURL: bundle)

        service.setAdvertisementEnabled(true)

        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(service.status, .ready)
        XCTAssertTrue(service.mcpJSONSnippet.contains(#""upmarket""#))
        XCTAssertTrue(service.mcpJSONSnippet.contains(#""command""#))
        XCTAssertTrue(service.mcpJSONSnippet.contains("upmarket-mcp"))

        let reloaded = makeService(root: root, bundleURL: bundle)
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertEqual(reloaded.status, .ready)
    }

    func testAddToLMStudioEnablesAndUsesEncodedCurrentCommandPath() throws {
        let root = try makeRoot()
        let bundle = try makeBundleWithMCPTool()
        var openedURL: URL?
        let service = makeService(root: root, bundleURL: bundle, urlOpener: { openedURL = $0 })

        service.addToLMStudio()

        XCTAssertTrue(service.isEnabled)
        let url = try XCTUnwrap(openedURL)
        XCTAssertEqual(url.scheme, "lmstudio")
        XCTAssertEqual(url.host, "add_mcp")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let name = components.queryItems?.first { $0.name == "name" }?.value
        let config = components.queryItems?.first { $0.name == "config" }?.value
        XCTAssertEqual(name, "upmarket")
        let encoded = try XCTUnwrap(config)
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object["command"], bundle.appendingPathComponent("Contents/MacOS/upmarket-mcp").path)
    }

    func testCopySnippetWritesOnlyServerEntry() throws {
        let root = try makeRoot()
        let bundle = try makeBundleWithMCPTool()
        var copied = ""
        let service = makeService(root: root, bundleURL: bundle, pasteboardWriter: { copied = $0 })

        service.copySnippet()

        XCTAssertTrue(copied.contains(#""upmarket""#))
        XCTAssertTrue(copied.contains(#""command""#))
        XCTAssertFalse(copied.contains("mcpServers"))
    }

    func testMovedAppReportsReAddStatus() throws {
        let root = try makeRoot()
        let firstBundle = try makeBundleWithMCPTool(name: "UpmarketOne.app")
        let secondBundle = try makeBundleWithMCPTool(name: "UpmarketTwo.app")
        let first = makeService(root: root, bundleURL: firstBundle)
        first.setAdvertisementEnabled(true)

        let moved = makeService(root: root, bundleURL: secondBundle)

        XCTAssertEqual(moved.status, .appMoved)
    }

    private func makeService(
        root: URL,
        bundleURL: URL? = nil,
        pasteboardWriter: @escaping (String) -> Void = { _ in },
        urlOpener: @escaping (URL) -> Void = { _ in }
    ) -> MCPIntegrationService {
        let bundle = bundleURL ?? root.appendingPathComponent("Upmarket.app", isDirectory: true)
        return MCPIntegrationService(
            rootURLProvider: { root },
            bundleURLProvider: { bundle },
            fileManager: .default,
            dateProvider: { Date(timeIntervalSince1970: 1_800_000_000) },
            pasteboardWriter: pasteboardWriter,
            urlOpener: urlOpener
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketMCPIntegrationServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func makeBundleWithMCPTool(name: String = "Upmarket.app") throws -> URL {
        let root = try makeRoot()
        let bundle = root.appendingPathComponent(name, isDirectory: true)
        let executableDirectory = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        let tool = executableDirectory.appendingPathComponent("upmarket-mcp")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return bundle
    }
}
