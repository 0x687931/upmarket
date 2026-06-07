import XCTest
@testable import Upmarket

@MainActor
final class WatchedFolderServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchedFolderServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        suiteName = "WatchedFolderServiceTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
        suite.removePersistentDomain(forName: suiteName)
        OutputPreference.shared.mode = .markdown
    }

    override func tearDownWithError() throws {
        suite.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        suite = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testAddFolderPersistsBookmarkBackedConfiguration() throws {
        let folderURL = try makeDirectory("Inbox")
        let service = makeService()

        try service.addFolder(folderURL)

        XCTAssertEqual(service.folders.count, 1)
        XCTAssertEqual(service.folders.first?.displayName, "Inbox")
        XCTAssertFalse(service.folders.first?.bookmarkData.isEmpty ?? true)

        let reloaded = makeService()
        XCTAssertEqual(reloaded.folders.count, 1)
        XCTAssertEqual(reloaded.folders.first?.displayName, "Inbox")
    }

    func testScanEnqueuesSupportedStableFileOnlyOnce() async throws {
        let folderURL = try makeDirectory("Inbox")
        try write("hello", to: folderURL.appendingPathComponent("paper.txt"))
        try write("ignored", to: folderURL.appendingPathComponent("archive.bin"))
        var convertedNames: [String] = []
        let service = makeService { url in
            convertedNames.append(url.lastPathComponent)
            return .success(Self.output(title: "Paper"))
        }
        try service.addFolder(folderURL)
        let id = try XCTUnwrap(service.folders.first?.id)

        await service.scanFolder(id: id)
        await service.scanFolder(id: id)

        XCTAssertEqual(convertedNames, ["paper.txt"])
    }

    func testIncludeAndExcludeRulesFilterCandidates() async throws {
        let folderURL = try makeDirectory("Inbox")
        try write("keep", to: folderURL.appendingPathComponent("keep.pdf"))
        try write("skip", to: folderURL.appendingPathComponent("skip.pdf"))
        try write("note", to: folderURL.appendingPathComponent("note.txt"))
        var convertedNames: [String] = []
        let service = makeService { url in
            convertedNames.append(url.lastPathComponent)
            return .success(Self.output(title: "Filtered"))
        }
        service.includePatterns = "*.pdf"
        service.excludePatterns = "skip"
        try service.addFolder(folderURL)
        let id = try XCTUnwrap(service.folders.first?.id)

        await service.scanFolder(id: id)

        XCTAssertEqual(convertedNames, ["keep.pdf"])
    }

    func testDefaultRulesIgnoreGeneratedOutputsAndTemporaryFiles() async throws {
        let folderURL = try makeDirectory("Inbox")
        try write("keep", to: folderURL.appendingPathComponent("keep.pdf"))
        try write("converted", to: folderURL.appendingPathComponent("converted.md"))
        try write("json", to: folderURL.appendingPathComponent("converted.json"))
        try write("partial", to: folderURL.appendingPathComponent("download.part"))
        var convertedNames: [String] = []
        let service = makeService { url in
            convertedNames.append(url.lastPathComponent)
            return .success(Self.output(title: "Filtered"))
        }
        try service.addFolder(folderURL)
        let id = try XCTUnwrap(service.folders.first?.id)

        await service.scanFolder(id: id)

        XCTAssertEqual(convertedNames, ["keep.pdf"])
    }

    func testChosenOutputFolderWritesFormattedResult() async throws {
        let inboxURL = try makeDirectory("Inbox")
        let outputURL = try makeDirectory("Outbox")
        try write("hello", to: inboxURL.appendingPathComponent("paper.txt"))
        let service = makeService { _ in
            .success(Self.output(title: "Converted Paper", markdown: "# Converted"))
        }
        try service.addFolder(inboxURL)
        let id = try XCTUnwrap(service.folders.first?.id)
        try service.setOutputFolder(outputURL, for: id)

        await service.scanFolder(id: id)

        let written = outputURL.appendingPathComponent("Converted Paper.md")
        XCTAssertEqual(try String(contentsOf: written), "# Converted")
    }

    func testRemovingFolderStopsExplicitScans() async throws {
        let folderURL = try makeDirectory("Inbox")
        try write("hello", to: folderURL.appendingPathComponent("paper.txt"))
        var convertedNames: [String] = []
        let service = makeService { url in
            convertedNames.append(url.lastPathComponent)
            return .success(Self.output(title: "Paper"))
        }
        try service.addFolder(folderURL)
        let id = try XCTUnwrap(service.folders.first?.id)

        service.removeFolder(id: id)
        await service.scanFolder(id: id)

        XCTAssertTrue(convertedNames.isEmpty)
    }

    private func makeService(
        convert: @escaping WatchedFolderService.Convert = { _ in
            .success(WatchedFolderServiceTests.output(title: "Converted"))
        }
    ) -> WatchedFolderService {
        WatchedFolderService(
            userDefaults: suite,
            stabilityDelayNanoseconds: 0,
            convert: convert,
            notify: { _, _ in }
        )
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func output(
        title: String,
        markdown: String = "# Watched"
    ) -> ConversionOutput {
        ConversionOutput(
            markdown: markdown,
            pages: 1,
            format: "txt",
            title: title,
            pipeline: .fast,
            selectedPathway: .pdfKit
        )
    }
}
